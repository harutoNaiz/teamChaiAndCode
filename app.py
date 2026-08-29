import time
from flask import Flask, current_app, jsonify, request
from local_index import IndexStore, IndexedRecord, LocalTextIndex

app = Flask(__name__)
app.config["INDEX_STORE"] = LocalTextIndex()

# ==============================================================================
# Plug-and-Play Extensible Hooks for Local LLM & Unified Device Indexing
# ==============================================================================

def query_unified_index(query: str, attachment_path: str = None):
    """
    Plug-in hook for Role C (Indexing & OCR RAG).
    Connects to local ChromaDB / SQLite-vec / Tesseract OCR.
    """
    # Placeholder search simulation / hook
    lower = query.lower()
    if "offer letter" in lower or "internship" in lower or "pdf" in lower:
        return {
            "found": True,
            "document": "Documents/Offer_Letters/Google_SWE_Intern_2026.pdf",
            "snippet": "Software Engineering Intern - Google India. Monthly stipend: INR 1,25,000. Joining: June 15, 2026.",
        }
    elif "receipt" in lower or "bill" in lower or attachment_path:
        return {
            "found": True,
            "document": attachment_path or "DCIM/Screenshots/Swiggy_Bill_Aug28.jpg",
            "snippet": "Swiggy Order - Masala Chai (2x Rs 180), Paneer Roll (2x Rs 320), Tax & Delivery (Rs 65). Total: Rs 565.",
        }
    return None

def execute_agent_reasoning(prompt: str, compressed_memory: str, recent_history: list, model_id: str, attachment_path: str = None):
    """
    Plug-in hook for Role B (Agent Loop & LLM Router).
    Routes to Gemini API, OpenRouter, or on-device local SLM.
    """
    lower = prompt.lower()
    index_data = query_unified_index(prompt, attachment_path)
    actions = []
    thought_process = f"Model: {model_id} | Memory Context: {len(compressed_memory)} chars | Recent History: {len(recent_history)} turns"

    if "offer letter" in lower or "internship" in lower or "pdf" in lower:
        actions.append({
            "id": f"act-{int(time.time()*1000)}",
            "type": "search_files",
            "title": "Unified File Index Search",
            "description": "Located: Google_SWE_Intern_2026.pdf",
            "permissionLevel": "safe",
            "status": "completed",
            "parameters": {"query": "offer letter", "type": "pdf"},
            "result": index_data,
        })

        if "whatsapp" in lower or "send" in lower or "share" in lower:
            actions.append({
                "id": f"act-{int(time.time()*1000)+1}",
                "type": "send_whatsapp",
                "title": "Send WhatsApp Message",
                "description": "Send internship details to Rahul (+91 98765 43210)",
                "permissionLevel": "sensitive",
                "status": "pendingApproval",
                "parameters": {
                    "contact": "Rahul",
                    "phone": "+91 98765 43210",
                    "message": "SWE Intern Stipend: Rs 1,25,000/mo. Joining Date: June 15, 2026.",
                }
            })

        response = (
            "I searched your phone's storage and located the document:\n\n"
            "📄 **Document:** `Documents/Offer_Letters/Google_SWE_Intern_2026.pdf`\n\n"
            "### 📑 Summary:\n"
            "• **Role:** Software Engineering Intern\n"
            "• **Stipend:** ₹1,25,000 / month\n"
            "• **Joining Date:** 15th June 2026\n\n"
            "Please review and approve the WhatsApp dispatch card below."
        )
    elif "receipt" in lower or "bill" in lower or "ocr" in lower or attachment_path:
        actions.append({
            "id": f"act-{int(time.time()*1000)}",
            "type": "ocr_image",
            "title": "On-Device OCR Scan",
            "description": "Extracted items & prices from receipt",
            "permissionLevel": "safe",
            "status": "completed",
            "parameters": {"source": attachment_path or "DCIM/Screenshots/Swiggy_Bill_Aug28.jpg"},
            "result": index_data,
        })
        response = (
            "Here is the itemized summary from the receipt:\n\n"
            "| Item | Quantity | Price |\n"
            "| :--- | :--- | :--- |\n"
            "| Masala Chai | 2 | ₹180 |\n"
            "| Paneer Roll | 2 | ₹320 |\n"
            "| Taxes & Delivery | - | ₹65 |\n"
            "| **Total** | | **₹565** |\n\n"
            "Receipt processed successfully."
        )
    else:
        response = (
            f"teamChai agent processed your request using **{model_id}**.\n\n"
            "I have full context of this conversation and can search documents, scan receipts, or perform device actions."
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
