# SEO Content App — Implementation Plan

A simplified, self-contained app built on the existing `SEO-LLM` prompt foundation. All models run locally via Ollama. All tailoring lives in app-layer markdown (never baked into Modelfiles). The app owns every constraint: banned words, tone levels, length bounds, and enforcement.

**Core workflow:** Tailor to a business → scan an SEO brief → extract keywords → generate small content using approved keywords → lint and deliver.

---

## Guiding principles (carried over from SEO-LLM)

1. **App-layer prompts only.** Base Ollama models stay project-agnostic. Every SEO rule, voice, and constraint ships as a markdown/config edit via git — no model rebuilds.
2. **Durable vs. volatile split.** Stable rules (`seo-core.md`) are separated from Google-posture rules (`google-rules.md`) so volatile edits never touch durable files.
3. **Constraints are data, not prose.** Banned words and tone levels live in structured YAML frontmatter so the app can both inject them into prompts *and* mechanically verify outputs.
4. **Layers earn their way in.** No SERP scraping, retrieval, batching, or schema generation until a concrete pain point demands it.

---

## Target structure

```
seo-app/
├── app/
│   ├── main.py            # Streamlit UI (Phase 7)
│   ├── compiler.py        # stacks rules + profile + brief into final prompt
│   ├── ollama_client.py   # Ollama calls; format=json for structured passes
│   ├── brief_parser.py    # reads uploaded briefs (md / txt / docx)
│   ├── tone.py            # slider value → instruction-sentence lookup
│   └── lint.py            # banned-word grep, length checks, retry loop
├── rules/
│   ├── seo-core.md        # durable (merged system.md + formatting.md)
│   └── google-rules.md    # volatile, reviewed on core updates
├── profiles/
│   └── <business>.md      # per-business: YAML frontmatter + voice prose
├── briefs/                # uploaded briefs (input)
├── outputs/               # generated content (output)
├── tests/
└── config.yaml            # model names, retry caps, defaults
```

---

## Phase 0 — Repo restructure & migration

**Goal:** Convert the decision-record repo into the app skeleton without losing prompt work.

**Tasks**
- [ ] Create the directory structure above in a new branch (or new repo if kept separate from `~/ai/`).
- [ ] Merge `prompts/seo/system.md` + `formatting.md` + `personality.md` → `rules/seo-core.md`. Strip anything business-specific into a profile template instead.
- [ ] Move `prompts/seo/google-rules.md` → `rules/google-rules.md` unchanged. Extract its banned-word list into a machine-readable block (see Phase 3).
- [ ] Archive the old README as `docs/decision-record.md` — it remains the "why we picked X" reference.
- [ ] Write a new top-level `README.md` describing the app workflow in ≤1 page.
- [ ] Add `config.yaml` with: model names (prose model, structured model), Ollama host/port, retry cap, default output types.

**Deliverable:** Clean skeleton; rules migrated; old decisions preserved.
**Done when:** `rules/` contains exactly two files and nothing references the old `prompts/seo/` paths.

---

## Phase 1 — Prompt compiler (CLI-first, no UI)

**Goal:** Prove the layered prompt stack produces a single, correct system prompt.

**Tasks**
- [ ] Build `compiler.py` with one function: `compile_prompt(profile_path, brief_text, keywords, task) -> str`.
- [ ] Stacking order (durable → volatile → per-run):
  1. `rules/seo-core.md`
  2. `rules/google-rules.md`
  3. Tone instructions (from profile frontmatter, translated by `tone.py`)
  4. Profile voice prose (markdown body)
  5. Brief summary + approved keywords + task instruction
- [ ] Build `tone.py`: lookup table mapping each slider (formality, energy, technicality — each 1–5) to a concrete instruction sentence. Numbers are never sent raw to the model.
- [ ] Add a `--dry-run` CLI flag that prints the compiled prompt for inspection.
- [ ] Create one hardcoded test profile in `profiles/` with realistic frontmatter.

