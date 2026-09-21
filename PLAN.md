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
2. **CC is the harness.** No custom CLI, workflow engine, or storage layer. Just skills, prompts, Bash, and files.
3. **Deterministic pipelines.** Stages run in order, with no autonomous loops in MVP.
4. **Section-based generation.** Long articles are never produced in a single call.
5. **Multi-pass quality.** Draft → rewrite → SEO/metadata.
6. **SEO-centric.** Prompts ground in intent, semantic coverage, EEAT.

---

## Architecture

Built (one skill per stage, run in order):

```
User in Claude Code
  ├─ /seo-research <slug>  scripts/fetch_page.sh (no model call)              → research/<slug>/page.json
  ├─ /seo-ingest  <file>   pdftotext/pandoc + prompts/ingest.md (schema)      → briefs/<slug>.json
  ├─ /seo-outline <brief>  prompts/outline.md                                → outline.md
  ├─ /seo-draft   <brief>  scripts/draft_sections.sh: per-part call
  │                        (intro/section/conclusion.md) + verify.md          → sections/*, draft.md
  └─ /seo-rewrite <brief>  scripts/rewrite_sections.sh: per-part rewrite.md
                           (REWRITE_MODEL) + verify.md                        → rewrite/*, final.md
```

Phases 6 to 13 are built, so the research stage runs end to end: page check, competitor and export collection, keyword choice, a staged brief builder, and the research detail reaching the outline. Planned next are a metadata pass writing `meta.json` (Phase 14), and an SEO knowledge base grounding the prompts in `SEO-GUIDE.md` plus a `/seo-generate` skill (Phase 15).

The research stage ahead of ingest was added 2026-09-20. Search Console data arrives as files the user exports, never through an API, so the pipeline needs no keys and breaks nobody's terms of service. Search engine results pages are never scraped. Measured first-party data is preferred, and third-party keyword estimates are the accepted fallback when Search Console has no history for the page, which is the case for a new site or a topic the site has never ranked for. The CSV parser reads a volume column either way. Estimates were dropped outright on 2026-09-20 and reinstated as a fallback on 2026-09-21, because the first-party-only rule left a pre-launch site with nothing but competitor headings to choose from.

No Python app. No workflow engine. No SQLite.

---

## Folder structure

