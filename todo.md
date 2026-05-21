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
- [ ] stream LLM chat responses token-by-token via PubSub — feels responsive, not like a loading spinner

## Archive Hygiene — Rules & Automation

- [x] create tag-based archival rules with age threshold — hands-off "arquivo morto" document hygiene
- [x] add archival rule dry-run showing affected document count — prevents accidental mass-archival
- [x] add periodic Oban cron job to evaluate and apply archival rules — automation must run without manual trigger

## Paperless-Inspired Features

- [x] add watched folder with filesystem polling for auto-import — proven Paperless pattern, reduces ingestion friction
- [x] add saved searches with tag, type, and date range filters — power users need repeatable document queries
- [x] create Correspondent schema linked to documents — matches Paperless metadata users already expect
- [ ] add bulk tag add/remove on search result selection — efficiency for users managing large archives

## Smarter Classification — Context-Aware LLM Pipeline

- [ ] [high] inject similar archived documents into LLM classification prompt via embedding similarity search — classification improves as archive grows, core differentiator
- [ ] include prior documents' tags, type, and correspondent in classification context — LLM learns from user's actual filing patterns
- [ ] add a dedicated `chat`/`generate` callback to the LLM provider behaviour — RAG chat currently abuses `classify`, needs a proper abstraction
- [ ] seed default DocumentType entries (invoice, receipt, contract, email, letter, statement, report) — LLM can't propose types if none exist to match against
- [ ] allow ClassifyWorker to create new DocumentType when LLM proposes an unknown type — prevents useful classifications from being silently dropped
- [ ] add correspondent extraction to LLM classification prompt — correspondent field exists but pipeline never populates it

## Involved Parties — Multi-Entity Extraction

- [ ] [high] create InvolvedParty schema with name, role, and document association — real documents mention multiple people/entities, not just one correspondent
- [ ] extract all named entities (people, companies, organizations) from document text during classification — enables "show me everything involving X" queries
- [ ] add involved parties display to document review UI — reviewer should see and correct extracted entities before archiving
- [ ] add search/filter by involved party name — users need to find all documents mentioning a specific person or company