**Deliverable:** `python -m app.compiler --profile profiles/test.md --dry-run` prints a sane, fully-stacked prompt.
**Done when:** Reordering or editing any layer file changes the output with no code changes.

---

## Phase 2 — Ollama client & structured keyword extraction

**Goal:** Reliable local model calls, including guaranteed-JSON keyword output.

**Tasks**
- [ ] Build `ollama_client.py` wrapping `/api/chat`: prose mode and structured mode (`format` = JSON schema).
- [ ] Define the keyword schema: `{primary: [str], secondary: [str], long_tail: [str], rationale: str}`.
- [ ] Implement `extract_keywords(brief_text, profile) -> KeywordSet` using the structured model (granite-class), with the compiled prompt from Phase 1.
- [ ] Handle failure modes: Ollama not running, model not pulled, malformed JSON (one automatic re-ask before surfacing an error).
- [ ] CLI entry: `python -m app.keywords --brief briefs/example.md --profile profiles/test.md`.

**Deliverable:** Brief in → clean keyword JSON out, every time.
**Done when:** 10 consecutive runs against a sample brief return schema-valid JSON with zero manual parsing.

---

## Phase 3 — Constraint engine (lint + retry loop)

**Goal:** Mechanical enforcement of everything the app promises: banned words, tone, length.

**Tasks**
- [ ] Define the constraint schema in profile frontmatter:
  ```yaml
  banned_words: [delve, elevate, unlock, "in today's fast-paced world"]
  tone: {formality: 3, energy: 2, technicality: 4}
  length: {meta_description: [140, 160], intro: [80, 150]}
  ```
- [ ] Global banned words also live in `rules/google-rules.md` frontmatter; the lint merges global + profile lists.
- [ ] Build `lint.py`:
  - Banned-word/phrase check (case-insensitive, word-boundary regex).
  - Length bounds per content type.
  - Heading-hierarchy check for longer pieces (no skipped levels).
  - Keyword-presence check (each approved primary keyword appears ≥1×, density ≤ configurable ceiling).
- [ ] Build the retry loop: on failure, regenerate *only the failing piece* with the failure reason appended to the prompt. Hard cap at 3 attempts, then surface to the user with the specific violations listed.
- [ ] Unit tests for every lint rule.

**Deliverable:** `lint(content, profile) -> LintReport` plus a `generate_with_retries()` wrapper.
**Done when:** A deliberately violating output is caught, regenerated, and passes — or fails loudly with a readable report after 3 tries.

---

## Phase 4 — Business profile system

**Goal:** Make "tailor to a business" a five-minute, repeatable step.

**Tasks**
- [ ] Design the profile template (`profiles/_template.md`): frontmatter (name, audience, region, banned_words, tone, length) + body sections (voice notes, positioning, credentials/anecdotes usable for E-E-A-T, topics to avoid).
- [ ] Build a CLI wizard: `python -m app.profile new` — asks the questions, writes the file.
- [ ] Add profile validation (required fields present, tone values in range, no empty voice body) — run on load, not just creation.
- [ ] Support multiple profiles side by side; profile choice is a parameter everywhere downstream.

**Deliverable:** Anyone can create a valid business profile via prompts in the terminal.
**Done when:** Two different profiles produce visibly different tone/vocabulary from the same brief.

---

## Phase 5 — Brief ingestion & keyword approval

**Goal:** Accept real-world briefs and put a human checkpoint before generation.

**Tasks**
- [ ] Build `brief_parser.py`: accept `.md` and `.txt` first; add `.docx` (via python-docx) second. Normalize to plain text + light structure (title, sections).
- [ ] Extract brief metadata when present (target keyword hints, word counts, audience notes) and pass to the compiler as context.
- [ ] Keyword approval step: present extracted keywords grouped by tier; user approves/edits/prunes before anything is generated. CLI version first (numbered select), UI version in Phase 7.
- [ ] Persist the approved keyword set alongside the brief in `briefs/<name>.keywords.json` so a run is reproducible.

