# AI Tutor App — Implementation Plan

A local-first tutor bot built by porting the seo-app core and adding three net-new capabilities: a chat loop with memory, documentation grounding (RAG), and a code-dump guardrail. All models run via Ollama. All tailoring is app-layer markdown — same philosophy as SEO-LLM: constraints are data, prompts ship via git, no model rebuilds.

**Core workflow:** Tailor to the learner → load a subject's documentation → chat; the tutor answers *from the docs*, teaches Socratically instead of dumping code, and (later) can check online for newer trends as a clearly-labeled secondary source.

Each phase is tagged **[PORT]** (adapted from seo-app) or **[NET-NEW]** (built fresh).

---

## Guiding principles

1. **Docs-grounded honesty.** The tutor answers from supplied documentation, cites the section, and says "the docs don't cover this" rather than guessing. Fabricated Liquid filters are the failure mode to kill.
2. **Teach, don't solve.** Hints → pseudocode → partial snippets → full solution, in that order, and full solutions only on explicit request. Enforced mechanically, not just by prompt.
3. **Tailor to dimensions that matter.** Explanation depth, scaffolding level, pace, preferred medium (analogies / worked examples / exercises), and known-topics — not VAK learning styles.
4. **Subjects are first-class.** Each subject (e.g., Shopify) bundles its docs, its embedding index, and an optional rules overlay.
5. **Offline-first.** Web trend search is an explicit, labeled add-on feature — the app is fully useful with local docs alone.

---

## Target structure

```
tutor-app/
├── app/
│   ├── main.py            # Streamlit chat UI (Phase 8)
│   ├── chat.py            # conversation loop + session memory   [NET-NEW]
│   ├── compiler.py        # stacks rules + profile + subject + retrieved docs  [PORT]
│   ├── ollama_client.py   # chat + embeddings endpoints          [PORT, extended]
│   ├── ingest.py          # docs → chunks → embeddings           [NET-NEW]
│   ├── retriever.py       # question → top-k doc chunks          [NET-NEW]
│   ├── websearch.py       # trends feature (Phase 7)             [NET-NEW]
│   ├── tone.py            # learner sliders → instruction text   [PORT, re-mapped]
│   └── lint.py            # code-dump guard + honesty checks     [PORT, new rules]
├── rules/
│   ├── tutor-core.md      # Socratic method, docs-honesty rules  [replaces seo-core.md]
│   └── pedagogy.md        # hint-laddering, explanation structure
├── profiles/
│   └── <learner>.md       # frontmatter (depth, scaffolding, pace, known topics) + prose
├── subjects/
│   └── shopify/
│       ├── docs/          # dropped-in documentation (md/html/pdf)
│       ├── index/         # embedding store
│       └── overlay.md     # optional subject-specific rules
├── sessions/              # chat logs + per-subject progress summaries
├── tests/
└── config.yaml            # models (chat, embed), retrieval k, code-line cap, retry cap
```

---

## Phase 0 — Bootstrap from SEO-LLM [PORT]

**Goal:** Create the tutor-app skeleton by copying everything reusable directly out of the seo-app tree — start from working code, not a blank directory.

**Tasks**
- [ ] From inside the SEO-LLM project directory, create the skeleton and copy the reusable core:
  ```bash
  cd ~/path/to/SEO-LLM        # or wherever seo-app lives

  # Skeleton
  mkdir -p ../tutor-app/{app,rules,profiles,subjects/shopify/{docs,index},sessions,tests}

  # Portable code — the app-agnostic core
  cp seo-app/app/compiler.py       ../tutor-app/app/
  cp seo-app/app/ollama_client.py  ../tutor-app/app/
  cp seo-app/app/tone.py           ../tutor-app/app/
  cp seo-app/app/lint.py           ../tutor-app/app/
  cp seo-app/app/brief_parser.py   ../tutor-app/app/ingest.py   # becomes the docs ingester

  # Config and templates as starting points
  cp seo-app/config.yaml               ../tutor-app/config.yaml
  cp seo-app/profiles/_template.md     ../tutor-app/profiles/_template.md

  # Rules: copy as raw material to rewrite, NOT to keep
  cp seo-app/rules/seo-core.md         ../tutor-app/rules/tutor-core.md
  ```
