# Tasks

_Last updated: 2026-05-22_

## In Progress

_No tasks in progress._

## Backlog

_No pending tasks._

## Completed

- [x] **[server] Core thinking loop & pipeline improvements** — 2026-05-22
  All 7 server-side items implemented (222 tests, 0 failures):
  - Chain-of-thought "thinking" step (`think/2` callback)
  - Extract-then-classify two-step pipeline (`classify_from_reasoning/4`)
  - Verification pass (`verify/2` callback) — cross-checks entity grounding
  - Heuristic confidence scoring (5-factor model, no LLM self-report)
  - Text chunking for docs > 8,000 chars (6k chunks, 500-char overlap)
  - Entity name dedup/normalization (Levenshtein fuzzy matching)
  - Low-confidence auto-reclassification (retry with different prompt/temperature)
  - New migration: `add_classification_quality_fields` (llm_reasoning, verification_data, classification_attempts)
  - Added `Seath.Documents.reclassify/1` for frontend integration

- [x] **[frontend] Add "Reclassify" button to review UI** — 2026-05-22
  Added Reclassify button to review LiveView with PubSub subscription for real-time progress. Displays classification attempts, verification warnings (flagged fields), and heuristic confidence. Button disables during processing with spinner. 223 tests, 0 failures.
