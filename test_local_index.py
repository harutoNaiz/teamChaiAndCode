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