- [ ] Deliberately do **not** copy: `google-rules.md` (SEO-only), keyword extraction, the generation pipeline, Streamlit pages (UI is rebuilt around chat in Phase 8).
- [ ] `git init` the new directory (or add as a sibling project) and commit the raw copies before editing anything — clean diff baseline.
- [ ] Strip `config.yaml` to tutor-relevant keys: chat model, embedding model (e.g., `nomic-embed-text`), retrieval `top_k`, code-line cap, retry cap, Ollama host.
- [ ] Decision to record in the README: if both apps will live long-term, plan a shared `core/` library (compiler, ollama_client, lint framework) extracted later — note it now, don't build it yet.

**Deliverable:** `tutor-app/` exists with ported code committed unmodified.
**Done when:** `git log` shows the pristine-copy commit and the directory tree matches the target structure.

---

## Phase 1 — Rules rewrite & learner profile system [PORT]

**Goal:** Replace SEO identity with tutor identity; re-map the profile schema to learner dimensions.

**Tasks**
- [ ] Rewrite `rules/tutor-core.md`: tutor identity, docs-honesty mandate ("answer from provided documentation, cite the section, say so when the docs don't cover it"), and the solution ladder (question → hint → pseudocode → partial → full-only-on-request).
- [ ] Write `rules/pedagogy.md`: how to structure an explanation (concept → tiny example → check-understanding question), when to quiz, how to build on the session summary.
- [ ] Re-map `tone.py` sliders to learner dimensions, each 1–5, each translated to instruction sentences (never raw numbers):
  ```yaml
  depth: 3          # 1 = ELI5 … 5 = terse expert
  scaffolding: 4    # 1 = show solutions freely … 5 = hints only
  pace: 2           # 1 = one concept at a time … 5 = broad survey
  medium: [analogies, worked_examples]   # multi-select
  ```
