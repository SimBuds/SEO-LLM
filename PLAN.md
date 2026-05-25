# PLAN.md

# Local AI SEO Content CLI

## Overview

A local-first SEO content pipeline driven by **Claude Code (CC) as the runtime orchestrator** and **Ollama** as the local model runtime. There is no standalone Python app. CC's skills, prompts, and the Bash tool sequence work; a single shell helper posts to Ollama's HTTP API.

Primary models (custom Ollama tags built via `~/ai/build-qwen` and `~/ai/build-llama`):
- `qwen-custom` — outlining, structured outputs, metadata, drafting
- `llama-custom` — rewrite / humanization

Single-model-active at a time to respect a low-VRAM budget (target: 12 GB). If these tags are missing from `ollama list`, build them via the scripts in `~/ai/` before running the pipeline.

---

## Design principles

1. **Local-first.** All generation hits `localhost:11434`.
2. **CC is the harness.** No custom CLI, workflow engine, or storage layer — skills + prompts + Bash + files.
3. **Deterministic pipelines.** Stages run in order; no autonomous loops in MVP.
4. **Section-based generation.** Long articles are never produced in a single call.
5. **Multi-pass quality.** Draft → rewrite → SEO/metadata.
6. **SEO-centric.** Prompts ground in intent, semantic coverage, EEAT.

---

## Architecture

```
User in Claude Code
  └─ /seo-generate briefs/<brief>.yaml
       └─ skill reads brief + prompts/*.md
            ├─ Bash: scripts/ollama_call.sh qwen-custom prompts/outline.md  → outline.md
            ├─ Bash: per-section call (qwen-custom, prompts/section.md)     → sections/*.md
            ├─ Bash: per-section rewrite (llama-custom, prompts/rewrite.md) → humanized
            ├─ Bash: metadata + keywords pass (qwen-custom)                 → meta.json
            └─ Write outputs/<slug>/final.md
```

No Python app. No workflow engine. No SQLite.

---

## Folder structure

```
seo-cli/
├── .claude/
│   ├── skills/              # /seo-draft, /seo-outline, /seo-rewrite, /seo-metadata, /seo-keywords, /seo-generate
│   └── settings.json        # allow Bash(scripts/ollama_call.sh:*) and Bash(curl:*) to localhost
├── prompts/
│   ├── system/              # SEO standards, anti-generic rules, tone, EEAT
│   ├── outline.md
│   ├── section.md
│   ├── intro.md
│   ├── conclusion.md
│   ├── rewrite.md
│   ├── metadata.md
│   └── keywords.md
├── scripts/
│   └── ollama_call.sh       # curl wrapper: model + prompt-file (+ optional temp/seed) → stdout
├── briefs/                  # YAML inputs
├── outputs/                 # <brief-slug>/{outline.md, sections/, final.md, meta.json}
├── docs/
│   └── google/              # helpful-content.md, eeat.md, semantic-search.md, ai-content-guidelines.md
├── AGENTS.md
└── PLAN.md
```

---

## Brief format (YAML)

```yaml
topic: Local SEO for Dentists
target_audience: Dental Clinics
tone: Professional
word_count: 2500
keywords:
  - dental seo
  - local dental marketing
  - dentist google rankings
cta: Book a consultation
```

---

## How CC calls Ollama

A single shell helper:

```bash
scripts/ollama_call.sh <model> <prompt-file> [temperature] [seed]
# posts {"model","prompt","stream":false,"options":{...}} to /api/generate
# emits the response text to stdout
```

CC invokes it via the Bash tool. No Python wrapper, no client library.

### Determinism knobs (defaults)

| Stage     | model        | temperature | seed  | num_ctx |
|-----------|--------------|-------------|-------|---------|
| outline   | qwen-custom   | 0.3         | fixed | 8192    |
| section   | qwen-custom   | 0.6         | fixed | 8192    |
| rewrite   | llama-custom  | 0.8         | fixed | 8192    |
| metadata  | qwen-custom   | 0.2         | fixed | 4096    |

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

