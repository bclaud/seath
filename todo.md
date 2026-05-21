# Seath — Product Backlog

## Foundation — Document Model & Ingestion

- [x] [high] create Document schema with state machine — every downstream feature depends on this
- [x] [high] add document upload with local filesystem storage — documents must enter the system first
- [x] [high] implement Oban OCR worker using provider behaviour — extracted text prerequisite for classification and search
- [x] add Azure Document Intelligence OCR provider — cloud option for high-accuracy OCR
- [x] add Ollama OCR provider — self-hosted fallback, no cloud dependency required
- [x] create Tag and DocumentType schemas with many-to-many documents — classification needs targets to propose

## Core Pipeline — Classification & Review

- [x] [high] implement Oban classification worker using LLM provider behaviour — core differentiator over Paperless
- [x] add Ollama LLM provider for classification — self-hosted classification, zero external API cost
- [x] [high] build document review LiveView with approve/reject/edit — trust gate before documents reach archive
- [x] display classification confidence score in review UI — helps users triage what needs attention
- [x] add bulk approve/reject in document review — prevents review from becoming tedious at scale
- [x] add Oban archive worker with state transition — documents need a final resting place
- [x] add PostgreSQL full-text search over OCR text and metadata — users must find documents they archived

## Differentiators — Chat & RAG

- [x] build conversational document ingestion LiveView with drag-and-drop — friendly first impression, key UX differentiator
- [x] broadcast pipeline status updates to LiveView via PubSub — users see OCR/classification progress inline
- [x] generate document embeddings and store in pgvector — prerequisite for RAG and semantic search
- [x] build RAG chat LiveView with source citations and pgvector retrieval — genuine differentiator Paperless lacks
- [x] [high] fix RAG chat — embedding-based retrieval broken, needs debugging
- [x] [high] fix font rendering on Chat and Review pages — text unreadable despite CSS fixes
- [x] stream LLM chat responses token-by-token via PubSub — feels responsive, not like a loading spinner

## Archive Hygiene — Rules & Automation

- [x] create tag-based archival rules with age threshold — hands-off "arquivo morto" document hygiene
- [x] add archival rule dry-run showing affected document count — prevents accidental mass-archival
- [x] add periodic Oban cron job to evaluate and apply archival rules — automation must run without manual trigger

## Paperless-Inspired Features

- [x] add watched folder with filesystem polling for auto-import — proven Paperless pattern, reduces ingestion friction
- [x] add saved searches with tag, type, and date range filters — power users need repeatable document queries
- [x] create Correspondent schema linked to documents — matches Paperless metadata users already expect
- [x] add bulk tag add/remove on search result selection — efficiency for users managing large archives

## Document Explorer — Browse, Search & View

- [x] [high] build document index LiveView with paginated list of all documents — archived documents are invisible without this
- [x] [high] add full-text search bar to document index wired to existing PostgreSQL search — search backend exists but has no UI
- [x] [high] add filter sidebar with tag, document type, correspondent, status, and date range — users need to narrow large archives fast
- [x] [high] build document detail/show LiveView with full metadata, OCR text, and file preview — no way to view a filed document today
- [x] wire saved searches UI into document index — backend CRUD exists but is completely unexposed
- [x] fix dashboard "Archived" stat card to link to document index — currently a dead `#` link
- [x] add document thumbnail generation for visual browsing — Paperless users expect to recognize documents by sight
- [x] [quick win] show recent documents on dashboard — gives the home page immediate utility beyond stat counters
- [x] add inline document editing (title, tags, type, correspondent) from detail view — users need to correct metadata post-archive without re-processing

## Retrieval Strategy — Hybrid Grep + Semantic Search

- [x] [high] save OCR text as plain text files alongside original documents — enables grep-based retrieval, external tooling, and full portability
- [x] [high] embed structured metadata header in text files (title, tags, type, correspondent, date, involved parties) — LLM can grep by field, not just raw text
- [x] regenerate text file when document metadata changes (tag edit, type change, etc.) — metadata in files must stay in sync with database
- [x] [high] implement grep-based document retrieval for RAG chat as primary search method — exact matches (names, IDs, dates) are what users search for most
- [ ] add tool-use/function-calling pattern to chat LLM — let the model choose between grep and semantic search per query
- [x] keep pgvector embeddings as fallback for fuzzy/semantic queries — "docs about my lease" when text says "rental agreement"
- [x] use grep-based retrieval for context-aware classification — find prior docs by matching terms without embedding dependency

## Smarter Classification — Context-Aware LLM Pipeline

- [x] [high] inject similar archived documents into classification prompt via grep or embedding search — classification improves as archive grows, core differentiator
- [x] include prior documents' tags, type, and correspondent in classification context — LLM learns from user's actual filing patterns
- [x] add a dedicated `chat`/`generate` callback to the LLM provider behaviour — RAG chat currently abuses `classify`, needs a proper abstraction
- [x] seed default DocumentType entries (invoice, receipt, contract, email, letter, statement, report) — LLM can't propose types if none exist to match against
- [x] implement multi-step classification with separate LLM calls per field (title, tags, document_type, correspondent, involved_parties) — follows paperless-gpt approach for better quality
- [x] add vision OCR callback to LLM provider (ocr_vision/2) — enables LLM-based OCR with structured data extraction
- [x] add correspondent extraction to search/match existing correspondents during classification
- [x] add involved parties extraction (named entities) during classification — enables "show me everything involving X" queries
- [x] update OCR worker with optional vision-LLM OCR fallback — better structured data extraction for invoices/receipts
- [x] allow ClassifyWorker to create new DocumentType when LLM proposes an unknown type — prevents useful classifications from being silently dropped
- [x] add correspondent extraction to LLM classification prompt — correspondent field exists but pipeline never populates it

## Involved Parties — Multi-Entity Extraction

- [x] [high] create InvolvedParty schema with name, role, and document association — real documents mention multiple people/entities, not just one correspondent
- [x] extract all named entities (people, companies, organizations) from document text during classification — enables "show me everything involving X" queries
- [x] add involved parties display to document review UI — reviewer should see and correct extracted entities before archiving
- [x] add search/filter by involved party name — users need to find all documents mentioning a specific person or company
