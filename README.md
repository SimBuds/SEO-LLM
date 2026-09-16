# SEO LLM CLI

Local-first SEO content pipeline driven by **Claude Code** (CC) as the runtime and a **llama.cpp router** on `localhost:8080` as the local model server. No standalone Python app. CC's skills, prompts, and Bash tool sequence the work, and a single shell helper posts to the router's OpenAI-compatible chat endpoint.

## Design at a glance

```
User in Claude Code
  ├─ /seo-ingest  <doc.docx|doc.pdf|doc.md>  (Phase 3 — optional: doc → JSON brief)
  │    └─ pandoc / pdftotext → scripts/llm_call.sh prompts/ingest.md → writes briefs/<slug>.json
  ├─ /seo-outline briefs/<brief>.json        (Phase 2 — outline first)
  │    └─ scripts/llm_call.sh prompts/outline.md
  │         └─ writes outputs/<slug>/outline.md
  └─ /seo-draft   briefs/<brief>.json        (Phase 2 — draft from outline)
       └─ scripts/llm_call.sh prompts/section.md (+ outline injected)

Every scripts/llm_call.sh call → POST localhost:8080/v1/chat/completions
  model qwen, system message prompts/system.md, thinking off
            └─ writes outputs/<slug>/draft.md
```

Later phases add section-by-section drafting, a humanization rewrite pass (model chosen when that phase is planned), metadata/keywords, and an SEO knowledge base. See [PLAN.md](PLAN.md) for the full phase breakdown.

### Why this shape
- **CC is the harness.** Skills replace a CLI; the Bash tool replaces a workflow engine; files replace a database.
- **llama.cpp over HTTP.** One thin shell wrapper (`scripts/llm_call.sh`), no client library. The router's models carry no built-in system prompt, so the wrapper sends `prompts/system.md` on every call.
- **Section-based, multi-pass.** Long articles are never produced in a single call; drafts get a separate rewrite pass.
- **Deterministic.** Per-stage temperature and seed; no autonomous loops in MVP.

## Repository layout

```
seo-cli/
├── .claude/
│   ├── skills/         # slash commands invoked inside Claude Code
│   └── settings.json   # Bash allow-list: the wrapper, the router model check, jq, doc extractors
├── prompts/            # markdown prompt templates with {{PLACEHOLDERS}}, plus system.md (sent on every call)
├── scripts/
│   └── llm_call.sh     # curl wrapper: prompt-file + prompts/system.md → reply on stdout
├── briefs/             # user inputs (JSON)
├── outputs/            # generated articles, one directory per brief
├── AGENTS.md           # workflow contract for any AI agent in this repo
├── PLAN.md             # architecture + phased MVP plan
└── README.md
```

## Prerequisites

- **llama.cpp router** on `http://localhost:8080` serving the model `qwen`. It runs as the `llama-server` systemd user service, configured and deployed from `~/Apps/Local-LLM` (see that repo's README, "Serving other apps"). This repo only calls it.
  - The router keeps one model loaded at a time and puts it to sleep after 10 idle minutes, so the first call after another model was in use waits for `qwen` to load.
  - Context is fixed at 32768 tokens by the router's preset. The wrapper reads the served value before every call and refuses to run below 32768 (see below). A longer prompt returns HTTP 400 instead of being truncated.
  - Optional: the `llm` CLI from Local-LLM shows model state (`llm status`) and preloads a model (`llm load qwen`).
- **`jq`** and **`curl`** on `PATH` (the wrapper uses them).
- **`pandoc`** (for `.docx` ingest) and **`pdftotext`** from `poppler-utils` (for `.pdf` ingest). Only needed if you use `/seo-ingest`.
- **Claude Code** open in this repo so slash commands resolve.

## Quickstart

1. Confirm the router is up and serves `qwen` (this must print `qwen`):
   ```bash
   # Runs in: local terminal
   systemctl --user is-active llama-server
   curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'
   ```
2. Drop a brief into `briefs/` (see [briefs/example.json](briefs/example.json) for the schema).
3. **Option A — start from a JSON brief.** Drop a brief into `briefs/` (see [briefs/example.json](briefs/example.json)).
   **Option B — start from a doc.** Run `/seo-ingest path/to/source.{docx,pdf,md,txt}` to extract a JSON brief into `briefs/<slug>.json`, then review/edit it.
4. In Claude Code, run the outline first, then the draft:
   ```
   /seo-outline briefs/example.json
   /seo-draft   briefs/example.json
   ```
5. Inspect `outputs/<slug>/outline.md` and `outputs/<slug>/draft.md`.

## The model wrapper

`scripts/llm_call.sh <prompt-file> [temperature] [seed] [schema-file]`

Posts a non-streaming request to `/v1/chat/completions` and prints `.choices[0].message.content` to stdout. That's the entire model-runtime surface.

- The system message is always `prompts/system.md`, and the prompt file is the user message.
- Temperature defaults to 0.7 and seed to 0. `top_p`, `top_k`, `min_p`, `presence_penalty`, and `repeat_penalty` are pinned in the script and sent on every call.
- Thinking is off (`chat_template_kwargs: {"enable_thinking": false}`).
- With a schema file (a JSON object, as in [prompts/brief.schema.json](prompts/brief.schema.json)), the reply is constrained to that schema via `response_format`. `/seo-ingest` uses this. Without it the payload is unchanged.
- `LLM_HOST` (default `http://localhost:8080`) and `LLM_MODEL` (default `qwen`) override the target.
- Before each call it reads `GET /models` and requires the served context to be at least `MIN_CTX` (32768, the constant at the top of the script). Below that it exits 3 without calling the model. A loaded model reports `meta.n_ctx`, an unloaded one carries `--ctx-size` in `status.args`, so the check works in both states and never forces a model load.
- If the context cannot be read at all (`/models` unreachable, the model absent from the list, or neither field present), it exits non-zero rather than calling on an unverified context. A router that changes the shape of `/models` therefore stops calls until the script is updated, which is deliberate.
- Exits non-zero on an HTTP error, printing the server's error body to stderr, and on an empty reply.

## Brief schema

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

All six keys are required. `tone` is one of `Professional`, `Authoritative`, `Conversational`, `Friendly`, or `Technical`, `word_count` is a whole number, and `keywords` holds 3 to 6 entries. [prompts/brief.schema.json](prompts/brief.schema.json) states the same rules for the router, and `/seo-ingest` checks a generated brief against them with `jq`.

The skill substitutes these into `prompts/section.md` placeholders (`{{BRIEF}}`, `{{TONE}}`, `{{AUDIENCE}}`, `{{KEYWORDS}}`, `{{WORD_COUNT}}`, `{{CTA}}`).

## Working in this repo

Read [AGENTS.md](AGENTS.md) before making changes. The 4-pillar docs are [AGENTS.md](AGENTS.md) (agent rules), [PLAN.md](PLAN.md) (architecture + phases), [IMPLEMENT.md](IMPLEMENT.md) (execution tracker — current state lives here), and this README (user/developer-facing). The short version: one phase at a time, ≤5 files per phase, walking-skeleton first, verify end-to-end against the live llama.cpp router, and end each phase with the literal handoff line.

Current state: **Phase 3 (doc/PDF ingest) complete** — `/seo-ingest` produces a JSON brief from `.docx`/`.pdf`/`.md`/`.txt`; `/seo-outline` + `/seo-draft` consume it. Next up is Phase 4 (section-by-section drafting) — see [PLAN.md](PLAN.md).
