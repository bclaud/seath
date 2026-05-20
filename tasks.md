# Tasks

_Last updated: 2026-05-20_

## In Progress

- [ ] **[frontend] Build RAG chat LiveView with source citations** — @frontend-specialist
  Depends on: embeddings ✓. Create `SeathWeb.ChatLive` with message history, query input, and response display. On submit: embed the query text, find similar docs via `Seath.Embeddings.similarity_search/2`, send context + query to LLM (using `Seath.LLM.classify/3` won't work for chat — need a `chat/2` callback), show answer with cited document titles.
  Acceptance: chat UI renders, queries return answers with cited documents, tests pass.

- [ ] **[server] Add watched folder for auto-import** — @server-specialist
  Create a periodic Oban worker that polls a configurable directory for new files, ingests them via `Seath.Documents.ingest/2`, and moves processed files to a subdirectory.
  Acceptance: files dropped in watched folder are auto-ingested, tests pass.

- [ ] **[server] Create Correspondent schema** — @server-specialist
  Migration for `correspondents` table (name, color), add `correspondent_id` to documents. Update Document schema and context. Update review LiveView to display/edit correspondent.
  Acceptance: migration runs, schema compiles, tests pass.

## Backlog

- [ ] **[server] Stream LLM chat responses token-by-token** — @server-specialist
  Depends on: chat LiveView. Modify LLM provider behaviours to support streaming responses via `GenServer`/`Phoenix.PubSub`. Update `ChatLive` to stream tokens as they arrive.
  Acceptance: tokens appear incrementally in chat UI, tests pass.

- [ ] **[frontend] Add saved searches** — @frontend-specialist
  Depends on: full-text search ✓. Create saved searches UI with name, tag/type/date filters. Store in `saved_searches` table.
  Acceptance: users can save and load searches, tests pass.

## Completed

- [x] Foundation phase (7 items) — 2026-05-20
- [x] Core Pipeline phase (7 items) — 2026-05-20
- [x] Batch 1: PubSub, pgvector/embeddings, archival rules — 2026-05-20
