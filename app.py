import os

from flask import Flask, current_app, jsonify, request
from local_index import IndexStore, IndexedRecord, LocalTextIndex
from scanner_pipeline import CsvCatalogStore, LocalScannerPipeline, RefreshScanner

app = Flask(__name__)
app.config["INDEX_STORE"] = LocalTextIndex()
# Durable CSV "seen" catalog backing the Refresh button. Dev harness only;
# production Android keeps its own SAF/MediaStore-authorised catalog.
app.config["CATALOG_CSV"] = os.environ.get(
    "TEAMCHAI_CATALOG_CSV", os.path.join(os.path.dirname(__file__), "catalog", "catalog.csv")
)
app.config["CATALOG_STORE"] = CsvCatalogStore(app.config["CATALOG_CSV"])
# Directories a system-wide refresh is allowed to walk. A request may override
# this; both must point at directories the user has authorised.
app.config["REFRESH_ROOTS"] = [
    root for root in os.environ.get("TEAMCHAI_REFRESH_ROOTS", "").split(os.pathsep) if root.strip()
]

# ==============================================================================
# Plug-and-Play Extensible Hooks for Local LLM & Unified Device Indexing
# ==============================================================================

def execute_agent_reasoning(prompt: str, compressed_memory: str, recent_history: list, model_id: str,
                            retrieved_evidence: list[dict] | None = None):
    """Development transport only; never invent a device search or OCR result."""
    evidence_count = len(retrieved_evidence or [])
    return {
        "response": (
            "The development backend does not run a model. "
            f"It received {evidence_count} verified local retrieval result(s) for the selected model."
        ),
        "actions": [],
        "thought_process": (
            f"Model: {model_id} | Memory Context: {len(compressed_memory)} chars | "
            f"Recent History: {len(recent_history)} turns | Verified evidence: {evidence_count}"
        ),
    }

# ==============================================================================
# REST API Endpoints
# ==============================================================================

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
    modified_at = payload.get("modified_at")
    if modified_at is not None and (isinstance(modified_at, bool) or not isinstance(modified_at, int) or modified_at < 1):
        return None, (jsonify(error="modified_at must be a positive integer"), 400)
    return IndexedRecord(
        identifier=payload["id"],
        source_uri=payload["source_uri"],
        display_name=payload["display_name"],
        mime_type=payload["mime_type"],
        content_type=content_type,
        transcription=payload["transcription"],
        page=page,
        ocr_confidence=confidence,
        modified_at=modified_at,
    ), None


def _upsert(content_type: str):
    record, error = _index_payload(content_type)
    if error:
        return error
    current_app.config["INDEX_STORE"].upsert(record)
    return jsonify(id=record.identifier, indexed=True, open_uri=record.source_uri), 201


@app.post("/index/text")
def index_text():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify(error="JSON body must be an object"), 400
    content_type = payload.get("content_type", "text")
    if content_type not in {"text", "pdf_text", "chat_memory"}:
        return jsonify(error="invalid text content_type"), 400
    return _upsert(content_type)


@app.post("/index/ocr")
def index_ocr():
    return _upsert("image_ocr")


@app.get("/search")
def search():
    query = request.args.get("q", "")
    if not query.strip():
        return jsonify(error="q is required"), 400
    store: IndexStore = current_app.config["INDEX_STORE"]
    try:
        limit = int(request.args.get("limit", "20"))
    except ValueError:
        return jsonify(error="limit must be an integer"), 400
    if not 1 <= limit <= 20:
        return jsonify(error="limit must be between 1 and 20"), 400
    content_types = set(filter(None, request.args.getlist("content_type"))) or None
    mime_types = set(filter(None, request.args.getlist("mime_type"))) or None
    source_uri = request.args.get("source_uri") or None
    return jsonify(query=query, results=store.search(query, limit, content_types=content_types,
                                                       mime_types=mime_types, source_uri=source_uri))


@app.post("/index/refresh")
def index_refresh():
    """System-wide refresh: index new/changed files, skip already-seen ones.

    Dev harness for the Flutter Refresh button. On device this maps to a burst
    re-scan of authorised SAF/MediaStore sources; here it walks the given roots.
    Roots must be directories the user authorised (request body or configured
    default), never an arbitrary system path chosen by the model.
    """
    payload = request.get_json(silent=True) or {}
    roots = payload.get("roots")
    if roots is None:
        roots = current_app.config.get("REFRESH_ROOTS", [])
    if not isinstance(roots, list) or not all(isinstance(r, str) and r.strip() for r in roots):
        return jsonify(error="roots must be a list of non-empty directory paths"), 400
    if not roots:
        return jsonify(
            error="no refresh roots given; pass roots in the body or set TEAMCHAI_REFRESH_ROOTS"
        ), 400
    valid = [r for r in roots if os.path.isdir(r)]
    if not valid:
        return jsonify(error="none of the given roots is an existing directory", roots=roots), 400

    index_store = current_app.config["INDEX_STORE"]
    catalog = current_app.config["CATALOG_STORE"]
    scanner = RefreshScanner(LocalScannerPipeline(index_store=index_store), catalog)
    summary = scanner.refresh(valid)
    summary["roots"] = valid
    return jsonify(summary)


@app.get("/api/agent/tools")
def get_tools():
    return jsonify({
        "tools": [
            {"name": "search_files", "description": "Search local documents, PDFs, and storage", "risk": "safe"},
            {"name": "list_files", "description": "List authorised files using metadata and path filters", "risk": "safe"},
            {"name": "ocr_image", "description": "Run on-device OCR on images and receipts", "risk": "safe"},
            {"name": "organize_files", "description": "Group or move files by category", "risk": "medium"},
            {"name": "organize_downloads", "description": "Preview and organize the Downloads folder", "risk": "medium"},
            {"name": "create_reminder", "description": "Create a reminder through the device calendar", "risk": "medium"},
            {"name": "move_file", "description": "Move an authorised file to a selected destination", "risk": "medium"},
            {"name": "rename_file", "description": "Rename an authorised file", "risk": "medium"},
            {"name": "restore_file", "description": "Restore an item from the app trash manifest", "risk": "medium"},
            {"name": "upsert_file", "description": "Create or update an indexed file/catalog record", "risk": "medium"},
            {"name": "send_whatsapp", "description": "Send WhatsApp message to contact", "risk": "sensitive"},
            {"name": "soft_delete_file", "description": "Move specified file to trash with undo support", "risk": "sensitive"},
        ]
    })

@app.post("/api/agent/chat")
def chat():
    data = request.get_json(force=True) or {}
    session_id = data.get("session_id", "default")
    model_id = data.get("model_id", "gemini-1.5-flash")
    compressed_memory = data.get("compressed_memory", "")
    recent_history = data.get("recent_history", [])
    current_turn = data.get("current_turn", {})
    prompt = current_turn.get("prompt", "")
    evidence = data.get("retrieved_evidence", [])
    if not isinstance(evidence, list):
        return jsonify(error="retrieved_evidence must be a list"), 400

    result = execute_agent_reasoning(
        prompt=prompt,
        compressed_memory=compressed_memory,
        recent_history=recent_history,
        model_id=model_id,
        retrieved_evidence=evidence,
    )

    return jsonify(result)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
