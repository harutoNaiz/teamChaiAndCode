import os
import json
import time
from flask import Flask, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

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