```
SEO-LLM/
├── .claude/
│   ├── skills/              # <name>/SKILL.md per command. Built: /seo-research, /seo-ingest, /seo-outline, /seo-draft, /seo-rewrite. Planned: /seo-keywords, /seo-brief, /seo-metadata, /seo-generate
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
│   ├── fetch_page.sh        # polite curl fetch of one page: robots, per-host delay, cache, extract
│   ├── llm_call.sh          # curl wrapper: prompt-file (+ optional temp/seed/schema) + prompts/system.md → stdout
│   ├── fill_prompt.sh       # {{PLACEHOLDER}} filling from brief / outline / source text
│   ├── draft_sections.sh    # per-part drafting loop with fact check, retry, stitch
│   ├── rewrite_sections.sh  # per-part rewrite loop with guards and fact check
│   ├── lib_parts.sh         # shared helpers: verify_part, heading restore, unbold, draft_factor
│   └── check.sh             # FAIL/WARN checks for brief, outline, section, rewrite, draft
├── research/                # <slug>/page.json, plus inputs/ and _cache/ (cache gitignored)
├── briefs/                  # JSON inputs
├── outputs/                 # <brief-slug>/{outline.md, sections/, draft.md, rewrite/, final.md}
├── docs/
│   └── google/              # planned (Phase 7): helpful-content.md, eeat.md, semantic-search.md, ai-content-guidelines.md
├── AGENTS.md
├── INSTRUCTIONS.md          # stage-by-stage walk through the pipeline
├── PLAN.md
├── README.md
└── SEO-GUIDE.md           # the SEO reference behind the pipeline (no script parses it, but check.sh mirrors its targets)
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

Briefs written by `/seo-brief` also carry four optional research keys,
`search_intent`, `must_cover`, `questions` and `existing_page`, which the outline
stage consumes. They are optional so that a hand-written brief and `/seo-ingest`
output remain valid (added 2026-09-20).

The shape is enforced twice: `prompts/brief.schema.json` constrains what the router may return during ingest, and `scripts/check.sh brief` re-checks the saved file with `jq`.

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

Each phase: one declarative goal, ≤5 files, atomic revert, end-to-end verification against the live llama.cpp router. **Live execution state (what is done, in progress, or remaining) lives in `IMPLEMENT.md` (untracked, see README), not here.** This section is the architectural breakdown, and IMPLEMENT.md is the tracker.

### Phase 1: Walking skeleton
- Files: `scripts/llm_call.sh` (the wrapper, replaced for the llama.cpp router on 2026-09-15), `prompts/section.md`, `.claude/skills/seo-draft/SKILL.md`, `.claude/settings.json`, `briefs/example.json`.
- Goal: `/seo-draft briefs/example.json` produces `outputs/<slug>/draft.md` via a single Qwen call.

### Phase 2: Outline stage
- Files: `prompts/outline.md`, `.claude/skills/seo-outline/SKILL.md`, update `seo-draft` to consume the outline.
- Goal: outline generated first and saved as `outline.md`, and the draft follows it.

### Phase 3: Brief ingest from .docx / .pdf / .md / .txt
- Files: `prompts/ingest.md`, `.claude/skills/seo-ingest/SKILL.md`, `.claude/settings.json` (allow `pandoc` + `pdftotext`), `PLAN.md`, `README.md`.
- Goal: `/seo-ingest <file>` extracts text (pandoc for .docx, pdftotext for .pdf, passthrough for .md/.txt) and emits `briefs/<slug>.json` matching the brief schema for the user to review before running `/seo-outline`.
- Gap: `pandoc` is not installed on this machine, so `.docx` ingest does not run yet. PDF, `.md`, and `.txt` work.

### Phase 4: Section-by-section drafting (done 2026-09-16)
- Files: `scripts/draft_sections.sh`, `prompts/intro.md`, `prompts/section.md` (now per section), `prompts/conclusion.md`, `seo-draft` skill.
- Goal: each outline section → its own model call, stitched into `draft.md` (the rewrite phase produces `final.md`).
- Each part then gets a fact-verification call (`prompts/verify.md`) whose replacements are applied only when they pass deterministic guards (see README).
- Failure handling as implemented: a failed section check is retried once with seed 2 (not a higher temperature: the same seed repeats the output, a new seed does not), then saved as `sections/NN-<heading>.ERROR.md`.

### Phase 5: Humanization rewrite (done 2026-09-16)
- Files: `prompts/rewrite.md`, `scripts/rewrite_sections.sh`, `.claude/skills/seo-rewrite/SKILL.md`, `check.sh rewrite`.
- Goal: a post-draft rewrite pass reduces repetition and awkward keyword phrasing without changing facts, and writes `final.md`.
- Model: chosen by a qwen vs gemma comparison on the three test briefs (see IMPLEMENT.md). `REWRITE_MODEL` overrides it.

### Phase 6: Page check and snapshot (done 2026-09-20)
- Files: `scripts/fetch_page.sh`, `.claude/skills/seo-research/SKILL.md`, `.gitignore`, `PLAN.md`, `README.md`.
- Goal: `/seo-research <slug>` asks whether the page exists and writes `research/<slug>/page.json`, snapshotting the live page when there is one.
- The fetcher honors `robots.txt`, sends a configurable User-Agent (`FETCH_UA`, no contact address by default), keeps a per-host delay, and caches raw HTML so a rerun does not hit the host again.

### Phase 7: Research collection (done 2026-09-20)
- Files: `scripts/research_collect.sh`, `scripts/check.sh`, the `seo-research` skill.
- Goal: the Search Console export in `research/<slug>/inputs/` plus competitor URLs become one `research/<slug>/research.json`. Any other keyword export parses too, since columns are read by name.

### Phase 8: Keyword choice (done 2026-09-20)
- Files: `prompts/keywords.md`, `prompts/keywords.schema.json`, `.claude/skills/seo-keywords/SKILL.md`, `scripts/check.sh`.
- Goal: `/seo-keywords <slug>` picks the primary and secondary keywords, reads the intent (type, format, angle), and scores business potential, all grounded in `research.json`.

### Phases 9 and 10: Staged brief builder (done 2026-09-20)
- Files: `scripts/brief_stages.sh`, `prompts/brief-intent.md`, `prompts/brief-structure.md`, `prompts/brief-targets.md`, `prompts/brief-facts.md`, `.claude/skills/seo-brief/SKILL.md`.
- Goal: four approved stages (intent and audience, structure and gaps, keywords and length, facts and CTA) merge into `briefs/<slug>.json` in the current seven-key shape.

### Phase 11: Research detail in the brief (done 2026-09-20)
- Files: `prompts/brief.schema.json`, `scripts/check.sh`, `prompts/outline.md`, `scripts/brief_stages.sh`, `scripts/fill_prompt.sh`, `README.md`, `PLAN.md`.
- Goal: optional `search_intent`, `must_cover`, `questions` and `existing_page` keys reach the outline, so it covers the competitor gaps.
- The keys are optional, so hand-written briefs and `/seo-ingest` output stay valid. `check.sh brief` requires the seven, allows these four, and rejects anything else.
- Observed: from the same merged brief, the outline built with the keys followed the researched subtopics and used the researched FAQ questions, while the same brief stripped of them produced a structure of the model's own invention.

### Phase 12: Punctuation fixes from the pipeline QA (done 2026-09-20)
- Files: `scripts/lib_parts.sh`.
- Goal: stop the verifier's punctuation tidy from deleting the space before a dotted token (".example", ".org", ".json"), and stop the absolute-wording pattern splitting a sentence inside "example.com".
- Both were found by a full end-to-end QA run and reproduced minimally before the fix.

### Phase 13: SEO-GUIDE.md expanded to baseline and intermediate (done 2026-09-20)
- Files: `SEO-GUIDE.md`, `README.md`, `PLAN.md`.
- Goal: the guide covers the fundamentals and the intermediate practice, so it can ground the prompts in the knowledge-base phase.
- Added a measurement and tooling module, search intent types and SERP features, white hat against black hat, E-E-A-T, the helpful-content and AI-content position, structured data, cannibalization and topic clusters, local SEO, a measurement module, a glossary, and an appendix mapping the guide to the pipeline. Its title, meta description and competitor-count targets are mirrored in `scripts/check.sh`, so they are locked.

### Phase 14: Metadata + keywords
- Files: `prompts/metadata.md`, `prompts/keywords.md`, `.claude/skills/seo-metadata/SKILL.md`, `.claude/skills/seo-keywords/SKILL.md`.
- Goal: title, description, slug, FAQ, keyword expansion written to `meta.json`.

### Phases 16 to 18: The interactive menu (done 2026-09-20)
- Files: `scripts/seo.sh`, `.claude/settings.json`, `README.md`, `INSTRUCTIONS.md`.
- Goal: `bash scripts/seo.sh [slug]` is the front door. It reads each stage's state from the artifacts on disk, runs the stage you pick, and `a` runs every ready stage in turn.
- It stops before stages that need typed input, stops after each brief stage so it gets read, and stops at the first failure. Plain bash, no new dependency, so the declared stack is unchanged.

### Phases 19 to 21: First-party data only, and the sitemap as an inventory (done 2026-09-20)
- Files: `SEO-GUIDE.md`, `README.md`, `INSTRUCTIONS.md`, `PLAN.md`, both research skills, `prompts/keywords.md`, `scripts/check.sh`, `scripts/seo.sh`, `scripts/fetch_page.sh`, `scripts/fetch_sitemap.sh`, `scripts/research_collect.sh`.
- Goal: the pipeline is documented and reasons around measured data. The Search Console Performance export is the source, third-party keyword estimates are gone from the guidance, and the 3 C's framing left the guide while `keywords.json` kept its type, format and angle fields.
- The CSV parser deliberately keeps its Ahrefs column aliases, so an export a user already holds still works.
- `scripts/fetch_sitemap.sh` builds a per-site page inventory from `sitemap.xml` (via `robots.txt`, following a sitemap index one level) through `fetch_page.sh --raw`, and `research.json` gains `site_pages`, which is the cannibalization check and the internal-link candidate list.

### Phases 22 to 27: Hardening, the guide trim, and the outline repair (done 2026-09-21)
- Files: `scripts/llm_call.sh`, `scripts/draft_sections.sh`, `scripts/rewrite_sections.sh`, `scripts/lib_parts.sh`, `scripts/seo.sh`, `SEO-GUIDE.md`, `.claude/skills/seo-outline/SKILL.md`, `README.md`.
- `llm_call.sh` refuses a prompt file with no non-whitespace content (exit 2), because an empty prompt made the router answer the system message alone and return confident, unrelated text that could satisfy a schema.
- `draft_sections.sh` and `rewrite_sections.sh` read `OUTPUTS_DIR`, matching `seo.sh`, so a whole run can be verified in a scratch tree.
- `SEO-GUIDE.md` was trimmed from 10,094 to 6,964 words. Appendix B was removed and its statement that `check.sh` enforces three of the guide's targets moved into the opening note.
- `clean_outline` in `lib_parts.sh` repairs an outline deterministically before it is checked, dropping `_Intent:` and `Keywords:` lines that are not directly under an H2 and any prose under a heading, and printing what it removed.

### Phase 28: Estimated keyword data as a fallback (done 2026-09-21)
- Files: `scripts/check.sh`, `prompts/keywords.md`, `.claude/skills/seo-research/SKILL.md`, `SEO-GUIDE.md`, `PLAN.md`.
- Goal: measured first-party data stays the preference, and a third-party estimate is the accepted fallback when Search Console has no history for the page. This reverses the Phase 19 decision to drop estimates outright, which left a pre-launch site with nothing but competitor headings to choose from.
- No collection code changed. `research_collect.sh` already mapped the Ahrefs columns, already detected the tab-separated file Ahrefs ships under a `.csv` name, and already sorted by volume before clicks. Phase 19 had removed the guidance, never the reader.
- `check.sh research` now separates three cases: measured data present, estimated only, and no demand data at all. A volume column of zeroes counts as none, because that is an export artifact rather than a finding.
- `prompts/keywords.md` rule 2 is split into labelled Case A, B and C. The labelling is load-bearing and is not a style choice: with the fallback written as a trailing condition instead, the model called measured Search Console data "estimated volume" in 4 of 6 runs against 0 of 6 before the change. The split restored 0 of 6 while keeping the fallback working in 6 of 6.
- Measured across three prompt variants and three research fixtures at matched seeds, 30 live calls in total. That method is the Phase 24 and 25 lesson applied: a prompt change is judged on a rate across fixtures, never on one sample.

### Phase 29: A real export cannot inject a false keyword or a false measured signal (done 2026-09-21)
- Files: `scripts/research_collect.sh`, `scripts/check.sh`, `prompts/keywords.md`.
- Found by running the first real Ahrefs exports through the pipeline, not by review. Both faults were silent and produced plausible output.
- `canonical_header` now keeps the first column that claims a canonical name and drops later duplicates. An Ahrefs SERP overview carries both `Keyword` and `Keywords`, where the second counts the keywords a URL ranks for, so every keyword arrived as a number ("91", "54", "488"). The same file carries `Volume` and `Global volume`, and first-wins now takes the country figure rather than the global one.
- The measured-data test in `check.sh` no longer counts `position` as evidence. Search Console reports a position, but so does an Ahrefs SERP overview, where it is somebody else's rank. Reading it as first-party data made the check go silent on a file with no first-party data in it. Impressions and clicks carry no such collision, so the test is now those two. `prompts/keywords.md` Case A and B match.
- Verified against both real exports: the organic keywords file is unchanged at 73 keywords, the SERP overview went from 8 keywords (7 of them numeric) to 1, and from silent to correctly reporting estimated data. All five Phase 28 fixtures unchanged.
- Two phases were reverted and are recorded as failures rather than deleted: three prompt wordings aimed at the same outline faults each traded one structural failure for another when measured across briefs and seeds, which is why the repair is deterministic.

### Phase 15: Docs + SEO knowledge base
- Files: `README.md`, `docs/google/{helpful-content,eeat,semantic-search,ai-content-guidelines}.md`, link from system prompt.
- Goal: prompts ground in EEAT / helpful-content guidance, and the quickstart is documented.

Deferred (post-MVP): SERP extraction, competitor analysis, RAG, autonomous research, internal linking, topical authority (Milestones 4 and 5 in the old plan).

---

## Verification

After each phase:
1. The router serves `qwen`: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen`.
2. Run the latest skill in CC against `briefs/example.json`.
3. Inspect `outputs/<slug>/` for the artifacts that phase promised.
4. Spot-check generated text for SEO structure (H2s, keyword presence, no robotic intros).

