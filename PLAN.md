# PLAN.md

# Local AI SEO Content CLI

## Overview

A local-first SEO content pipeline driven by **Claude Code (CC) as the runtime orchestrator** and a **llama.cpp router** as the local model runtime. There is no standalone Python app. CC's skills, prompts, and the Bash tool sequence the work, and a single shell helper posts to the router's OpenAI-compatible HTTP API.

Models are served by the llama.cpp router on `localhost:8080`, which runs as the `llama-server` systemd user service. Its presets (`gemma`, `qwen`, `lite`) are built and deployed from `~/Apps/Local-LLM`, and this repo only consumes them:
- `qwen`: ingest, outlining, drafting, fact verification, rewrite, and (planned) metadata
- `gemma`: optional verifier and rewrite model (`VERIFY_MODEL`, `REWRITE_MODEL`). Qwen stayed the default after A/B runs on the three test briefs (2026-09-16).

The router keeps one model loaded at a time (`--models-max 1`) to respect a low-VRAM budget (currently a 10 GB RTX 3080, with `qwen`'s MoE layers offloaded to system RAM). If `curl -s localhost:8080/models` does not list `qwen`, fix the router in Local-LLM before running the pipeline.

Router models carry no built-in system prompt. The wrapper sends `prompts/system.md` as the system message on every call (decided 2026-09-15, after the move off the previous runtime removed the model-side prompt).

---

## Design principles

1. **Local-first.** All generation hits `localhost:8080`.
2. **CC is the harness.** No custom CLI, workflow engine, or storage layer — skills + prompts + Bash + files.
3. **Deterministic pipelines.** Stages run in order; no autonomous loops in MVP.
4. **Section-based generation.** Long articles are never produced in a single call.
5. **Multi-pass quality.** Draft → rewrite → SEO/metadata.
6. **SEO-centric.** Prompts ground in intent, semantic coverage, EEAT.

---

## Architecture

Built (one skill per stage, run in order):

```
User in Claude Code
  ├─ /seo-ingest  <file>   pdftotext/pandoc + prompts/ingest.md (schema)      → briefs/<slug>.json
  ├─ /seo-outline <brief>  prompts/outline.md                                → outline.md
  ├─ /seo-draft   <brief>  scripts/draft_sections.sh: per-part call
  │                        (intro/section/conclusion.md) + verify.md          → sections/*, draft.md
  └─ /seo-rewrite <brief>  scripts/rewrite_sections.sh: per-part rewrite.md
                           (REWRITE_MODEL) + verify.md                        → rewrite/*, final.md
```

Planned (Phases 6 and 7): a metadata and keywords pass (qwen) writing `meta.json`, and a `/seo-generate` skill that runs outline through metadata in one command.

No Python app. No workflow engine. No SQLite.

---

## Folder structure

```
SEO-LLM/
├── .claude/
│   ├── skills/              # <name>/SKILL.md per command. Built: /seo-ingest, /seo-outline, /seo-draft, /seo-rewrite. Planned: /seo-metadata, /seo-keywords, /seo-generate
│   └── settings.json        # allow the five entry scripts, jq, extractors, and Bash(curl -s localhost:8080/models)
├── prompts/
│   ├── system.md            # system message sent on every model call
│   ├── brief.schema.json    # ingest output schema
│   ├── ingest.md
│   ├── outline.md
│   ├── intro.md
│   ├── section.md           # each topic H2 and the FAQ
│   ├── conclusion.md
│   ├── verify.md            # fact check, with verify.schema.json
│   ├── rewrite.md
│   ├── system/              # planned (Phase 7): SEO standards, anti-generic rules, tone, EEAT
│   ├── metadata.md          # planned (Phase 6)
│   └── keywords.md          # planned (Phase 6)
├── scripts/
│   ├── llm_call.sh          # curl wrapper: prompt-file (+ optional temp/seed/schema) + prompts/system.md → stdout
│   ├── fill_prompt.sh       # {{PLACEHOLDER}} filling from brief / outline / source text
│   ├── draft_sections.sh    # per-part drafting loop with fact check, retry, stitch
│   ├── rewrite_sections.sh  # per-part rewrite loop with guards and fact check
│   ├── lib_parts.sh         # shared helpers: verify_part, heading restore, unbold, draft_factor
│   └── check.sh             # FAIL/WARN checks for brief, outline, section, rewrite, draft
├── briefs/                  # JSON inputs
├── outputs/                 # <brief-slug>/{outline.md, sections/, draft.md, rewrite/, final.md}
├── docs/
│   └── google/              # planned (Phase 7): helpful-content.md, eeat.md, semantic-search.md, ai-content-guidelines.md
├── AGENTS.md
├── Instructions.md          # stage-by-stage walk through the pipeline
├── PLAN.md
└── README.md
```

---

## Brief format (JSON)

```json
{
  "topic": "Local SEO for Dentists",
  "target_audience": "Dental Clinics",
  "tone": "Professional",
  "word_count": 2500,
  "keywords": ["dental seo", "local dental marketing", "dentist google rankings"],
  "cta": "Book a consultation",
  "facts": ["Clinic opened in 2012", "New-patient exams are free"]
}
```

The shape is enforced twice: `prompts/brief.schema.json` constrains what the router may return during ingest, and a `jq` check in `/seo-ingest` validates the saved file.

---

## How CC calls the model

A single shell helper:

```bash
scripts/llm_call.sh <prompt-file> [temperature] [seed] [schema-file]
# posts {"model","messages":[system, user],"stream":false, sampling,
#        "chat_template_kwargs":{"enable_thinking":false}} to /v1/chat/completions
# system = prompts/system.md, user = <prompt-file>
# emits .choices[0].message.content to stdout; LLM_HOST / LLM_MODEL override the target
```

CC invokes it via the Bash tool. No Python wrapper, no client library.

### Determinism knobs (defaults)

| Stage     | model      | temperature | seed  |
|-----------|------------|-------------|-------|
| ingest    | qwen       | 0.2         | fixed |
| outline   | qwen       | 0.3         | fixed |
| section   | qwen       | 0.5         | 1, retry 2 |
| verify    | qwen (gemma via VERIFY_MODEL) | 0.1 | 1 |
| rewrite   | REWRITE_MODEL (see Phase 5) | 0.7 | 1, retry 2 |
| metadata  | qwen       | 0.2         | fixed |

Context is not a per-stage knob. Each router preset fixes it per model (65536 for all three presets since the 2026-09-16 redeploy), and a prompt over it returns HTTP 400 instead of being truncated. `scripts/llm_call.sh` reads the served value from `/models` before each call and aborts if it is below this repo's 32768 minimum or cannot be read, so a shrunken preset fails loudly instead of silently cutting the budget. The other sampling values (`top_p`, `top_k`, `min_p`, `presence_penalty`, `repeat_penalty`) are pinned in `scripts/llm_call.sh` and sent on every call, so behavior is defined in this repo rather than by the router's defaults.

### Failure handling

- If a per-section check fails, `scripts/draft_sections.sh` retries once with seed 2, then writes `sections/NN-<heading>.ERROR.md` and stops. An HTTP error or empty reply stops it at once. Re-running skips sections that already exist and pass.
- A fact-check call that fails or times out leaves the part unverified with a WARN. Re-running retries it.
- If a rewrite fails its check twice, `scripts/rewrite_sections.sh` keeps the drafted part with a WARN and carries on, because the rewrite is polish and never blocks the article.

---

## Output layout

```
outputs/<brief-slug>/
├── outline.md
├── draft.md
├── sections/
│   ├── 00-intro.{prompt.txt,md,verify.json,verify.prompt.txt,unverified.md}
│   ├── 01-<heading-slug>.{block.md,prompt.txt,md,verify.json,verify.prompt.txt,unverified.md}
│   └── ...                  # NN-<heading-slug>.ERROR.md when a part fails twice
├── rewrite/
│   ├── 01-<heading-slug>.{prompt.txt,md,verify.json,verify.prompt.txt,unverified.md}
│   └── ...                  # NN-<heading-slug>.rejected-seedN.md for failed edits
├── final.md
└── meta.json                # planned (Phase 6)
```

---

## Setup contract

1. The `llama-server` user service is running (`systemctl --user is-active llama-server` prints `active`). It is installed and configured from `~/Apps/Local-LLM`.
2. The `qwen` preset is deployed there (`make deploy` in Local-LLM, then a service restart, both run by the owner of that repo).
3. Verify: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen`.
4. Open this repo in Claude Code and run `/seo-outline briefs/example.json`, then `/seo-draft` and `/seo-rewrite` on the same brief.

---

## Phased MVP execution (per AGENTS.md)

Each phase: one declarative goal, ≤5 files, atomic revert, end-to-end verification against the live llama.cpp router. **Live execution state — what is done, in progress, or remaining — lives in `IMPLEMENT.md` (untracked, see README), not here.** This section is the architectural breakdown; IMPLEMENT.md is the tracker.

### Phase 1 — Walking skeleton
- Files: `scripts/llm_call.sh` (the wrapper, replaced for the llama.cpp router on 2026-09-15), `prompts/section.md`, `.claude/skills/seo-draft/SKILL.md`, `.claude/settings.json`, `briefs/example.json`.
- Goal: `/seo-draft briefs/example.json` produces `outputs/<slug>/draft.md` via a single Qwen call.

### Phase 2 — Outline stage
- Files: `prompts/outline.md`, `.claude/skills/seo-outline/SKILL.md`, update `seo-draft` to consume the outline.
- Goal: outline generated first and saved as `outline.md`; draft follows it.

### Phase 3 — Brief ingest from .docx / .pdf / .md / .txt
- Files: `prompts/ingest.md`, `.claude/skills/seo-ingest/SKILL.md`, `.claude/settings.json` (allow `pandoc` + `pdftotext`), `PLAN.md`, `README.md`.
- Goal: `/seo-ingest <file>` extracts text (pandoc for .docx, pdftotext for .pdf, passthrough for .md/.txt) and emits `briefs/<slug>.json` matching the brief schema for the user to review before running `/seo-outline`.

### Phase 4 — Section-by-section drafting (done 2026-09-16)
- Files: `scripts/draft_sections.sh`, `prompts/intro.md`, `prompts/section.md` (now per section), `prompts/conclusion.md`, `seo-draft` skill.
- Goal: each outline section → its own model call, stitched into `draft.md` (the rewrite phase produces `final.md`).
- Each part then gets a fact-verification call (`prompts/verify.md`) whose replacements are applied only when they pass deterministic guards; see README.
- Failure handling as implemented: a failed section check is retried once with seed 2 (not a higher temperature: the same seed repeats the output, a new seed does not), then saved as `sections/NN-<heading>.ERROR.md`.

### Phase 5 — Humanization rewrite (done 2026-09-16)
- Files: `prompts/rewrite.md`, `scripts/rewrite_sections.sh`, `.claude/skills/seo-rewrite/SKILL.md`, `check.sh rewrite`.
- Goal: a post-draft rewrite pass reduces repetition and awkward keyword phrasing without changing facts; writes `final.md`.
- Model: chosen by a qwen vs gemma comparison on the three test briefs (see IMPLEMENT.md); `REWRITE_MODEL` overrides.

### Phase 6 — Metadata + keywords
- Files: `prompts/metadata.md`, `prompts/keywords.md`, `.claude/skills/seo-metadata/SKILL.md`, `.claude/skills/seo-keywords/SKILL.md`.
- Goal: title, description, slug, FAQ, keyword expansion written to `meta.json`.

### Phase 7 — Docs + SEO knowledge base
- Files: `README.md`, `docs/google/{helpful-content,eeat,semantic-search,ai-content-guidelines}.md`, link from system prompt.
- Goal: prompts ground in EEAT / helpful-content guidance; quickstart documented.

Deferred (post-MVP): SERP extraction, competitor analysis, RAG, autonomous research, internal linking, topical authority — Milestones 4–5 in the old plan.

---

## Verification

After each phase:
1. The router serves `qwen`: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen`.
2. Run the latest skill in CC against `briefs/example.json`.
3. Inspect `outputs/<slug>/` for the artifacts that phase promised.
4. Spot-check generated text for SEO structure (H2s, keyword presence, no robotic intros).

No test framework in MVP — generation is the test.

---

## Reuse audit

Project contains `AGENTS.md`, `PLAN.md`, and Phase-1-shaped stubs (`briefs/example.json`, `prompts/section.md`, `scripts/llm_call.sh`). External reuse:
- **llama.cpp router**: call its OpenAI-compatible HTTP API directly through `scripts/llm_call.sh`, with no client library.
- **Claude Code skills + Bash** — don't build a workflow engine.
- **JSON** — `jq`, already on the box, for reading briefs and checking them against `prompts/brief.schema.json`.

---

## Risks

1. **Repetitive outputs** → multi-pass rewrite, prompt variation, section drafting.
2. **Hallucinated SEO claims** → ground prompts in `docs/google/*` (Phase 7); deterministic temps for metadata.
3. **Over-engineering** → no workflow engine, no DB; skills + files only.
4. **Router instability or model swaps** → single retry, then halt with an `.ERROR.md` marker and resume by hand. Another app using a different preset unloads `qwen`, so the next call pays its load time.

---

## Success criteria

MVP succeeds when a user can, on a local GPU box with the llama.cpp router serving `qwen`:
1. Drop a JSON brief into `briefs/`.
2. Run `/seo-generate` in CC.
3. Get a section-by-section, humanized, metadata-tagged markdown article in `outputs/<slug>/final.md`.
