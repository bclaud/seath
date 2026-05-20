# Tasks

_Last updated: 2026-05-20_

## In Progress

- [ ] **[frontend] Build document upload LiveView** — @frontend-specialist
  Depends on: server upload task ✓. Create `SeathWeb.UploadLive` with `live_file_input` for drag-and-drop upload. Show upload progress and created document confirmation.
  Acceptance: LiveView renders, file upload works end-to-end, tests pass.

- [ ] **[server] Implement Azure Document Intelligence OCR provider** — @server-specialist
  Depends on: OCR behaviour ✓. Implement `Seath.OCR.Azure` using Req to call Azure DI API. Read endpoint and key from `config/runtime.exs`. Handle errors gracefully.
  Acceptance: provider returns extracted text for test PDF, error cases handled.

- [ ] **[server] Implement Ollama OCR provider** — @server-specialist
  Depends on: OCR behaviour ✓. Implement `Seath.OCR.Ollama` using Req to call local Ollama instance. Read base URL and model from config. Handle connection errors gracefully.
  Acceptance: provider returns extracted text when Ollama is available, graceful fallback when not.

## Backlog

_No remaining backlog items for Foundation phase._

## Completed

- [x] **[server] Create Document schema with state machine**
  Completed 2026-05-20. 34 tests passing. Schema at `lib/seath/documents/document.ex`, context at `lib/seath/documents.ex`.

- [x] **[server] Create Tag and DocumentType schemas**
  Completed 2026-05-20. 62 tests passing. Schemas at `lib/seath/tags/tag.ex` and `lib/seath/document_types/document_type.ex`.

- [x] **[server] Add document upload with local filesystem storage**
  Completed 2026-05-20. 85 tests passing. `Seath.Storage` at `lib/seath/storage.ex`, `ingest/2` in Documents context.

- [x] **[server] Define OCR provider behaviour and Oban worker**
  Completed 2026-05-20. 85 tests passing. `Seath.OCR.Provider` behaviour, `Seath.Workers.OCRWorker`, Oban configured with queues.