**Deliverable:** Brief file → parsed text → keyword proposal → approved set on disk.
**Done when:** Re-running generation uses the saved approved set without re-extracting.

---

## Phase 6 — Content generation pipeline

**Goal:** End-to-end: approved keywords → linted small-content package.

**Tasks**
- [ ] Define the "small content" package (configurable per run):
  - Meta title + meta description
  - Intro paragraph
  - 2–3 section blurbs (question-based headings per `seo-core.md`)
  - Optional: social snippet
- [ ] Each piece is a separate model call with its own length constraint — small local models do short pieces far better than one monolithic generation.
- [ ] Route calls: prose model (llama-class) for body text, structured model for meta/title JSON. Allow a single-model config for simpler setups.
- [ ] Wire every piece through `generate_with_retries()` (Phase 3).
- [ ] Assemble the package into `outputs/<business>/<brief>/<date>.md` with a frontmatter header recording: profile used, rules versions (git hash), model names, keywords, lint results.
- [ ] CLI: `python -m app.generate --brief ... --profile ...` runs the full pipeline.

**Deliverable:** One command, full linted package on disk with provenance metadata.
**Done when:** Output passes lint, uses approved keywords, and reads in the profile's voice on manual review.

---

## Phase 7 — Streamlit UI

**Goal:** The "easy to use app" layer. Thin wrapper — all logic already exists.

**Tasks**
- [ ] Page 1 — **Profiles:** list/create/edit profiles (form mirrors the CLI wizard; sliders for tone; tag input for banned words).
- [ ] Page 2 — **Generate:** select profile → upload brief → view/approve keywords (checkboxes) → pick package pieces → generate with progress per piece → results view with lint badges.
- [ ] Page 3 — **Outputs:** browse past runs, copy buttons per piece, download as .md.
- [ ] Settings panel: Ollama host, model selection (auto-list from `ollama list`), retry cap.
- [ ] Graceful states: Ollama offline banner, generation-in-progress spinners, lint-failure explanations in plain language.

**Deliverable:** `streamlit run app/main.py` — the full workflow with zero terminal use.
**Done when:** A non-technical user completes profile → brief → content without documentation.

---

## Phase 8 — Hardening, packaging, docs

**Goal:** Make it durable and shareable.

**Tasks**
- [ ] End-to-end test with 2 real briefs × 2 profiles; fix rough edges.
- [ ] `requirements.txt` / `pyproject.toml`, pinned versions.
- [ ] One-command setup script: checks Ollama, pulls configured models, creates dirs.
- [ ] Docs: quickstart, profile-writing guide (with a good/bad frontmatter example), "updating google-rules.md" runbook tied to the RSS-notify habit from the decision record.
- [ ] Optional: package as a single `seo-app` entry point (pipx-installable).

**Done when:** A fresh machine goes from clone → generated content in under 15 minutes.

---

## Phase 9 — Deferred layers (build only when pain appears)

Not in scope now; listed so they're deliberate decisions later:

- **Experiential-claim guard** — lint check that generated first-hand claims don't exceed what the profile/brief supplied (top candidate for first addition).
- **Outcome log** — publish date + rules version + post-update traffic delta, closing the "survive the next core update" loop.
- **SERP gap analysis** — scrape top-10, diff against generated content.
- **Retrieval grounding** — inject source material to reduce fabrication on factual pieces.
- **Batch mode** — CSV of briefs in, folder of packages out (only after lint loop is proven).
- **Full-article generation** — extend "small content" to long-form using the same pipeline.

---

## Phase order & dependencies

```
Phase 0 ──▶ Phase 1 ──▶ Phase 2 ──▶ Phase 3 ──▶ Phase 6 ──▶ Phase 7 ──▶ Phase 8
                             │           │          ▲
                             │       Phase 4 ───────┤   (profiles feed generation)
                             └────── Phase 5 ───────┘   (briefs/keywords feed generation)
```

Phases 4 and 5 can run in parallel after Phase 2. Everything before Phase 7 is CLI-verifiable, so quality is proven before any UI work begins.