No test framework in MVP. Generation is the test.

---

## Reuse audit

Project contains `AGENTS.md`, `PLAN.md`, and Phase-1-shaped stubs (`briefs/example.json`, `prompts/section.md`, `scripts/llm_call.sh`). External reuse:
- **llama.cpp router**: call its OpenAI-compatible HTTP API directly through `scripts/llm_call.sh`, with no client library.
- **Claude Code skills + Bash**: don't build a workflow engine.
- **JSON**: `jq`, already on the box, for reading briefs and checking them against `prompts/brief.schema.json`.

---

## Risks

1. **Repetitive outputs** → multi-pass rewrite, prompt variation, section drafting.
2. **Hallucinated SEO claims** → ground prompts in `docs/google/*` (Phase 7), and deterministic temps for metadata.
3. **Over-engineering** → no workflow engine, no DB, only skills and files.
4. **Router instability or model swaps** → single retry, then halt with an `.ERROR.md` marker and resume by hand. Another app using a different preset unloads `qwen`, so the next call pays its load time.

---

## Success criteria

These describe the finished MVP. `/seo-generate` and `meta.json` are planned (Phases 6 and 7), so today the same result takes the four stage commands and has no metadata.

MVP succeeds when a user can, on a local GPU box with the llama.cpp router serving `qwen`:
1. Drop a JSON brief into `briefs/`.
2. Run `/seo-generate` in CC.
3. Get a section-by-section, humanized, metadata-tagged markdown article in `outputs/<slug>/final.md`.
