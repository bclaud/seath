# Seath

**Self-hosted document management, LLM-native.**

Seath is a document ingestion and retrieval system that uses local LLMs to classify, organize, and make your documents searchable — via SQL, grep, or natural language chat. It is designed for a single user or a small team who values control over their data above all.

This is **not** a polished consumer product. It is a tool built by and for people who are comfortable with the command line, Docker, and occasional debugging. If you are looking for something that Just Works™ out of the box, go use [Paperless-ngx](https://docs.paperless-ngx.com). It is excellent, mature, and has a massive community. Seath exists because Paperless does not have a conversational RAG interface or LLM-driven document classification as a first-class citizen.

---

## State of Affairs

**What works well:**
- Upload documents via a conversational drag-and-drop UI or a watched folder
- OCR extraction via Ollama (fully local, no cloud) or Azure Document Intelligence
- LLM-based classification with multi-step pipeline (think → extract → classify → verify)
- Human review before documents reach the archive
- RAG chat over your document corpus — ask questions in natural language
- PostgreSQL full-text and grep-based retrieval
- Tag-based automatic archival rules
- Document preview (PDF inline via browser, images, download)

**What is rough:**
- No authentication yet (single-user, no login page)
- No S3-compatible storage (local filesystem only)
- No mobile app
- The UI is functional but not beautiful — it is a LiveView app, not a design system
- LLM classification quality depends heavily on your model choice and prompt tuning
- No multi-user support (no permissions, no sharing)
- Backup strategy is "back up your postgres and upload directory"

**What is missing (compared to Paperless-ngx):**
- Mail consumption (fetch documents from email)
- Barcode detection (split multi-page documents)
- Archive serial numbers (ASN)
- Storage paths (template-based file organization)
- Workflows (automated document routing)
- Multi-page document splitting
- Document consumption from scanners (SANED)
- A proper settings UI for everything

---

## Quick Start

```bash
# Prerequisites: Ollama running with a vision model for OCR
# and a chat model for classification. PostgreSQL running.

git clone https://github.com/bclaud/seath
cd seath/server

cp config/runtime.exs.example config/runtime.exs
# Edit runtime.exs with your Ollama URL and model names

mix setup     # installs deps, creates DB, runs migrations, seeds
mix phx.server
```

Open `http://localhost:4000`. Upload a document. Wait for OCR and classification to complete. Review. Approve. Chat with your documents.

### Docker

A Docker compose file is on the roadmap. For now, you run the Elixir server directly.

---

## Architecture

| Layer | Technology |
|-------|-----------|
| Web framework | Phoenix + LiveView |
| Background jobs | Oban |
| Database | PostgreSQL (pgvector for embeddings) |
| OCR (cloud) | Azure Document Intelligence |
| OCR (local) | Ollama vision model |
| Classification | Ollama / OpenAI / Azure OpenAI |
| Embeddings | Ollama |
| File storage | Local filesystem (ext4, zfs, btrfs — whatever you mount) |

### Pipeline

```
Upload → OCR → Extract metadata → Classify (LLM) → Verify → Human Review → Archive
                                                                             ↓
                                                                    RAG Chat / Search
```

Every step is asynchronous via Oban jobs. The UI updates in real-time via Phoenix PubSub.

---

## Configuration

All configuration lives in `config/runtime.exs`. Key environment variables:

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `DATABASE_URL` | Yes | — | PostgreSQL connection |
| `SECRET_KEY_BASE` | Yes | — | Phoenix encryption key |
| `OLLAMA_BASE_URL` | No | `http://localhost:11434` | Ollama endpoint for OCR + LLM |
| `OLLAMA_OCR_MODEL` | No | `llava` | Vision model for OCR |
| `OLLAMA_LLM_MODEL` | No | `llama3.2` | Chat model for classification |
| `OCR_PROVIDER` | No | — | `ollama` or `azure` |
| `LLM_PROVIDER` | No | — | `ollama`, `openai`, or `azure` |

---

## Document Types

Seath ships with 30 default document types spanning financial, personal, academic, business, correspondence, and legal categories. The LLM can also propose new types during classification — you approve them during review.

---

## Why "Seath"?

No deep meaning. It is a made-up name that was not taken on Hex.pm.

---

## License

AGPL-3.0. This project is free software. If you modify and distribute it, you must share your changes.
