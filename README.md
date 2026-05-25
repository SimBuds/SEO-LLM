# SEO LLM CLI

Local-first SEO content pipeline driven by **Claude Code** (CC) as the runtime and **Ollama** as the local model server. No standalone Python app — CC's skills, prompts, and Bash tool sequence the work; a single shell helper posts to Ollama.

## Design at a glance

```
User in Claude Code
  ├─ /seo-outline briefs/<brief>.yaml        (Phase 2 — outline first)
  │    └─ scripts/ollama_call.sh qwen-custom prompts/outline.md
  │         └─ writes outputs/<slug>/outline.md
  └─ /seo-draft   briefs/<brief>.yaml        (Phase 2 — draft from outline)
       └─ scripts/ollama_call.sh qwen-custom prompts/section.md (+ outline injected)
            └─ writes outputs/<slug>/draft.md
```

Later phases add section-by-section drafting, a humanization rewrite pass (`llama-custom`), metadata/keywords, and an SEO knowledge base. See [PLAN.md](PLAN.md) for the full phase breakdown.

### Why this shape
- **CC is the harness.** Skills replace a CLI; the Bash tool replaces a workflow engine; files replace a database.
- **Ollama over HTTP.** One thin shell wrapper (`scripts/ollama_call.sh`) — no client library.
- **Section-based, multi-pass.** Long articles are never produced in a single call; drafts get a separate rewrite pass.
- **Deterministic.** Per-stage temperature and seed; no autonomous loops in MVP.

## Repository layout

```
seo-cli/
├── .claude/
│   ├── skills/         # slash commands invoked inside Claude Code
│   └── settings.json   # Bash allow-list for the wrapper + curl to localhost:11434
├── prompts/            # markdown prompt templates with {{PLACEHOLDERS}}
├── scripts/
│   └── ollama_call.sh  # curl wrapper: model + prompt-file → stdout
├── briefs/             # user inputs (YAML)
├── outputs/            # generated articles, one directory per brief
├── AGENTS.md           # workflow contract for any AI agent in this repo
├── PLAN.md             # architecture + phased MVP plan
└── README.md
```

## Prerequisites

- **Ollama** running locally: `ollama serve` (defaults to `http://localhost:11434`).
- **Custom models built.** This project uses two custom Modelfile-built tags:
  - `qwen-custom` — outlining, drafting, metadata. Build with `~/ai/build-qwen`.
  - `llama-custom` — rewrite / humanization (Phase 4+). Build with `~/ai/build-llama`.
  - Verify: `ollama list` should show both tags.
- **`jq`** and **`curl`** on `PATH` (the wrapper uses them).
- **Claude Code** open in this repo so slash commands resolve.

## Quickstart

1. Start Ollama and confirm the models are present:
   ```bash
   ollama serve &
   ollama list | grep -E 'qwen-custom|llama-custom'
   ```
2. Drop a brief into `briefs/` (see [briefs/example.yaml](briefs/example.yaml) for the schema).
3. In Claude Code, run the outline first, then the draft:
   ```
   /seo-outline briefs/example.yaml
   /seo-draft   briefs/example.yaml
   ```
4. Inspect `outputs/<slug>/outline.md` and `outputs/<slug>/draft.md`.

## The Ollama wrapper

`scripts/ollama_call.sh <model> <prompt-file> [temperature] [seed]`

Posts a non-streaming request to `/api/generate` and prints `.response` to stdout. Exits non-zero on HTTP error. That's the entire model-runtime surface.

## Brief schema

```yaml
topic: Local SEO for Dentists
target_audience: Dental Clinics
tone: Professional
word_count: 2500
keywords:
  - dental seo
  - local dental marketing
cta: Book a consultation
```

The skill substitutes these into `prompts/section.md` placeholders (`{{BRIEF}}`, `{{TONE}}`, `{{AUDIENCE}}`, `{{KEYWORDS}}`, `{{WORD_COUNT}}`, `{{CTA}}`).

## Working in this repo

Read [AGENTS.md](AGENTS.md) before making changes. The short version: one phase at a time, ≤5 files per phase, walking-skeleton first, verify end-to-end against live Ollama, and end each phase with the literal handoff line.

Current state: **Phase 2 (outline stage) complete** — `/seo-outline` produces an outline, `/seo-draft` drafts from it. Next up is Phase 3 (section-by-section drafting) — see [PLAN.md](PLAN.md).
