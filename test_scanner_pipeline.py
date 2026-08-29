import os
import shutil
import tempfile
import unittest

from local_index import LocalTextIndex
from scanner_pipeline import (
    BackgroundFileSystemCronWatcher,
    DefaultLocalOcrEngine,
    LocalScannerPipeline,
    ModelCapability,
    OpenRouterMultimodalExtractor,
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


if __name__ == "__main__":
    unittest.main()
