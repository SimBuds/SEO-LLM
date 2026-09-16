# PLAN.md

# Local AI SEO Content CLI

## Overview

A local-first SEO content pipeline driven by **Claude Code (CC) as the runtime orchestrator** and a **llama.cpp router** as the local model runtime. There is no standalone Python app. CC's skills, prompts, and the Bash tool sequence the work, and a single shell helper posts to the router's OpenAI-compatible HTTP API.

Models are served by the llama.cpp router on `localhost:8080`, which runs as the `llama-server` systemd user service. Its presets (`gemma`, `qwen`, `lite`) are built and deployed from `~/Apps/Local-LLM`, and this repo only consumes them:
- `qwen`: outlining, structured outputs, metadata, drafting
- Rewrite / humanization: model chosen when that phase is planned

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

```
User in Claude Code
  └─ /seo-generate briefs/<brief>.json
       └─ skill reads brief + prompts/*.md
            ├─ Bash: scripts/llm_call.sh prompts/outline.md                  → outline.md
            ├─ Bash: per-section call (qwen, prompts/section.md)            → sections/*.md
            ├─ Bash: per-section rewrite (model TBD, prompts/rewrite.md)    → humanized
            ├─ Bash: metadata + keywords pass (qwen)                        → meta.json
            └─ Write outputs/<slug>/final.md
```

No Python app. No workflow engine. No SQLite.

---

## Folder structure

```
SEO-LLM/
├── .claude/
│   ├── skills/              # <name>/SKILL.md per command. Built: /seo-ingest, /seo-outline, /seo-draft. Planned: /seo-rewrite, /seo-metadata, /seo-keywords, /seo-generate
│   └── settings.json        # allow Bash(scripts/llm_call.sh:*) and Bash(curl -s localhost:8080/models)
├── prompts/
│   ├── system.md            # system message sent on every model call
│   ├── system/              # SEO standards, anti-generic rules, tone, EEAT
│   ├── outline.md
│   ├── section.md
│   ├── intro.md
│   ├── conclusion.md
│   ├── rewrite.md
│   ├── metadata.md
│   └── keywords.md
├── scripts/
│   └── llm_call.sh          # curl wrapper: prompt-file (+ optional temp/seed) + prompts/system.md → stdout
├── briefs/                  # JSON inputs
├── outputs/                 # <brief-slug>/{outline.md, sections/, final.md, meta.json}
├── docs/
│   └── google/              # helpful-content.md, eeat.md, semantic-search.md, ai-content-guidelines.md
├── AGENTS.md
└── PLAN.md
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
  "cta": "Book a consultation"
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
| draft     | qwen       | 0.7         | fixed |
| section   | qwen       | 0.6         | fixed |
| rewrite   | TBD        | 0.8         | fixed |
| metadata  | qwen       | 0.2         | fixed |

Context is not a per-stage knob. Each router preset fixes it per model (65536 for all three presets since the 2026-09-16 redeploy), and a prompt over it returns HTTP 400 instead of being truncated. `scripts/llm_call.sh` reads the served value from `/models` before each call and aborts if it is below this repo's 32768 minimum or cannot be read, so a shrunken preset fails loudly instead of silently cutting the budget. The other sampling values (`top_p`, `top_k`, `min_p`, `presence_penalty`, `repeat_penalty`) are pinned in `scripts/llm_call.sh` and sent on every call, so behavior is defined in this repo rather than by the router's defaults.

### Failure handling

- If a per-section call fails (non-2xx or empty body), the skill retries once with a slightly higher temperature, then writes `sections/<n>.ERROR.md` and stops the pipeline. Resume is manual: re-running the skill skips sections that already have a non-error file.

---

## Output layout

```
outputs/<brief-slug>/
├── outline.md
├── sections/
│   ├── 01-<heading-slug>.md
│   └── ...
├── humanized/
│   └── 01-<heading-slug>.md
├── final.md
└── meta.json
```

---

## Setup contract

1. The `llama-server` user service is running (`systemctl --user is-active llama-server` prints `active`). It is installed and configured from `~/Apps/Local-LLM`.
2. The `qwen` preset is deployed there (`make deploy` in Local-LLM, then a service restart, both run by the owner of that repo).
3. Verify: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen`.
4. Open this repo in Claude Code; run `/seo-draft briefs/example.json`.

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

### Phase 4 — Section-by-section drafting
- Files: update `seo-draft` to loop sections; `prompts/intro.md`, `prompts/conclusion.md`.
- Goal: each outline section → its own model call, stitched into `final.md`.

### Phase 5 — Humanization rewrite
- Files: `prompts/rewrite.md`, `.claude/skills/seo-rewrite/SKILL.md`. The wrapper already swaps models through `LLM_MODEL`.
- Goal: a post-draft rewrite pass reduces repetition. Its model is chosen from the router's presets when this phase is planned.

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
