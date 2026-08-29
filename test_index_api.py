import unittest

from app import app
from local_index import LocalTextIndex


class IndexApiTest(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        app.config["INDEX_STORE"] = LocalTextIndex()

    def test_text_is_indexed_and_found(self):
        response = self.client.post(
            "/index/text",
            json={
                "id": "offer-v1",
                "source_uri": "content://documents/offer-v1",
                "display_name": "offer-letter.txt",
                "mime_type": "text/plain",
                "transcription": "Internship offer from Chai and Code",
            },
        )

        self.assertEqual(201, response.status_code)
        result = self.client.get("/search?q=intern")

        self.assertEqual(200, result.status_code)
        self.assertEqual("offer-v1", result.get_json()["results"][0]["identifier"])

    def test_ocr_result_returns_original_image_reference(self):
        response = self.client.post(
            "/index/ocr",
            json={
                "id": "image-42-v1",
                "source_uri": "content://media/external/images/media/42",
                "display_name": "IMG_1042.jpg",
                "mime_type": "image/jpeg",
                "transcription": "Government of India Aadhaar Ravi Kumar",
                "ocr_confidence": 0.96,
            },
        )

        self.assertEqual(201, response.status_code)
        result = self.client.get("/search?q=aadhaar").get_json()["results"][0]

        self.assertEqual("image_ocr", result["content_type"])
        self.assertIn("Aadhaar", result["transcription"])
        self.assertEqual("content://media/external/images/media/42", result["open_uri"])

    def test_missing_transcription_is_rejected(self):
        response = self.client.post(
            "/index/ocr",
            json={
                "id": "missing-text",
                "source_uri": "content://media/1",
                "display_name": "empty.jpg",
                "mime_type": "image/jpeg",
            },
        )

        self.assertEqual(400, response.status_code)
        self.assertIn("transcription", response.get_json()["fields"])
