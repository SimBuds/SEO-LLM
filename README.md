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
SEO-LLM/
├── .claude/
│   ├── skills/         # one directory per slash command, each holding SKILL.md
│   └── settings.json   # Bash allow-list: the wrapper, the router model check, jq, doc extractors
├── prompts/            # markdown prompt templates with {{PLACEHOLDERS}}, plus system.md (sent on every call)
├── scripts/
│   └── llm_call.sh     # curl wrapper: prompt-file + prompts/system.md → reply on stdout
├── briefs/             # user inputs (JSON)
├── outputs/            # generated articles, one directory per brief (gitignored)
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
- **Claude Code** open in this repo so the slash commands resolve. The first
  interactive session here shows a trust dialog. Accept it, otherwise Claude Code
  ignores the `permissions.allow` entries in `.claude/settings.json` and prompts
  for every Bash command the skills run.

## Quickstart

1. Confirm the router is up and serves `qwen` (this must print `qwen`):
   ```bash
   # Runs in: local terminal
   systemctl --user is-active llama-server
   curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'
   ```
2. Open this repo in Claude Code and accept the trust dialog on first run.
   Confirm the three commands are available by typing `/` and looking for
   `seo-ingest`, `seo-outline`, and `seo-draft`.
3. Get a brief into `briefs/`, either way:
   - **From a JSON brief you write.** Copy [briefs/example.json](briefs/example.json) and edit it.
   - **From a document.** Run `/seo-ingest path/to/source.{docx,pdf,md,txt}`, which writes `briefs/<slug>.json` for you to review and edit.
4. In Claude Code, run the outline first, then the draft:
   ```
   /seo-outline briefs/example.json
   /seo-draft   briefs/example.json
   ```
   The draft needs the outline, so running `/seo-draft` first stops with a message.
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

## Where files land

The slug comes from the brief's `topic`, lowercased with punctuation dropped and
spaces turned into hyphens, so `How to Choose an Engagement Ring` becomes
`how-to-choose-an-engagement-ring`. `/seo-ingest` instead derives its slug from
the source file's basename.

| Path | Written by | What it is |
| --- | --- | --- |
| `briefs/_ingest/<slug>.txt` | `/seo-ingest` | Plain text pulled out of the source document |
| `briefs/_ingest/<slug>.prompt.txt` | `/seo-ingest` | The filled ingest prompt sent to the model |
| `briefs/<slug>.json` | `/seo-ingest` | The brief, for you to review and edit |
| `outputs/<slug>/_outline_prompt.txt` | `/seo-outline` | The filled outline prompt |
| `outputs/<slug>/outline.md` | `/seo-outline` | The outline, consumed by `/seo-draft` |
| `outputs/<slug>/_prompt.txt` | `/seo-draft` | The filled draft prompt, outline included |
| `outputs/<slug>/draft.md` | `/seo-draft` | The article draft |

`outputs/` and `briefs/_ingest/` are gitignored. The `_`-prefixed prompt files are
kept on purpose: when a result looks wrong, they show exactly what the model was
asked. Each stage pins its own sampling: ingest runs at temperature 0.2 seed 1,
outline at 0.3 seed 1, and draft at 0.7 seed 0.

## Running without Claude Code

The skills are orchestration. The pipeline underneath is a prompt file plus the
wrapper, so any stage can be driven from a terminal. This is also the fastest way
to check the router end to end:

