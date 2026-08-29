import unittest

from local_index import IndexedRecord, LocalTextIndex


class LocalTextIndexTest(unittest.TestCase):
    def test_ocr_result_keeps_transcription_and_image_uri(self):
        index = LocalTextIndex()
        index.upsert(
            IndexedRecord(
                identifier="aadhaar-photo-1",
                source_uri="content://media/external/images/media/42",
                display_name="IMG_20240103.jpg",
                mime_type="image/jpeg",
                content_type="image_ocr",
                transcription="Government of India Aadhaar Ravi Kumar 1234 5678 9012",
                ocr_confidence=0.96,
            )
        )

        result = index.search("aadhaar")[0]

        self.assertEqual("image_ocr", result["content_type"])
        self.assertIn("Aadhaar", result["transcription"])
        self.assertEqual(result["source_uri"], result["open_uri"])

    def test_new_content_version_replaces_stale_source_text(self):
        index = LocalTextIndex()
        record = IndexedRecord("1-v1", "content://doc/1", "offer.pdf", "application/pdf", "text", "old internship")
        index.upsert(record)
        index.upsert(IndexedRecord("1-v2", "content://doc/1", "offer.pdf", "application/pdf", "text", "internship offer"))

        self.assertEqual([], index.search("old"))
        self.assertEqual("1-v2", index.search("offer")[0]["identifier"])

    def test_poor_filename_is_ranked_from_extracted_text_with_provenance(self):
        index = LocalTextIndex()
        index.upsert(IndexedRecord(
            "opaque-v1", "content://documents/opaque", "scan-003.jpg", "image/jpeg", "image_ocr",
            "Unique Aadhaar identity details for Example Person", ocr_confidence=0.91, modified_at=1789590600000,
        ))

        result = index.search("aadhaar identity", content_types={"image_ocr"})[0]

        self.assertEqual("scan-003.jpg", result["display_name"])
        self.assertEqual("content://documents/opaque", result["open_uri"])
        self.assertIn("Aadhaar", result["snippet"])
        self.assertEqual(1789590600000, result["modified_at"])

    def test_filters_and_invalid_records_are_handled(self):
        index = LocalTextIndex()
        index.upsert(IndexedRecord("pdf-v1", "content://docs/one", "file.pdf", "application/pdf", "pdf_text", "Aadhaar details", page=2))
        index.upsert(IndexedRecord("text-v1", "content://docs/two", "file.txt", "text/plain", "text", "Aadhaar details"))

        self.assertEqual(["pdf-v1"], [item["identifier"] for item in index.search("aadhaar", content_types={"pdf_text"})])
        with self.assertRaises(ValueError):
            index.upsert(IndexedRecord("bad", "content://docs/bad", "bad.jpg", "image/jpeg", "image_ocr", "text", ocr_confidence=1.1))
