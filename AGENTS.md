# Seath — Agent Instructions

Intelligent document management system. Paperless-inspired, but with a clearer OCR/classification pipeline, LLM-native design, and chat interface.

## What Seath Is

Seath is a self-hosted document management platform built around a PARA-style inbox-to-archive workflow:

1. **Ingest** — documents are dropped via a friendly chatbot-style interface or direct upload
2. **Scan & Extract** — OCR via Azure Document Intelligence or local Ollama models
3. **Classify** — LLM-driven classification pipeline assigns tags, type, and metadata
4. **Review** — human-in-the-loop approval before documents are permanently filed
5. **Archive** — approved documents are stored and searchable; automatic archival via tag-based rules
6. **Chat** — native RAG-powered chat over the document corpus

## Stack

| Layer | Technology |
|-------|-----------|
| Web server & UI | Elixir · Phoenix · LiveView |
| Background jobs | Oban |
| Database | PostgreSQL |
| OCR (cloud) | Azure Document Intelligence |
| OCR / LLM (local) | Ollama |
| File storage | Local filesystem (S3-compatible future) |

## Subprojects

| Directory | Description | Agent |
|-----------|-------------|-------|
| `server/` | Phoenix app: API, LiveView UI, Oban workers | `server-specialist` |
| `server/lib/seath_web/` | LiveView components and pages | `frontend-specialist` |

## Dev Tooling

- **Justfile** — Task runner. Run `just` or `just --list` to see all recipes.
- **flake.nix** — Nix shell with all required tooling. To add dev tools, edit `flake.nix` — user confirmation required before changes. See `.agents/skills/nix-thinking/SKILL.md` for Nix guidance.
- **opencode** — AI coding agent. Run `opencode` in the project root.

## Shared Conventions

- Commit messages: Conventional (`feat:`, `fix:`, `chore:`).
- Business logic in Phoenix contexts (`lib/seath/`), web layer in `lib/seath_web/`.
- Background work always goes through Oban workers.
- LLM provider calls are abstracted behind a behaviour so Ollama and Azure are interchangeable.
- Secrets only in `config/runtime.exs` — never committed.
