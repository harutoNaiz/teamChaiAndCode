import os
import shutil
import tempfile
import unittest

from local_index import LocalTextIndex
from scanner_pipeline import (
    BackgroundFileSystemCronWatcher,
    CsvCatalogStore,
    DefaultLocalOcrEngine,
    LocalScannerPipeline,
    ModelCapability,
    OpenRouterMultimodalExtractor,
    RefreshScanner,
)


class TestScannerPipeline(unittest.TestCase):
    def setUp(self):
        self.index = LocalTextIndex()
        # Host fixtures use an injected test backend. The production Python
        # adapter intentionally has no byte-decoding OCR fallback.
        def fixture_ocr(source):
            raw = source if isinstance(source, bytes) else open(source, "rb").read()
            return raw.decode("utf-8"), 0.95

        self.ocr = DefaultLocalOcrEngine(backend_runner=fixture_ocr)
        self.pipeline = LocalScannerPipeline(index_store=self.index, ocr_engine=self.ocr)
        self.test_dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_goal_1_authorised_photo_ocr_is_searchable(self):
        """Goal 1: Authorised photo OCR is searchable and returns open_uri."""
        photo_uri = "content://com.android.externalstorage.documents/document/photo42"
        photo_bytes = b"Government of India Unique Identification Authority Aadhaar 9988 7766 5544"
        
        result = self.pipeline.process_source(
            source_uri=photo_uri,
            display_name="unhelpfully-named-photo.jpg",
            mime_type="image/jpeg",
            content=photo_bytes,
            has_permission=True,
            modified_at=1789590600000,
        )

        self.assertEqual("indexed", result.status)
        self.assertEqual(photo_uri, result.open_uri)

        search_results = self.index.search("Aadhaar 9988")
        self.assertGreater(len(search_results), 0)
        top = search_results[0]
        self.assertEqual("image_ocr", top["content_type"])
        self.assertEqual(photo_uri, top["open_uri"])
        self.assertIn("9988 7766 5544", top["transcription"])
        self.assertEqual(1789590600000, top["modified_at"])

    def test_goal_2_pdf_or_document_page_keeps_provenance(self):
        """Goal 2: PDF or document page keeps provenance (page, content_type, open_uri)."""
        pdf_uri = "content://com.android.externalstorage.documents/document/annual_calendar.pdf"
        page2_bytes = b"Chai and Code budget review and planning meeting on 25 October 2026"

        result = self.pipeline.process_source(
            source_uri=pdf_uri,
            display_name="annual_calendar.pdf",
            mime_type="application/pdf",
            content=page2_bytes,
            page=2,
            has_permission=True,
            modified_at=1789590600000,
        )

        self.assertEqual("indexed", result.status)
        search_results = self.index.search("budget review")
        self.assertGreater(len(search_results), 0)
        top = search_results[0]
        self.assertEqual("pdf_ocr", top["content_type"])
        self.assertEqual(2, top["page"])
        self.assertEqual(pdf_uri, top["open_uri"])
        self.assertIn("25 October 2026", top["transcription"])

    def test_goal_3_changed_source_replaces_old_text(self):
        """Goal 3: Changed source replaces old text in index."""
        doc_uri = "content://com.android.externalstorage.documents/document/offer.txt"
        v1_bytes = b"Old obsolete contract terms for alpha project"
        v2_bytes = b"Fresh updated agreement terms for beta project"

        res1 = self.pipeline.process_source(
            source_uri=doc_uri,
            display_name="offer.txt",
            mime_type="text/plain",
            content=v1_bytes,
            modified_at=1000,
        )
        self.assertEqual("indexed", res1.status)
        self.assertEqual(1, len(self.index.search("obsolete")))

        res2 = self.pipeline.process_source(
            source_uri=doc_uri,
            display_name="offer.txt",
            mime_type="text/plain",
            content=v2_bytes,
            modified_at=2000,
        )
        self.assertEqual("indexed", res2.status)

        self.assertEqual(0, len(self.index.search("obsolete")))
        new_search = self.index.search("updated agreement")
        self.assertEqual(1, len(new_search))
        self.assertEqual(doc_uri, new_search[0]["open_uri"])

    def test_background_filesystem_cron_watcher(self):
        """Tests the background cron watcher scanning and indexing incoming files."""
        watcher = BackgroundFileSystemCronWatcher(pipeline=self.pipeline, watch_paths=[self.test_dir])
        
        # Add sample image and text files into watched directory
        txt_path = os.path.join(self.test_dir, "meeting.txt")
        with open(txt_path, "w") as f:
            f.write("Sprint review meeting with Vidya and Tushar")

        img_path = os.path.join(self.test_dir, "receipt.png")
        with open(img_path, "wb") as f:
            f.write(b"Swiggy Order Chai and Samosa Total 350 INR")

        indexed_count = watcher.scan_once()
        self.assertEqual(2, indexed_count)

        # Verify items are searchable in memory
        res = self.index.search("Sprint review")
        self.assertEqual(1, len(res))
        self.assertEqual("meeting.txt", res[0]["display_name"])

        res_ocr = self.index.search("Swiggy Order")
        self.assertEqual(1, len(res_ocr))
        self.assertEqual("receipt.png", res_ocr[0]["display_name"])

    def test_multimodal_extractor_fallback(self):
        """Tests the OpenRouter multimodal extractor with graceful fallback."""
        extractor = OpenRouterMultimodalExtractor(api_key="mock-key", fallback_engine=self.ocr)
        text, conf = extractor.reason_and_extract(b"Sample multimodal document text", "image/png")
        self.assertIn("Sample multimodal document text", text)
        self.assertGreater(conf, 0.0)




