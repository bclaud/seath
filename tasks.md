# Tasks

_Last updated: 2026-05-20_

## In Progress

_None — Foundation phase complete._

## Backlog

_No remaining backlog items for Foundation phase. Ready for Core Pipeline phase._

## Completed

- [x] **[server] Create Document schema with state machine**
  Completed 2026-05-20. 34 tests. `lib/seath/documents/document.ex`, `lib/seath/documents.ex`.

- [x] **[server] Create Tag and DocumentType schemas**
  Completed 2026-05-20. 62 tests. `lib/seath/tags/`, `lib/seath/document_types/`.

- [x] **[server] Add document upload with local filesystem storage**
  Completed 2026-05-20. 85 tests. `lib/seath/storage.ex`, `ingest/2` in Documents context.

- [x] **[server] Define OCR provider behaviour and Oban worker**
  Completed 2026-05-20. 85 tests. `lib/seath/ocr/provider.ex`, `lib/seath/workers/ocr_worker.ex`.

- [x] **[frontend] Build document upload LiveView**
  Completed 2026-05-20. 89 tests. `lib/seath_web/live/upload_live.ex` with drag-and-drop, progress bars, and success list.

- [x] **[server] Implement Azure Document Intelligence OCR provider**
  Completed 2026-05-20. 89 tests. `lib/seath/ocr/azure.ex` — submits to prebuilt-read, polls async result.

- [x] **[server] Implement Ollama OCR provider**
  Completed 2026-05-20. 89 tests. `lib/seath/ocr/ollama.ex` — base64-encodes image, sends to Ollama chat API.
