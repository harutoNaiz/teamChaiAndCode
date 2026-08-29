import os
import time
from flask import Flask, current_app, jsonify, request
from local_index import IndexStore, IndexedRecord, LocalTextIndex
from scanner_pipeline import (
    BackgroundFileSystemCronWatcher,
    DefaultLocalOcrEngine,
    LocalScannerPipeline,
    OpenRouterMultimodalExtractor,
)

app = Flask(__name__)
index_store = LocalTextIndex()
app.config["INDEX_STORE"] = index_store

# Initialize scanner & multimodal background watcher
scanner_pipeline = LocalScannerPipeline(index_store=index_store)
cron_watcher = BackgroundFileSystemCronWatcher(pipeline=scanner_pipeline, poll_interval_seconds=10.0)
app.config["SCANNER_PIPELINE"] = scanner_pipeline
app.config["CRON_WATCHER"] = cron_watcher


# ==============================================================================
# Unified Device Index & Vector Memory Reasoning
# ==============================================================================

def query_unified_index(query: str, attachment_path: str = None):
    """
    Queries the vector memory index store to ground chat and retrieval in indexed phone content.
    """
    store: IndexStore = current_app.config["INDEX_STORE"]
    results = store.search(query, limit=5)
    if results:
        top = results[0]
        return {
            "found": True,
            "document": top.get("display_name", top.get("source_uri")),
            "source_uri": top.get("source_uri"),
            "content_type": top.get("content_type"),
            "page": top.get("page"),
            "snippet": top.get("snippet") or top.get("transcription", ""),
            "transcription": top.get("transcription", ""),
            "score": top.get("score", 0),
        }
    
    # Fallback to general search if specific query wasn't matched
    return None


def execute_agent_reasoning(prompt: str, compressed_memory: str, recent_history: list, model_id: str, attachment_path: str = None):
    """
    Agent reasoning loop that queries vector memory and grounds the response.
    """
    lower = prompt.lower()
    index_data = query_unified_index(prompt, attachment_path)
    actions = []
    thought_process = f"Model: {model_id} | Memory: {len(compressed_memory)} chars | History: {len(recent_history)} turns"

    if index_data and index_data.get("found"):
        doc_name = index_data.get("document", "Document")
        snippet = index_data.get("snippet", "")
        source_uri = index_data.get("source_uri", "")
        content_type = index_data.get("content_type", "document")
        page = index_data.get("page")

        thought_process += f" | Retrieved memory from {doc_name} (score: {index_data.get('score')})"

        actions.append({
            "id": f"act-{int(time.time()*1000)}",
            "type": "search_files",
            "title": f"Vector Memory Search: {doc_name}",
            "description": f"Located relevant content in {doc_name}",
            "permissionLevel": "safe",
            "status": "completed",
            "parameters": {"query": prompt, "source_uri": source_uri},
            "result": index_data,
        })

        if "whatsapp" in lower or "send" in lower or "share" in lower:
            actions.append({
                "id": f"act-{int(time.time()*1000)+1}",
                "type": "send_whatsapp",
                "title": "Send WhatsApp Message",
                "description": f"Share extracted details from {doc_name}",
                "permissionLevel": "sensitive",
                "status": "pendingApproval",
                "parameters": {
                    "contact": "Selected Contact",
                    "message": f"Summary of {doc_name}: {snippet[:120]}...",
                }
            })

        response = (
            f"I retrieved the following information from your indexed {content_type}:\n\n"
            f"📄 **Document:** `{doc_name}`" + (f" (Page {page})" if page else "") + "\n\n"
            f"### 📑 Extracted Content:\n"
            f"{snippet}\n\n"
            f"*Source URI:* `{source_uri}`"
        )
    else:
        response = (
            f"teamChai agent processed your request using **{model_id}**.\n\n"
            "I checked your phone's vector memory and can search documents, scan photos with OCR, or perform device actions."
        )

    return {
        "response": response,
        "actions": actions,
        "thought_process": thought_process,
    }


# ==============================================================================
# REST API Endpoints
# ==============================================================================

@app.get("/health")
def health():
    return jsonify(status="ok")


def _index_payload(default_content_type: str, allowed_content_types: set[str]):
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return None, (jsonify(error="JSON body must be an object"), 400)
    required = ("id", "source_uri", "display_name", "mime_type", "transcription")
    missing = [field for field in required if not isinstance(payload.get(field), str) or not payload[field].strip()]
    if missing:
        return None, (jsonify(error="missing required fields", fields=missing), 400)
    
    content_type = payload.get("content_type", default_content_type)
    if not isinstance(content_type, str) or content_type not in allowed_content_types:
        return None, (jsonify(error=f"content_type must be one of {sorted(allowed_content_types)}"), 400)
    
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


def _upsert(default_content_type: str, allowed_content_types: set[str]):
    record, error = _index_payload(default_content_type, allowed_content_types)
    if error:
        return error
    current_app.config["INDEX_STORE"].upsert(record)
    return jsonify(id=record.identifier, indexed=True, open_uri=record.source_uri), 201


@app.post("/index/text")
def index_text():
    return _upsert("text", {"text", "pdf_text"})


@app.post("/index/ocr")
def index_ocr():
    return _upsert("image_ocr", {"image_ocr", "pdf_ocr"})


@app.get("/search")
def search():
    query = request.args.get("q", "")
    if not query.strip():
        return jsonify(error="q is required"), 400
    store: IndexStore = current_app.config["INDEX_STORE"]
    return jsonify(query=query, results=store.search(query))


@app.post("/api/scanner/watch")
def add_watch_path():
    data = request.get_json(silent=True) or {}
    path = data.get("path")
    if not path or not os.path.exists(path):
        return jsonify(error="valid directory path is required"), 400
    watcher: BackgroundFileSystemCronWatcher = current_app.config["CRON_WATCHER"]
    watcher.add_watch_path(path)
    indexed = watcher.scan_once()
    return jsonify(status="watching", path=path, newly_indexed=indexed)


@app.get("/api/agent/tools")
def get_tools():
    return jsonify({
        "tools": [
            {"name": "search_files", "description": "Search local documents, PDFs, and storage", "risk": "safe"},
            {"name": "ocr_image", "description": "Run on-device OCR on images and receipts", "risk": "safe"},
            {"name": "organize_files", "description": "Group or move files by category", "risk": "medium"},
            {"name": "send_whatsapp", "description": "Send WhatsApp message to contact", "risk": "sensitive"},
            {"name": "delete_file", "description": "Delete specified file from storage", "risk": "sensitive"},
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
    attachment_path = current_turn.get("attachment_path")

    result = execute_agent_reasoning(
        prompt=prompt,
        compressed_memory=compressed_memory,
        recent_history=recent_history,
        model_id=model_id,
        attachment_path=attachment_path,
    )

    return jsonify(result)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
