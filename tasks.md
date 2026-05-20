# Tasks

_Last updated: 2026-05-20_

## In Progress

- [ ] **[server] Broadcast pipeline status updates via PubSub** — @server-specialist
  Wire Oban workers (OCRWorker, ClassifyWorker, ArchiveWorker) to broadcast state changes via `Phoenix.PubSub` on topic `"documents"`. Update `UploadLive` to subscribe and update document list in real-time. Create a `SeathWeb.DocumentStatus` component showing real-time status per document.
  Acceptance: workers broadcast, LiveView receives updates and re-renders without page refresh, tests pass.

- [ ] **[server] Add pgvector extension and document embeddings** — @server-specialist
  Add `pgvector` extension to PostgreSQL. Generate migration creating the extension and adding an `embeddings` table (document_id, embedding vector, model, chunk_index). Add `embed/1` callback to `Seath.LLM.Provider` behaviour. Create `Seath.Workers.EmbedWorker` that generates and stores embeddings. Create `Seath.Embeddings` context with similarity search.
  Acceptance: migration runs, provider behaviour compiles, worker generates and stores embeddings, similarity search returns results.

- [ ] **[server] Create tag-based archival rules with Oban cron** — @server-specialist
  Create migration for `archival_rules` table (name, tag_id FK, age_days, enabled). Create `Seath.ArchiveRules` context with CRUD. Create `Seath.Workers.ApplyArchiveRules` Oban cron worker that checks each enabled rule, finds documents matching the tag older than age_days, and transitions them to `:archived`. Add `:archive_cron` queue and Oban.Cron plugin.
  Acceptance: rules CRUD works, cron worker finds and archives matching documents, tests pass.

## Backlog

- [ ] **[frontend] Build RAG chat LiveView with source citations** — @frontend-specialist
  Depends on: embeddings. Create `SeathWeb.ChatLive` with a chat interface. Accept user text, look up relevant documents via pgvector similarity search, send context + query to LLM provider, display answer with source citations.
  Acceptance: chat UI renders, queries return answers with cited documents, tests pass.

- [ ] **[server] Stream LLM chat responses token-by-token** — @server-specialist
  Depends on: chat LiveView. Modify LLM provider behaviours to support streaming responses via `GenServer`/`Phoenix.PubSub`. Update `ChatLive` to stream tokens as they arrive.
  Acceptance: tokens appear incrementally in chat UI, tests pass.

- [ ] **[server] Add watched folder for auto-import** — @server-specialist
  Create a periodic Oban worker that polls a configurable directory for new files, ingests them via `Seath.Documents.ingest/2`, and moves processed files to a subdirectory.
  Acceptance: files dropped in watched folder are auto-ingested, tests pass.

- [ ] **[server] Create Correspondent schema** — @server-specialist
  Migration for `correspondents` table (name, color), link to documents via `correspondent_id`. Update Document schema and context. Update review LiveView to display/edit correspondent.
  Acceptance: migration runs, schema compiles, tests pass.

- [ ] **[frontend] Add saved searches** — @frontend-specialist
  Depends on: full-text search. Create saved searches UI with name, tag/type/date filters. Store in `saved_searches` table.
  Acceptance: users can save and load searches, tests pass.

## Completed

- [x] Foundation phase (7 items) — 2026-05-20
- [x] Core Pipeline phase (7 items) — 2026-05-20
