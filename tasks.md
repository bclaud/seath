# Tasks

_Last updated: 2026-05-20_

## In Progress

_None — Core Pipeline phase complete._

## Backlog

- [ ] **[frontend] Display classification confidence score in review UI** — @frontend-specialist
  Depends on: review LiveView ✓. Show confidence percentage next to each proposed tag/type. Color-code.
  Acceptance: confidence scores visible and color-coded in review UI.

- [ ] **[frontend] Add bulk approve/reject in document review** — @frontend-specialist
  Depends on: review LiveView ✓. Add checkbox selection and bulk action buttons.
  Acceptance: selecting multiple documents and clicking approve/reject processes all selected.

## Completed

- [x] **[server] Create Document schema with state machine** — 2026-05-20
- [x] **[server] Create Tag and DocumentType schemas** — 2026-05-20
- [x] **[server] Add document upload with local filesystem storage** — 2026-05-20
- [x] **[server] Define OCR provider behaviour and Oban worker** — 2026-05-20
- [x] **[frontend] Build document upload LiveView** — 2026-05-20
- [x] **[server] Implement Azure Document Intelligence OCR provider** — 2026-05-20
- [x] **[server] Implement Ollama OCR provider** — 2026-05-20
- [x] **[server] Define LLM provider behaviour and classification worker** — 2026-05-20
- [x] **[server] Implement Ollama LLM provider for classification** — 2026-05-20
- [x] **[frontend] Build document review LiveView** — 2026-05-20
- [x] **[server] Add Oban archive worker** — 2026-05-20
- [x] **[server] Add PostgreSQL full-text search** — 2026-05-20