- [ ] Profile template: frontmatter above + prose body (background, goals, known-topics list so basics aren't re-explained, current project context — e.g., "building a Shopify theme for a client").
- [ ] Port the profile CLI wizard: `python -m app.profile new`.
- [ ] Compiler stacking order for a chat turn: `tutor-core.md` → `pedagogy.md` → subject `overlay.md` (if any) → learner instructions → retrieved doc chunks (labeled) → session summary → conversation history → user message.
- [ ] `--dry-run` flag prints a fully-compiled turn for inspection.

**Deliverable:** Compiled prompts that read as a tutor with your learning preferences baked in.
**Done when:** Two profiles with different `scaffolding` values produce visibly different behavior on the same question.

---

## Phase 2 — Documentation ingestion [NET-NEW]

**Goal:** Drop docs into a subject folder → searchable embedding index. This is the Liquid-docs case.

**Tasks**
- [ ] Extend `ingest.py` (from brief_parser): accept `.md` and `.html` first, `.pdf` second. Normalize to markdown.
- [ ] Chunking: split by heading hierarchy, target ~300–800 tokens per chunk, keep the heading path as metadata (`Liquid > Filters > money`).
- [ ] Embed chunks via Ollama (`nomic-embed-text` or similar) through the extended `ollama_client.py`.
- [ ] Store in ChromaDB (or SQLite + numpy if you want zero deps — a few thousand chunks needs nothing heavier). Persist under `subjects/<name>/index/`.
- [ ] CLI: `python -m app.ingest --subject shopify` — idempotent, re-indexes only changed files (hash check).
- [ ] Seed the first subject: download the Shopify Liquid docs into `subjects/shopify/docs/` and index them.

**Deliverable:** One command turns a folder of docs into a queryable index.
**Done when:** Re-running ingest on unchanged docs is a no-op; adding one file indexes only that file.

---

## Phase 3 — Retrieval + grounded answering [NET-NEW]

**Goal:** The core loop: question → relevant doc chunks → answer that cites them or admits gaps.

**Tasks**
- [ ] Build `retriever.py`: embed the question, return top-k chunks with scores + heading paths. Configurable `top_k` and a minimum-score threshold.
- [ ] Inject retrieved chunks into the compiled prompt inside a clearly delimited block: `--- DOCUMENTATION (cite by section) ---`.
- [ ] Low-confidence path: if no chunk clears the threshold, the injected block says so explicitly and the rules require the model to lead with "the provided docs don't cover this."
- [ ] Citation format in answers: `(docs: Liquid > Filters > money)` — cheap to render as a badge later.
- [ ] Honesty lint (in `lint.py`): if the answer asserts a doc-specific fact (filter/tag/API names) but retrieval returned nothing relevant, flag it; regenerate with a "stick to the docs or say you don't know" reminder.
- [ ] CLI smoke test: `python -m app.ask --subject shopify "how do I format currency in Liquid?"`.

**Deliverable:** Grounded single-turn Q&A over the Shopify docs.
**Done when:** A question the docs answer gets a cited answer; a question they don't answer gets an explicit "not in the docs" instead of an invented filter.

---

## Phase 4 — Code-dump guardrail [PORT — lint framework, new rules]

**Goal:** Mechanically stop the tutor from just handing over solutions.

**Tasks**
- [ ] Extend `lint.py` with response inspection:
  - Count fenced code blocks and contiguous code lines per block.
  - Threshold from profile: `scaffolding: 5` might cap at ~5 lines/block, `scaffolding: 1` effectively uncapped. Global ceiling in `config.yaml`.
  - Detect "complete solution" shape (e.g., full file, or code that directly implements the user's stated task end-to-end) vs. illustrative fragment.
- [ ] Retry loop (ported): on violation, regenerate with the violation appended — "convert this to a hint plus a ≤N-line partial snippet." Cap at 3 attempts.
- [ ] Bypass mechanism: an explicit user phrase (configurable, e.g., "solve it") lifts the cap for that single turn; the tutor should still explain the solution after showing it.
- [ ] Track bypass usage per session — if the learner bypasses constantly, surface a gentle note (and maybe that's a signal to lower `scaffolding` in the profile).
- [ ] Unit tests: solution-shaped response is caught; fragment passes; bypass works for exactly one turn.

**Deliverable:** A tutor that structurally cannot dump full code unless asked.
**Done when:** "Write me the whole product template" yields hints + a partial snippet on the first attempt, and the full template only after the bypass phrase.

---

## Phase 5 — Chat loop & session memory [NET-NEW]

**Goal:** Turn one-shot Q&A into an actual tutoring conversation that remembers.

**Tasks**
- [ ] Build `chat.py`: REPL-style loop — each turn runs retrieval → compile → generate → lint/retry → display.
- [ ] In-session memory: full history in every call, trimmed to the context budget (drop oldest turns first, never the session summary).
- [ ] Persistent memory: on session end (or every N turns), generate a compact summary — topics covered, learner struggles, open threads — saved to `sessions/<subject>-progress.md`. Loaded into every future session so lessons build instead of restarting cold.
- [ ] Session transcripts saved to `sessions/` with frontmatter (date, subject, profile, models, rules git-hash) — same provenance pattern as seo-app outputs.
- [ ] Commands inside chat: `/quiz` (generate questions on covered material), `/summary`, `/sources` (show chunks behind the last answer), `/solve` (the bypass).
- [ ] CLI entry: `python -m app.chat --subject shopify --profile casey`.

**Deliverable:** Terminal tutoring sessions with memory across days.
**Done when:** A second session references what the first covered without being told.

---

## Phase 6 — Subject management [PORT — mirrors profile system]

**Goal:** Adding a new subject is a five-minute step, like adding a business was.

**Tasks**
- [ ] `python -m app.subject new <name>` — creates the folder trio (docs/, index/, overlay.md stub).
- [ ] Subject overlay support in the compiler (e.g., Shopify overlay: "prefer Online Store 2.0 patterns; flag deprecated Liquid tags when they appear in docs or user code").
- [ ] Subject validation on load: docs present, index built and non-stale (warn if docs changed since last ingest).
- [ ] Support switching subjects mid-app (not mid-session) and multiple subjects side by side.

**Deliverable:** Second subject (pick anything — e.g., Tailwind) added end-to-end as a test.
**Done when:** New subject goes from empty folder to answerable questions in ≤5 minutes plus ingest time.

---

## Phase 7 — Online trends feature [NET-NEW]

**Goal:** "Also look online for newer trends" — as an explicit, labeled secondary source, never silently mixed with docs.

**Tasks**
- [ ] Build `websearch.py` behind a provider interface. Option A: self-hosted SearXNG (matches the fully-local philosophy). Option B: hosted API (Brave/Tavily) for less setup. Config-selectable.
- [ ] Trigger rules: user asks explicitly ("what's new in…", "current best practice"), user runs `/trends <topic>`, or retrieval confidence was low and the user opts in when prompted.
- [ ] Fetch top results, strip to text, inject as a second delimited block: `--- WEB RESULTS (recent, unofficial — label as such) ---`.
- [ ] Rules addition: answers must attribute clearly — "the official docs say X; recent community sources suggest Y" — and include result dates when available.
- [ ] Cache results per query per day to avoid hammering the search provider.
- [ ] Offline behavior: feature degrades gracefully to "web search unavailable" — everything else keeps working.

**Deliverable:** `/trends shopify liquid 2026` returns a docs-vs-current-practice comparison with sources.
**Done when:** Doc facts and web claims are visibly distinguished in every mixed answer.

---

## Phase 8 — Streamlit chat UI [PORT — pages pattern, new chat surface]

**Goal:** The easy-to-use layer; all logic already proven in CLI.

**Tasks**
- [ ] Page 1 — **Chat:** subject + profile selectors, streaming chat, citation badges on answers (click to view the doc chunk), lint-retry indicator, `/solve` as a button.
- [ ] Page 2 — **Subjects:** create subject, drag-and-drop docs upload, ingest button with progress, index status.
- [ ] Page 3 — **Profile:** learner sliders + known-topics editor (mirrors the CLI wizard).
- [ ] Page 4 — **Progress:** per-subject summaries, past session transcripts, quiz history.
- [ ] Settings: Ollama host, model pickers (from `ollama list`), web-search provider toggle.
- [ ] Graceful states: Ollama offline, index stale, web search disabled.

**Deliverable:** `streamlit run app/main.py` — full tutoring workflow, zero terminal.
**Done when:** Upload Liquid docs → set profile → have a cited, hint-first tutoring session entirely in the browser.

---

## Phase 9 — Hardening & docs [PORT]

**Tasks**
- [ ] End-to-end test: 2 subjects × 2 profiles, including a docs-gap question and a bypass turn.
- [ ] Pinned dependencies, setup script (checks Ollama, pulls chat + embed models, creates dirs).
- [ ] Docs: quickstart, "adding a subject" guide, profile-writing guide, web-search setup (SearXNG vs. API).
- [ ] Revisit the Phase 0 note: if seo-app is still active, extract the shared `core/` library now (compiler, ollama_client, lint framework, tone translator) and have both apps depend on it.

**Done when:** Fresh machine → tutoring session in under 15 minutes.

---

## Deferred (build when pain appears)

- **Spaced-repetition layer** — auto-generate flashcards from session summaries, schedule reviews.
- **Code-review mode** — learner pastes their Liquid; tutor critiques against docs + overlay rules instead of answering questions.
- **Multi-doc freshness checks** — detect when local docs are older than what web results describe and suggest re-ingesting.
- **Voice or IDE integration** — only if the browser chat proves limiting.

---

## Phase order & dependencies

```
Phase 0 ──▶ Phase 1 ──▶ Phase 2 ──▶ Phase 3 ──▶ Phase 5 ──▶ Phase 8 ──▶ Phase 9
                             │           │          ▲
                             │       Phase 4 ───────┤   (guardrail wraps every chat turn)
                             └────── Phase 6 ───────┘   (subjects feed retrieval)
                                     Phase 7 ───────┘   (optional; anytime after 5)
```

Phases 4 and 6 can run in parallel after Phase 2. Phase 7 (web trends) is deliberately late and optional — the tutor must be excellent offline first.

**Port-vs-new summary:** Phases 0, 1, 6, 9 are mostly ports; Phase 4 ports the lint framework with new rules; Phases 2, 3, 5, 7 are the net-new work — and of those, Phase 3 (grounded answering) is the heart of the app.
