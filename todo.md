# Seath — Product Backlog

## Foundation — Document Model & Ingestion

- [ ] [high] create Document schema with state machine — every downstream feature depends on this
- [ ] [high] add document upload with local filesystem storage — documents must enter the system first
- [ ] [high] implement Oban OCR worker using provider behaviour — extracted text prerequisite for classification and search
- [ ] add Azure Document Intelligence OCR provider — cloud option for high-accuracy OCR
- [ ] add Ollama OCR provider — self-hosted fallback, no cloud dependency required
- [ ] create Tag and DocumentType schemas with many-to-many documents — classification needs targets to propose

## Core Pipeline — Classification & Review

- [ ] [high] implement Oban classification worker using LLM provider behaviour — core differentiator over Paperless
- [ ] add Ollama LLM provider for classification — self-hosted classification, zero external API cost
- [ ] [high] build document review LiveView with approve/reject/edit — trust gate before documents reach archive
- [ ] display classification confidence score in review UI — helps users triage what needs attention
- [ ] add bulk approve/reject in document review — prevents review from becoming tedious at scale
- [ ] add Oban archive worker with state transition — documents need a final resting place
- [ ] add PostgreSQL full-text search over OCR text and metadata — users must find documents they archived

## Differentiators — Chat & RAG

- [ ] build conversational document ingestion LiveView with drag-and-drop — friendly first impression, key UX differentiator
- [ ] broadcast pipeline status updates to LiveView via PubSub — users see OCR/classification progress inline
- [ ] generate document embeddings and store in pgvector — prerequisite for RAG and semantic search
- [ ] build RAG chat LiveView with source citations and pgvector retrieval — genuine differentiator Paperless lacks
- [ ] stream LLM chat responses token-by-token via PubSub — feels responsive, not like a loading spinner

## Archive Hygiene — Rules & Automation

- [ ] create tag-based archival rules with age threshold — hands-off "arquivo morto" document hygiene
- [ ] add archival rule dry-run showing affected document count — prevents accidental mass-archival
- [ ] add periodic Oban cron job to evaluate and apply archival rules — automation must run without manual trigger

## Paperless-Inspired Features

- [ ] add watched folder with filesystem polling for auto-import — proven Paperless pattern, reduces ingestion friction
- [ ] add saved searches with tag, type, and date range filters — power users need repeatable document queries
- [ ] create Correspondent schema linked to documents — matches Paperless metadata users already expect
- [ ] add bulk tag add/remove on search result selection — efficiency for users managing large archives