```bash
# Runs in: local terminal
# 1. A one-line smoke test. Prints a sentence and exits 0.
printf 'In one sentence, what is your role?\n' > /tmp/role.txt
bash scripts/llm_call.sh /tmp/role.txt 0.2 1

# 2. Build an outline prompt by hand from a brief, then call the model.
python3 - <<'FILL' > /tmp/outline_prompt.txt
import json
b = json.load(open("briefs/example.json"))
t = open("prompts/outline.md").read()
for k, v in {"TOPIC": b["topic"], "AUDIENCE": b["target_audience"],
             "TONE": b["tone"], "WORD_COUNT": str(b["word_count"]),
             "KEYWORDS": ", ".join(b["keywords"]), "CTA": b["cta"]}.items():
    t = t.replace("{{" + k + "}}", v)
print(t)
FILL
bash scripts/llm_call.sh /tmp/outline_prompt.txt 0.3 1 > /tmp/outline.md

# 3. Check a brief against the schema the way /seo-ingest does.
jq -e '(keys == ["cta","keywords","target_audience","tone","topic","word_count"])
  and all(.topic, .target_audience, .tone, .cta; type == "string" and length > 0)
  and (.word_count | type == "number" and . == floor and . >= 1)
  and (.keywords | type == "array" and length >= 3 and length <= 6
       and all(.[]; type == "string" and length > 0))' briefs/example.json
```

## Troubleshooting

Every failure is an exit code from `scripts/llm_call.sh`, and the message says
which one. None of them are retried silently.

| Exit | Meaning | What to do |
| --- | --- | --- |
| 1 | No prompt file given | Pass a prompt file as the first argument |
| 2 | A file is unreadable, or the schema is not a JSON object | Check the path in the message. An empty or malformed schema file also lands here, deliberately, so a bad schema cannot turn into an unconstrained call |
| 3 | The router serves less context than `MIN_CTX` | The preset was deployed smaller than 32768. Fix the preset in `~/Apps/Local-LLM`, or lower `MIN_CTX` if that is genuinely what you want |
| 5 | `/models` has no entry for the model, or no context size in it | Confirm the router serves `qwen` with the quickstart check. A `/models` response shape change also lands here |
| 7 | The router is unreachable | `systemctl --user is-active llama-server`, then check `LLM_HOST` |
| 22 | The router returned an HTTP error | The body is printed. An oversized prompt reads `exceeds the available context size`, which means the input must shrink, not that the call should be retried. A body reading `model name=qwen failed to load` is a router-side problem, see below |

Other things worth knowing:

- **The first call after another model was in use is slow.** The router holds one
  model at a time and sleeps it after 10 idle minutes, so `qwen` has to load. A
  cold call took 7.9 s where a warm one took 0.5 s. `llm load qwen` preloads it.
- **`/seo-draft` stops if no outline exists.** Run `/seo-outline` on the same
  brief first, because the draft is built from that outline.
- **`.docx` ingest needs `pandoc`**, which is not installed here. `.pdf`, `.md`
  and `.txt` work with `pdftotext` and plain copying.
- **`model name=qwen failed to load` (HTTP 500).** The router accepted the
  request but could not start the model, almost always because the GPU is
  already full. The router on 8080 reports every model `unloaded` while some
  other process holds the VRAM, so its own status looks healthy. Compare
  `nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv`
  against `curl -s localhost:8080/models | jq -c '.data[] | {id, status: .status.value}'`.
  The usual cause is a second `llama-server` started by hand on another port,
  which the 8080 service knows nothing about. Observed 2026-09-15: a router on
  port 8081 held 6.2 GB of a 10 GB card, and every call to 8080 returned 500
  until that instance was stopped.
- **Empty or truncated output.** The wrapper exits non-zero on an empty reply
  rather than writing an empty file, so an empty `draft.md` means the step after
  the call went wrong, not the model.

## Working in this repo

[AGENTS.md](AGENTS.md) is the source of truth for how work happens here. Read it before making changes. The other pillars are [PLAN.md](PLAN.md) (architecture and the phased MVP plan) and this README (user-facing and developer-facing).

The fourth pillar, `IMPLEMENT.md`, is the execution tracker and holds the live state: which phase is active, what is done, what is deferred. It is untracked and gitignored on purpose, so a fresh clone has none. Its absence means no work is in flight, not that state was lost. Create it from the skeleton in `AGENTS.md` when you start a phase.

The short version: one phase at a time, at most five files per phase, walking-skeleton first, verify end-to-end against the live llama.cpp router, and end each phase with the literal handoff line.

This repo is SEO only. The tutor application that used to live alongside it now has its own repo, `~/Apps/Tutor-LLM`, and shares no code with this one.