class TestCsvCatalogAndRefresh(unittest.TestCase):
    def setUp(self):
        self.index = LocalTextIndex()
        self.pipeline = LocalScannerPipeline(index_store=self.index)
        self.corpus = tempfile.mkdtemp()
        self.state = tempfile.mkdtemp()
        self.csv_path = os.path.join(self.state, "catalog.csv")
        self.catalog = CsvCatalogStore(self.csv_path)
        self.scanner = RefreshScanner(self.pipeline, self.catalog)

    def tearDown(self):
        shutil.rmtree(self.corpus, ignore_errors=True)
        shutil.rmtree(self.state, ignore_errors=True)

    def _write(self, name, text):
        path = os.path.join(self.corpus, name)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return path

    def test_refresh_indexes_new_then_skips_seen(self):
        self._write("roadmap.txt", "Quarterly roadmap for teamChai indexing")
        self._write("budget.md", "Budget review meeting on 25 October 2026")

        first = self.scanner.refresh([self.corpus])
        self.assertEqual(2, first["indexed"])
        self.assertEqual(0, first["skipped"])
        self.assertEqual(2, first["total_rows"])
        self.assertEqual(1, len(self.index.search("roadmap")))

        second = self.scanner.refresh([self.corpus])
        self.assertEqual(0, second["indexed"])
        self.assertEqual(2, second["skipped"])
        self.assertEqual(2, second["total_rows"])

    def test_refresh_reindexes_changed_file_and_drops_stale_text(self):
        path = self._write("offer.txt", "Old obsolete contract terms for alpha")
        self.scanner.refresh([self.corpus])
        self.assertEqual(1, len(self.index.search("obsolete")))

        with open(path, "w", encoding="utf-8") as handle:
            handle.write("Fresh updated agreement terms for the beta project")

        changed = self.scanner.refresh([self.corpus])
        self.assertEqual(1, changed["indexed"])
        self.assertEqual(0, changed["skipped"])
        self.assertEqual(1, changed["total_rows"])
        self.assertEqual(0, len(self.index.search("obsolete")))
        self.assertEqual(1, len(self.index.search("updated agreement")))

    def test_refresh_counts_unsupported_files(self):
        self._write("notes.txt", "keep this one")
        with open(os.path.join(self.corpus, "archive.bin"), "wb") as handle:
            handle.write(b"\x00\x01\x02binary")

        summary = self.scanner.refresh([self.corpus])
        self.assertEqual(1, summary["indexed"])
        self.assertEqual(1, summary["unsupported"])

    def test_catalog_persists_seen_state_across_instances(self):
        self._write("roadmap.txt", "Quarterly roadmap for teamChai indexing")
        self.scanner.refresh([self.corpus])

        reopened = CsvCatalogStore(self.csv_path)
        self.assertEqual(1, reopened.row_count)
        rescan = RefreshScanner(LocalScannerPipeline(index_store=LocalTextIndex()), reopened)
        summary = rescan.refresh([self.corpus])
        self.assertEqual(0, summary["indexed"])
        self.assertEqual(1, summary["skipped"])

    def test_catalog_stale_replacement_keeps_one_row_per_unit(self):
        self.catalog.upsert_row({"source_uri": "file:///a.txt", "content_version": "1:1"})
        self.catalog.upsert_row({"source_uri": "file:///a.txt", "content_version": "2:2"})
        self.assertEqual(1, self.catalog.row_count)
        self.assertTrue(self.catalog.is_indexed("file:///a.txt", None, "2:2"))
        self.assertFalse(self.catalog.is_indexed("file:///a.txt", None, "1:1"))


if __name__ == "__main__":
    unittest.main()