1. Install Ollama and run `ollama serve`.
2. Build custom models: `~/ai/build-qwen` and `~/ai/build-llama` (produces `qwen-custom` and `llama-custom` Ollama tags).
3. Verify: `curl -s http://localhost:11434/api/tags | jq '.models[].name'`
4. Open this repo in Claude Code; run `/seo-draft briefs/example.yaml`.

---

## Phased MVP execution (per AGENTS.md)

Each phase: one declarative goal, ≤5 files, atomic revert, end-to-end verification against live Ollama.

### Phase 1 — Walking skeleton
- Files: `scripts/ollama_call.sh`, `prompts/section.md`, `.claude/skills/seo-draft.md`, `.claude/settings.json`, `briefs/example.yaml`.
- Goal: `/seo-draft briefs/example.yaml` produces `outputs/<slug>/draft.md` via a single Qwen call.

### Phase 2 — Outline stage
- Files: `prompts/outline.md`, `.claude/skills/seo-outline.md`, update `seo-draft` to consume the outline.
- Goal: outline generated first and saved as `outline.md`; draft follows it.

### Phase 3 — Brief ingest from .docx / .pdf / .md / .txt
- Files: `prompts/ingest.md`, `.claude/skills/seo-ingest.md`, `.claude/settings.json` (allow `pandoc` + `pdftotext`), `PLAN.md`, `README.md`.
- Goal: `/seo-ingest <file>` extracts text (pandoc for .docx, pdftotext for .pdf, passthrough for .md/.txt) and emits `briefs/<slug>.yaml` matching the brief schema for the user to review before running `/seo-outline`.

### Phase 4 — Section-by-section drafting
- Files: update `seo-draft` to loop sections; `prompts/intro.md`, `prompts/conclusion.md`.
- Goal: each outline section → its own Ollama call, stitched into `final.md`.

### Phase 5 — Humanization rewrite (Llama)
- Files: `prompts/rewrite.md`, `.claude/skills/seo-rewrite.md`, helper supports model swap.
- Goal: post-draft rewrite pass with `llama-custom` reduces repetition.

### Phase 6 — Metadata + keywords
- Files: `prompts/metadata.md`, `prompts/keywords.md`, `.claude/skills/seo-metadata.md`, `.claude/skills/seo-keywords.md`.
- Goal: title, description, slug, FAQ, keyword expansion written to `meta.json`.

### Phase 7 — Docs + SEO knowledge base
- Files: `README.md`, `docs/google/{helpful-content,eeat,semantic-search,ai-content-guidelines}.md`, link from system prompt.
- Goal: prompts ground in EEAT / helpful-content guidance; quickstart documented.

Deferred (post-MVP): SERP extraction, competitor analysis, RAG, autonomous research, internal linking, topical authority — Milestones 4–5 in the old plan.

---

## Verification

After each phase:
1. `ollama serve` running; `ollama list` includes `qwen-custom` and `llama-custom`.
2. Run the latest skill in CC against `briefs/example.yaml`.
3. Inspect `outputs/<slug>/` for the artifacts that phase promised.
4. Spot-check generated text for SEO structure (H2s, keyword presence, no robotic intros).

No test framework in MVP — generation is the test.

---

## Reuse audit

Project contains `AGENTS.md`, `PLAN.md`, and Phase-1-shaped stubs (`briefs/example.yaml`, `prompts/section.md`, `scripts/ollama_call.sh`). External reuse:
- **Ollama** — call its HTTP API directly; don't wrap.
- **Claude Code skills + Bash** — don't build a workflow engine.
- **YAML** — `yq` if needed, otherwise let CC parse inline.

---

## Risks

1. **Repetitive outputs** → multi-pass rewrite, prompt variation, section drafting.
2. **Hallucinated SEO claims** → ground prompts in `docs/google/*` (Phase 6); deterministic temps for metadata.
3. **Over-engineering** → no workflow engine, no DB; skills + files only.
4. **Ollama instability** → single retry then halt with `.ERROR.md` marker; manual resume.

---

## Success criteria

MVP succeeds when a user can, on a 12 GB GPU box with Ollama running:
1. Drop a YAML brief into `briefs/`.
2. Run `/seo-generate` in CC.
3. Get a section-by-section, humanized, metadata-tagged markdown article in `outputs/<slug>/final.md`.
