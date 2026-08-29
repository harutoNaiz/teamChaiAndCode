import os
import shutil
import tempfile
import unittest

from app import app
from local_index import LocalTextIndex
from scanner_pipeline import CsvCatalogStore


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

    def test_search_filters_and_source_freshness_are_returned(self):
        self.client.post("/index/text", json={
            "id": "pdf-v1", "source_uri": "content://documents/card", "display_name": "scan.pdf",
            "mime_type": "application/pdf", "transcription": "Aadhaar details", "page": 2,
            "modified_at": 1789590600000,
        })
        self.client.post("/index/ocr", json={
            "id": "photo-v1", "source_uri": "content://images/card", "display_name": "scan.jpg",
            "mime_type": "image/jpeg", "transcription": "Aadhaar details",
        })

        response = self.client.get("/search?q=aadhaar&content_type=text&source_uri=content://documents/card")
        self.assertEqual(200, response.status_code)
        result = response.get_json()["results"]
        self.assertEqual(["pdf-v1"], [item["identifier"] for item in result])
        self.assertEqual(1789590600000, result[0]["modified_at"])


    def test_refresh_endpoint_indexes_then_skips_seen(self):
        corpus = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, corpus, True)
        with open(os.path.join(corpus, "notes.txt"), "w", encoding="utf-8") as handle:
            handle.write("Quarterly roadmap for teamChai indexing")
        app.config["CATALOG_STORE"] = CsvCatalogStore(os.path.join(corpus, "catalog.csv"))

        first = self.client.post("/index/refresh", json={"roots": [corpus]})
        self.assertEqual(200, first.status_code)
        body = first.get_json()
        self.assertEqual(1, body["indexed"])
        self.assertEqual(0, body["skipped"])
        self.assertEqual(1, body["total_rows"])

        found = self.client.get("/search?q=roadmap").get_json()["results"]
        self.assertEqual(1, len(found))
        self.assertEqual("notes.txt", found[0]["display_name"])

        second = self.client.post("/index/refresh", json={"roots": [corpus]}).get_json()
        self.assertEqual(0, second["indexed"])
        self.assertEqual(1, second["skipped"])

    def test_refresh_endpoint_rejects_missing_or_bad_roots(self):
        self.assertEqual(400, self.client.post("/index/refresh", json={"roots": []}).status_code)
        self.assertEqual(400, self.client.post("/index/refresh", json={}).status_code)
        bad = self.client.post("/index/refresh", json={"roots": ["/no/such/dir/xyz123"]})
        self.assertEqual(400, bad.status_code)

    def test_chat_memory_is_searchable_with_message_provenance(self):
        response = self.client.post("/index/text", json={
            "id": "chat-session-1-message-2",
            "source_uri": "chat://session/session-1/message/message-2",
            "display_name": "Planning chat",
            "mime_type": "text/markdown",
            "content_type": "chat_memory",
            "transcription": "Remember that the design review is on Friday.",
            "modified_at": 1789590600000,
        })

        self.assertEqual(201, response.status_code)
        result = self.client.get("/search?q=design%20review&content_type=chat_memory").get_json()["results"]
        self.assertEqual(["chat-session-1-message-2"], [item["identifier"] for item in result])
        self.assertEqual("chat://session/session-1/message/message-2", result[0]["open_uri"])
