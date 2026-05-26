# IMPLEMENT.md — Execution tracker

The canonical record of phase-by-phase progress for this project. Per `AGENTS.md`, this file is updated as part of every phase's Definition of Done. Do not rely on conversational memory — read this file at the start of every phase.

- **Source of architecture and scope:** [PLAN.md](PLAN.md)
- **Source of agent rules:** [AGENTS.md](AGENTS.md)
- **Source of user/developer-facing docs:** [README.md](README.md)

---

## Status snapshot

- Phases done: 1, 2, 3
- Phase in progress: — (awaiting approval to begin Phase 4)
- Phases remaining: 4, 5, 6, 7

## Inherited decisions (session log)

1. Runtime stack pinned: Claude Code as orchestrator, Ollama HTTP at `localhost:11434` as model runtime.
2. Models are **custom Ollama tags** built via `~/ai/build-qwen` and `~/ai/build-llama` → `qwen-custom` (structure/drafting/metadata) and `llama-custom` (rewrite/humanization).
3. No standalone Python app, no workflow engine, no SQLite — skills + prompts + one shell helper + files.
4. Brief schema is YAML with six keys: `topic`, `target_audience`, `tone`, `word_count`, `keywords`, `cta`. YAML remains the single canonical interchange format for the pipeline.
5. Source-doc ingestion (.docx via `pandoc`, .pdf via `pdftotext`, .md/.txt passthrough) extracts a YAML brief; the user reviews/edits before downstream phases run.
6. No OCR for scanned PDFs in MVP. Long docs are truncated at ~24k chars for ingest.
7. Example brief is B2C (engagement-ring shoppers + local jeweler).
8. Single-model-active at a time; target VRAM budget ~12 GB.
9. Per-section failure handling: one retry at slightly higher temperature, then write `sections/<n>.ERROR.md` and halt. Manual resume by re-running the skill (skip files that exist).

---

## Phases

### Phase 1 — Walking skeleton: one prompt, one Ollama call, one output  ✅
- **Goal:** `/seo-draft briefs/example.yaml` produces `outputs/<slug>/draft.md` via a single `qwen-custom` call.
- **Files:** `scripts/ollama_call.sh`, `prompts/section.md`, `.claude/skills/seo-draft.md`, `.claude/settings.json`, `briefs/example.yaml`.
- **Verification:** Smoke output present at `outputs/_smoke/_prompt.txt`; skill spec validated against existing files.
- **Status:** Done.

### Phase 2 — Outline stage  ✅
- **Goal:** Outline is generated first and saved as `outline.md`; draft consumes it via a `{{OUTLINE}}` placeholder.
- **Files:** `prompts/outline.md`, `.claude/skills/seo-outline.md`, `prompts/section.md` (updated), `.claude/skills/seo-draft.md` (updated), `README.md` (updated).
- **Verification:**
  - `/seo-outline briefs/example.yaml` produces `outputs/<slug>/outline.md` with `# `, 4–7 `## `, `## FAQ`, `## Conclusion`.
  - `/seo-draft briefs/example.yaml` produces a draft whose H2 headings match the outline's.
- **Status:** Done. End-to-end run not executed by the agent; user-side verification recommended.

### Phase 3 — Brief ingest from .docx / .pdf / .md / .txt  ✅
- **Goal:** `/seo-ingest <file>` extracts text and emits `briefs/<slug>.yaml` for the user to review before `/seo-outline`.
- **Files:** `prompts/ingest.md`, `.claude/skills/seo-ingest.md`, `.claude/settings.json` (pandoc + pdftotext allowed), `PLAN.md` (phases renumbered), `README.md`.
- **Verification:**
  - `/seo-ingest some.pdf` → `briefs/<slug>.yaml` parses with `yq` and contains all six required keys.
  - The skill reports the six extracted field values and prompts the user to review before `/seo-outline`.
- **Status:** Done. End-to-end run not executed by the agent.

### Phase 4 — Section-by-section drafting  ⏳ (next)
- **Goal:** Each outline H2 becomes its own Ollama call; results stitched into `outputs/<slug>/final.md`.
- **Planned files (≤5):** `.claude/skills/seo-draft.md` (loop sections), `prompts/intro.md`, `prompts/conclusion.md`, `IMPLEMENT.md`, `README.md`.
- **Reuse audit (to perform before execution):**
  - Search: `rg -n 'outline|section' prompts .claude/skills` for any existing per-section logic.
  - Candidates expected: none — current `seo-draft` is single-pass. Document the search result before writing code.
- **Verification:**
  - Run on a 2500-word brief; confirm `outputs/<slug>/sections/01-*.md`, `02-*.md`, … exist.
  - `final.md` contains the H1 + every outline H2 in order; no single-pass blob.
  - At least one section is regenerated cleanly on rerun (skip-if-exists behavior works).
- **Status:** Awaiting approval.

### Phase 5 — Humanization rewrite (Llama)  🔒
- **Goal:** Post-draft rewrite pass using `llama-custom` reduces repetition and varies cadence.
- **Planned files:** `prompts/rewrite.md`, `.claude/skills/seo-rewrite.md`, `scripts/ollama_call.sh` (no change expected — already supports model swap), `IMPLEMENT.md`, `README.md`.
- **Verification:** diff before/after; sentence-length variance increases; no robotic transitions.

### Phase 6 — Metadata + keywords  🔒
- **Goal:** Title, description, slug, FAQ, keyword expansion generated and saved to `outputs/<slug>/meta.json`.
- **Planned files:** `prompts/metadata.md`, `prompts/keywords.md`, `.claude/skills/seo-metadata.md`, `.claude/skills/seo-keywords.md`, `IMPLEMENT.md` + `README.md` (counted toward budget if touched).
- **Verification:** `meta.json` validates against a small schema; FAQ present.

### Phase 7 — Docs + Google SEO knowledge base  🔒
- **Goal:** Prompts reference SEO knowledge; quickstart documented.
- **Planned files:** `docs/google/helpful-content.md`, `docs/google/eeat.md`, `docs/google/semantic-search.md`, `docs/google/ai-content-guidelines.md`, link from system prompt; `README.md` + `IMPLEMENT.md` updates.
- **Verification:** Re-run generation; system prompt now grounds in EEAT framing.

---

## Deferred (post-MVP)

- SERP intelligence, competitor analysis, internal linking, topical authority mapping, autonomous research, RAG.
- OCR for scanned PDFs.
- Chunked summarization for source docs > 24k chars in `/seo-ingest`.
- Test framework (none until `scripts/ollama_call.sh` grows real logic).
