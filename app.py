from flask import Flask, current_app, jsonify, request

from local_index import IndexStore, IndexedRecord, LocalTextIndex

app = Flask(__name__)
app.config["INDEX_STORE"] = LocalTextIndex()

@app.get("/health")
def health():
    return jsonify(status="ok")


def _index_payload(content_type: str):
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return None, (jsonify(error="JSON body must be an object"), 400)
    required = ("id", "source_uri", "display_name", "mime_type", "transcription")
    missing = [field for field in required if not isinstance(payload.get(field), str) or not payload[field].strip()]
    if missing:
        return None, (jsonify(error="missing required fields", fields=missing), 400)
    page = payload.get("page")
    if page is not None and (isinstance(page, bool) or not isinstance(page, int) or page < 1):
        return None, (jsonify(error="page must be a positive integer"), 400)
    confidence = payload.get("ocr_confidence")
    if confidence is not None and (isinstance(confidence, bool) or not isinstance(confidence, (int, float)) or not 0 <= confidence <= 1):
        return None, (jsonify(error="ocr_confidence must be between 0 and 1"), 400)
    return IndexedRecord(
        identifier=payload["id"],
        source_uri=payload["source_uri"],
        display_name=payload["display_name"],
        mime_type=payload["mime_type"],
        content_type=content_type,
        transcription=payload["transcription"],
        page=page,
        ocr_confidence=confidence,
    ), None


def _upsert(content_type: str):
    record, error = _index_payload(content_type)
    if error:
        return error
    current_app.config["INDEX_STORE"].upsert(record)
    return jsonify(id=record.identifier, indexed=True, open_uri=record.source_uri), 201


@app.post("/index/text")
def index_text():
    return _upsert("text")


@app.post("/index/ocr")
def index_ocr():
    return _upsert("image_ocr")


@app.get("/search")
def search():
    query = request.args.get("q", "")
    if not query.strip():
        return jsonify(error="q is required"), 400
    store: IndexStore = current_app.config["INDEX_STORE"]
    return jsonify(query=query, results=store.search(query))
