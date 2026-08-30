## Problem Statement

### **Making AI an Active User of Your Phone**

Current AI assistants are powerful at **reasoning and generating responses**, but they have limited access to the user's actual digital environment.

A smartphone contains files, photos, messages, contacts, applications, and years of personal information. However, this information is fragmented across different apps, and AI assistants generally cannot **search, understand, and act on it as a unified system**.

For example:

> *“Find my internship documents, summarize the important ones, and send the summary to Rahul on WhatsApp.”*

Today, the AI can generate the summary, but the user still has to manually perform the rest of the workflow.

**The gap is between AI that can think and AI that can actually act.**

---

# The Core Solution: An On-Device Index

Everything we build starts from one principal idea:

> **Before an agent can act on your phone, it has to _know_ your phone.**

So the heart of the product is not the chatbot and not the tools — it is a **private, on-device index of the user's own content**. The index is the single source of truth the agent reasons over. Every other capability in this product is a spin-off that hangs off this core.

### What the index is

A durable, self-healing catalog of the user's authorised files, documents, photos and their extracted text — built and queried entirely **on the device**, with **no server and no upload**.

* **Durable catalog = source of truth.** Every authorised file is recorded in a local catalog that survives restarts, reinstalls of the search layer, renames and moves. The catalog is the ground truth; the fast search layer is only a derived cache rebuilt from it.
* **Fast hybrid search layer.** On top of the catalog sits an on-device search engine that ranks results two ways at once:
  * **Lexical (BM25, prefix-aware)** for exact names and keywords.
  * **Semantic (embedding, cosine)** so *“my government ID”* can find an Aadhaar file even without the exact word.
* **OCR + text extraction pipeline.** PDFs, scanned documents and photos are run through on-device OCR/extraction so their *contents* — not just filenames — become searchable.
* **Self-healing and reconciling.** The index rehydrates itself from the catalog when the search layer is cold, and reconciles on every scan: files that were deleted, renamed or moved are purged so results never point at stale content.
* **Accelerated on-device inference.** The language model runs locally on the phone's GPU (with a CPU fallback), so reasoning over the index stays private and fast without a network round-trip.
* **Private by construction.** The index lives on the device, gated behind explicit folder permissions the user grants. Nothing is indexed that the user did not authorise, and indexed content never leaves the phone.

```text
                Authorised files / photos / PDFs
                              │
                     scan + OCR / extract
                              │
                  ┌───────────▼───────────┐
                  │   DURABLE CATALOG      │   ← source of truth
                  │  (survives restarts,   │
                  │   renames, moves)      │
                  └───────────┬───────────┘
                              │ derived, rebuildable
                  ┌───────────▼───────────┐
                  │  HYBRID SEARCH INDEX   │
                  │  lexical (BM25) +      │
                  │  semantic (embeddings) │
                  └───────────┬───────────┘
                              │
                    everything below is a
                     spin-off of the index
```

---

# Spin-Offs From the Index

Once the phone is indexed, the agent can do far more than answer questions. Each capability below is a **direct extension of the same index** — same catalog, same permissions, same on-device engine.

**🔎 Natural-Language Search (the index, spoken to)**

The most direct spin-off: ask in plain language and the agent answers from your own indexed content, with the source file cited.

> *“Find the PDF where I saved my internship offer letter.”*

**🛠️ File Actions (the index, acted on)**

Because every searchable item already maps to a real file, the same index that *finds* a file can *operate* on it. The agent resolves a spoken file name against the index, then creates, moves, renames or deletes the actual file — new or changed files flow straight back into the index.

* Create text, Markdown or PDF files from chat
* Move, rename and clean up files
* Delete with confirmation

**⏰ Reminders & Notes (the index, extended off-device)**

The same intent layer that routes a search can route a *create* — dropping a reminder into the Calendar or a note into the phone's notes app.

**🔗 Cross-App Workflows**

Combine index lookups and tool actions into one task.

> *“Take a picture of this receipt, extract the amount, summarize it and share it with me on WhatsApp.”*

**🧠 Model-Agnostic Reasoning**

The engine that reads the index is not tied to one provider. Users can switch between on-device models, OpenRouter models and paid APIs to balance **privacy, cost, speed and intelligence** — while the index stays the same private, local ground truth.

**🔐 Controlled Permissions**

The index is only ever built over folders the user explicitly authorises, and sensitive actions (delete, send) require confirmation. Permission is the boundary the whole index — and everything spun off it — lives inside.

---

### The Core Idea

```text
Traditional AI Assistant

User → Question → AI → Answer


Our Agent

          Private on-device INDEX  ← the core
                    │
        ┌───────────┼───────────────┐
     Search      Actions        Workflows
   (ask it)   (create/move/    (chain them
              rename/delete)    together)
                    │
             Phone / Apps / Data
                    │
                  Result
```

**We are not building another chatbot. We are building a private, on-device index of your phone — and then giving AI the tools to act on it. Search, file actions and cross-app workflows are all spin-offs of that one core: an agent that first _knows_ your phone, then _gets things done_ on it.**
