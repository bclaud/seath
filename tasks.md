# Tasks

_Last updated: 2026-05-29_

## In Progress

## Backlog

## Completed

- [x] **[server] Add Oban job querying, error broadcasts, and smart retry for failed documents** — @server-specialist
  Completed on 2026-05-29. Created `Seath.WorkerJobs` for Oban job queries, added PubSub error broadcasts to OCRWorker and ClassifyWorker, added `Documents.retry_failed/1` for smart worker re-enqueue. 225 tests pass.

- [x] **[frontend] Surface Oban job states and retry button in document index and detail views** — @frontend-specialist
  Completed on 2026-05-29. Added Pipeline Status card with job states to detail view. Added retry buttons to both detail and index views. PubSub subscriptions for real-time updates. Status badges for Oban states (completed/executing/discarded/etc).

- [x] **[server] Add document download and file-view controller endpoints** — @server-specialist
  Completed on 2026-05-29. Added `download/2` (Content-Disposition: attachment) and `show/2` (Content-Disposition: inline) to `DocumentController`, plus routes in `router.ex`. 225 tests pass.

- [x] **[frontend] Update document detail view with proper preview, download, and open-in-browser** — @frontend-specialist
  Completed on 2026-05-29. Replaced thumbnail-only preview with `<object>` for PDFs / `<img>` for images. Fixed download link. Added "Open Original" button with `target="_blank"`. Compiles cleanly.
