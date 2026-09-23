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
3. **The local model generates, Claude Code audits.** Qwen does the volume work:
   keyword choice, brief stages, outlines, drafts, rewrites, anything long or
   repetitive. Claude Code's job is to read what came back against the research
   and say what is wrong with it. The two are not interchangeable. A judgement
   that needs reading ("does this rationale describe the data honestly", "does
   this section promise something the brief cannot support") belongs to the
   auditor, and a rule that can be decided by arithmetic or a lookup belongs in
   `scripts/check.sh`. Putting judgement into a regex produces a check that is
   wrong on real data, and putting arithmetic into a model call produces a result
   that cannot be audited.
4. **Deterministic pipelines.** Stages run in order, with no autonomous loops in MVP.
5. **Section-based generation.** Long articles are never produced in a single call.
6. **Multi-pass quality.** Draft → rewrite → SEO/metadata.
7. **SEO-centric.** Prompts ground in intent, semantic coverage, EEAT.
8. **The output is a file, never a publication.** The pipeline writes briefs and
   articles into this repo and stops there. Nothing is pushed into WordPress or
   any other CMS, and no stage publishes, submits or posts anything. The last
   step is always a person copying the result where they want it.

---

## Architecture

Built (one skill per stage, run in order):

```
./seo [slug]               scripts/seo.sh: intake for a new page, then the menu
                           that runs every stage below from one place

User in Claude Code
  ├─ /seo-research <slug>  scripts/fetch_page.sh (no model call)              → research/<slug>/page.json
  ├─ /seo-ingest  <file>   pdftotext/pandoc + prompts/ingest.md (schema)      → briefs/<slug>.json
  ├─ /seo-outline <brief>  prompts/outline.md                                → outline.md
  ├─ /seo-draft   <brief>  scripts/draft_sections.sh: per-part call
  │                        (intro/section/conclusion.md) + verify.md          → sections/*, draft.md
  └─ /seo-rewrite <brief>  scripts/rewrite_sections.sh: per-part rewrite.md
                           (REWRITE_MODEL) + verify.md                        → rewrite/*, final.md
```

Phases 6 to 13, 16 to 32 and 33 to 38 are built, so the research stage runs end to end (page check, competitor and export collection, keyword choice, a staged brief builder, the research detail reaching the outline), and `./seo` is the front door that walks a new page through its inputs and then runs any stage. Planned next are a metadata pass writing `meta.json` (Phase 14), and a `/seo-generate` skill (Phase 15). The knowledge-base half of Phase 15 rested on `SEO-GUIDE.md`, which was removed from the repo on 2026-09-22, so it needs a new source before it means anything.

The research stage ahead of ingest was added 2026-09-20. Search Console data arrives as files the user exports, never through an API, so the pipeline needs no keys and breaks nobody's terms of service. Search engine results pages are never scraped. Measured first-party data is preferred, and third-party keyword estimates are the accepted fallback when Search Console has no history for the page, which is the case for a new site or a topic the site has never ranked for. The CSV parser reads a volume column either way. Estimates were dropped outright on 2026-09-20 and reinstated as a fallback on 2026-09-21, because the first-party-only rule left a pre-launch site with nothing but competitor headings to choose from.

No Python app. No workflow engine. No SQLite.

---

## Folder structure

```
SEO-LLM/
├── .claude/
│   ├── skills/              # <name>/SKILL.md per command. Built: /seo-research, /seo-keywords, /seo-brief, /seo-ingest, /seo-outline, /seo-draft, /seo-rewrite. Planned: /seo-metadata, /seo-generate
│   └── settings.json        # allow the entry scripts, jq, extractors, and Bash(curl -s localhost:8080/models)
├── seo                      # launcher at the repo root: ./seo [slug] → scripts/seo.sh
├── prompts/
│   ├── system.md            # system message sent on every model call
│   ├── brief.schema.json    # ingest output schema
│   ├── ingest.md
│   ├── keywords.md          # the keyword choice, with keywords.schema.json
│   ├── keywords-suggested.md # appended when you suggested keywords at the menu
│   ├── keywords-type-<type>.md, brief-type-<type>.md  # appended for a typed page
│   ├── brief-intent.md, brief-structure.md, brief-targets.md, brief-facts.md
│   ├── outline.md
│   ├── intro.md
│   ├── section.md           # each topic H2 and the FAQ
│   ├── conclusion.md
│   ├── verify.md            # fact check, with verify.schema.json
│   ├── rewrite.md
│   ├── system/              # planned (Phase 7): SEO standards, anti-generic rules, tone, EEAT
│   ├── metadata.md          # planned (Phase 6)
├── scripts/
│   ├── seo.sh               # the intake and the interactive menu, state read from the artifacts
│   ├── fetch_page.sh        # polite curl fetch of one page: robots, per-host delay, cache, extract
│   ├── fetch_sitemap.sh     # sitemap.xml and sitemap indexes → research/_sitemaps/<host>.txt
│   ├── research_collect.sh  # exports + competitor pages → research/<slug>/research.json
│   ├── brief_stages.sh      # one call per brief stage, then --merge into briefs/<slug>.json
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
- Failure handling as implemented: a failed section check is retried at a new seed (not a higher temperature: the same seed repeats the output, a new seed does not), then saved as `sections/NN-<heading>.ERROR.md`. Widened to two retries in Phase 74 after two failures at consecutive seeds turned out to have different causes.

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

### Phase 13: SEO-GUIDE.md expanded to baseline and intermediate (done 2026-09-20, the file was removed from the repo on 2026-09-22; the entries below are the record of work on a file that no longer exists)
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

### Phase 30: Briefs carry a content type, starting with review (done 2026-09-21)
- Files: `scripts/brief_stages.sh`, `scripts/check.sh`, `prompts/brief.schema.json`, `prompts/brief-type-review.md`.
- `brief_stages.sh --type review` records the type once in `brief-stages/type.txt`, the same record-once rule as `purpose.txt`, and refuses to change it on a slug that already has one.
- The type block is **appended to the filled prompt**, not templated into `prompts/brief-structure.md`. That keeps the template untouched, so a run with no type is byte-identical to before the flag existed rather than merely similar. An earlier attempt did template a `{{CONTENT_TYPE}}` placeholder in and left two blank lines of difference.
- The review block's rule is that the model has not used the product and knows nothing about it, so each section's `purpose` is an instruction to Casey about what to record. Measured against an untyped run on the same research: typed put the verdict first and added how-we-tested and who-it-suits, untyped put the verdict last and invented a "Manufacturer Background" section the research does not support.
- `content_type` is optional in `brief.schema.json` and in `check.sh brief`, so every brief written before this phase stays valid. The check was shown to FAIL on an out-of-enum value.

### Phase 31: The structure stage is checked against the research it claims (done 2026-09-21)
- Files: `scripts/check.sh`, `scripts/brief_stages.sh`, `prompts/brief-structure.md`, `prompts/brief-stage.schema.json`.
- `check.sh stage <structure.json> <research.json> <keywords.json>` FAILs a section whose `source` names evidence that is not in the research or the keyword choice. `brief_stages.sh` runs it inline as the structure stage is written.
- `source` now carries its evidence (`must_cover: cleaning the pump`) rather than a bare category. **The blocking cause was the schema, not the prompt:** `source` was an enum of the three category labels, so the router could not emit evidence at all and the prompt rewrite had no effect until the enum was removed. Shape is now held by the deterministic check instead, which is where this repo puts quality anyway.
- `page purpose` is the one source carrying no evidence. It is accepted, because a review's verdict genuinely comes from the page purpose, but a WARN fires when more than half the sections use it.
- Verified: an invented "Manufacturer Background" section FAILs by name, the old bare-category format FAILs, a genuinely traced stage passes, and the passes were confirmed real by reading `must_cover` and the competitor headings rather than trusting exit 0.

### Phase 32: The menu can stop at the brief (done 2026-09-21)
- Files: `scripts/seo.sh`, `README.md`.
- `SEO_BRIEF_ONLY=1` truncates `STAGE_IDS` and `STAGE_LABELS` together at `brief`, so the menu offers five stages and `a` finishes once the brief is written. Every other part of the script indexes one array by the other's position, which is why they are sliced together rather than filtered at render time.
- The outline, draft and rewrite stages keep working and are only hidden. Verified on a slug carrying a finished outline, draft and final: the menu showed five stages and `outputs/` was byte-for-byte unchanged.
- This is the scope reset of 2026-09-21 made operational: the brief is the deliverable, and the drafting stages stay in the repo without being in the way.
- Two phases were reverted and are recorded as failures rather than deleted: three prompt wordings aimed at the same outline faults each traded one structural failure for another when measured across briefs and seeds, which is why the repair is deterministic.

### Phases 33 to 35: Keyword-stage grounding and the content type (done 2026-09-21)
- Files: `prompts/keywords.md`, `prompts/brief-targets.md`, `scripts/check.sh`, `scripts/seo.sh`, `scripts/brief_stages.sh`.
- `questions` may be mined from question-shaped and problem-shaped keywords, not only from competitor headings, because the model already did so in 3 runs of 5 and an empty list reached a real brief.
- The call to action may not point at a section the structure does not contain. Two rewordings were measured and rejected before one held at every seed.
- The content type is asked once per page before the keyword choice and recorded in `research/<slug>/type.txt`, so the page's format is settled before the term it targets is.

### Phase 36: One command at the repo root (done 2026-09-21)
- Files: `seo`, `README.md`.
- `./seo [slug]` resolves the repository from its own path and hands over to `scripts/seo.sh`, so the front door is one short command from any directory. A shell alias was rejected because it lives outside the repository, and a Makefile would add a second runner the stack rules forbid.

### Phase 37: The keyword stage takes the keywords you suggest (done 2026-09-21)
- Files: `scripts/seo.sh`, `scripts/check.sh`, `prompts/keywords-suggested.md`, `README.md`.
- Keywords you type at the menu are saved to `research/<slug>/suggested.txt` and appended to the filled prompt as a second source, so the model may return one the research does not carry. `check.sh keywords` takes the file as an optional third argument and counts it as grounding, so a term you asked for is not reported as invented while a term in neither still fails.
- `prompts/keywords.md` is untouched, and the guidance is appended to the filled prompt exactly as the content type is, so a page with no suggestions produces a byte-identical prompt. Verified by `cmp` against the pre-change script.

### Phase 38: The launch fills in a new page's inputs (done 2026-09-21)
- Files: `scripts/seo.sh`, `README.md`.
- `./seo` asks whether the page is already live, then which page it is, then for whatever is missing: the live URL or your site's URL, the keyword export paths (copied into `inputs/`), and the competitor URLs. A page that already has them is asked nothing, and every question takes a blank answer.
- An export path that is not readable is refused by name and asked again, rather than skipped quietly, per the honest-checks rule in AGENTS.md.

### Phase 39: The tracked docs describe the launcher, the intake and the suggestions (done 2026-09-21)
- Files: `README.md`, `INSTRUCTIONS.md`, `PLAN.md`, two skill files.
- Every stale claim found while reading was corrected, including "the four commands" in the quickstart and "Phase 11 adds those keys" in two files when the merge already writes them.

### Phase 40: Any size of keyword export parses, and the list is capped (done 2026-09-21)
- Files: `scripts/research_collect.sh`, `scripts/check.sh`, `README.md`, `INSTRUCTIONS.md`.
- The parsed export travels to `jq` through a file, not an argument: Linux caps one argv string at 128 KB whatever `ARG_MAX` says, so a 432 KB export died with "Argument list too long".
- `MAX_KEYWORDS` (150) caps what reaches `research.json`, because 2782 rows would not fit the keyword prompt's 32768-token context. `keywords_total` and `keywords_cutoff` record the cut. An unreadable export exits 4 and writes nothing.

### Phase 41: The brief stages run in one press (done 2026-09-21)
- Files: `scripts/seo.sh`, `README.md`, `INSTRUCTIONS.md`.
- The loop advances only when a stage really lands on disk, so a call that exits 0 without writing stops it rather than repeating.

### Phases 42 to 45: What a full audit of a live run found (done 2026-09-21)
- Files: `scripts/research_collect.sh`, `scripts/check.sh`, `scripts/seo.sh`, `README.md`.
- Competitor page furniture ("About", "Help", "One Comment") is dropped at collect time, because those headings sit in the haystack `check.sh stage` traces sections against. Measured: 6 of 16 headings on one run.
- A rationale claiming "the highest volume" about the chosen term is checked against the figures and FAILs when false. A live run justified a 600-volume term that way while the file held one at 3400.
- An empty `facts` list against a picks-shaped heading WARNs at the brief and the outline, because that combination produced three subsections naming no product.
- The review stage says the fact checker had nothing to compare against instead of reporting a clean pass.

### Phases 46 to 50: Rewrite and draft integrity (done 2026-09-21)
- Files: `scripts/check.sh`, `scripts/lib_parts.sh`, `scripts/brief_stages.sh`, `prompts/rewrite.md`, `README.md`, `INSTRUCTIONS.md`.
- The rewrite may not use a keyword more often than the draft did: a live pass had taken the primary from 5 uses to 9.
- `check.sh targets` grounds the brands a call to action names against the research, run inline by `brief_stages.sh`.
- `draft_factor` fell from 135 to 120 after two runs measured the rewrite cutting 13% and 17.5%, not the assumed 20 to 35%, and a part over 140% of its budget now fails and regenerates.
- A number absent from the facts and the outline FAILs the draft instead of warning. "Less than 30 decibels" had shipped through draft, rewrite and review.
- **The rewrite prompt no longer receives the keyword list.** Measured across seeds: with it, 3 of 3 added keyword uses to one section; without it, 0 of 3, and the article landed inside its word band for the first time.

### Phase 51: The skills state what Claude Code has to judge (done 2026-09-21)
- Files: the `seo-keywords`, `seo-brief` and `seo-draft` skills, `README.md`.
- Written after design principle 3 was set: a rule arithmetic can settle belongs in `check.sh`, a judgement that needs reading belongs to the auditor. Each skill now names its own.

### Phases 52 to 54: The pipeline asks instead of expecting a hand edit (done 2026-09-21)
- Files: `scripts/seo.sh`, `scripts/brief_stages.sh`, `README.md`, `INSTRUCTIONS.md`.
- The facts a page may state are typed at the menu into the file `/seo-ingest` writes, so a document is no longer the only way to supply them. Fixing that exposed that `brief_stages.sh` never passed `--source`, so the facts stage had always failed when a source existed.
- The word count is offered at the merge with the competitor median as its default, and a page recording no facts is asked whether it recommends products.
- The keyword choice is confirmed at the menu: accept, swap for another researched term, or reseed, with the swap re-running the same check.

### Phase 55: guide and roundup join review as content types (done 2026-09-21)
- Files: four new `prompts/*-type-{guide,roundup}.md`, `scripts/seo.sh`, `README.md`, `INSTRUCTIONS.md`.
- Both were already in the `content_type` enums; only the prompt files were missing. `guide` produced criteria sections and no picks heading; `roundup` produced a picks spine whose purposes instruct the author to name the products.

### Phases 56 and 57: Redoing work without editing files (done 2026-09-22)
- Files: `scripts/draft_sections.sh`, `scripts/seo.sh`, `scripts/brief_stages.sh`, `README.md`, `INSTRUCTIONS.md`.
- `p` redoes one drafted part at a fresh seed (`DRAFT_SEED`), leaving the rest alone. Found and fixed while testing: the staleness test discarded every part when a part and the outline shared a timestamp to the second.
- `e` changes a recorded answer, says what it invalidates, and clears what was built on it. Changing the content type clears the brief stages, which `brief_stages.sh` requires.

### Phase 58: A keyword's market is part of its identity (done 2026-09-22)
- Files: `scripts/research_collect.sh`, `scripts/check.sh`, `README.md`.
- `Country` is read and rows merge by keyword and market, so a Canadian and a US export of one term stay two rows. Merged on the keyword alone, one volume silently won, and the keyword prompt's Case B is entirely a comparison of volumes.

### Phase 59: A field cut off by its schema cap is reported (done 2026-09-22)
- Files: `scripts/check.sh`, `scripts/brief_stages.sh`, `README.md`.
- A `maxLength` truncates rather than rejects. `check.sh truncated` walks a schema for capped strings and FAILs on a value sitting exactly on its cap. It caught the live `keywords.json` rationale at exactly 500 characters.

### Phase 60: The content type reaches the intent stage (done 2026-09-22)
- Files: `scripts/brief_stages.sh`, the three `brief-type-*.md`, `README.md`.
- A guide-typed brief had come out titled "Best Cat Water Fountains: Top Picks" over criteria sections, because only the structure stage knew the type. Each type now states what its `topic` may promise.

### Phases 61 to 65: What three measured runs changed (done 2026-09-22)
- Files: `scripts/seo.sh`, `scripts/check.sh`, `scripts/lib_parts.sh`, `scripts/research_collect.sh`, `prompts/*`, `README.md`, `INSTRUCTIONS.md`.
- A stage whose input is strictly newer than its artifact reads `stale`, not `done`: a brief rebuilt in the morning had left an outline and a final from the night before sitting at `done`, and the review stage reported a superseded article's lengths.
- Three runs of the same brief at different seeds produced the evidence for the rest: a costs section with no cost data invented prices 3 times out of 3, the flat keyword cap of 2 warned on every run of a correct article, and the absolute-wording check flagged maintenance instructions every time.
- 62: no section may be about a figure the research cannot supply. 63: the keyword cap is `word_count / 250`, floor 2. 64: temporal "every week" and imperative instructions are not overclaims.
- 65 was reverted: giving the part prompts an explicit word range instead of a percentage left parts at 127% and 139% of budget and made the finished articles longer. Recorded as a failure with its numbers.

### Phases 66 to 68: Sizing, naming, and accepting figures (done 2026-09-22)
- Files: `scripts/brief_stages.sh`, `scripts/fill_prompt.sh`, `scripts/check.sh`, `scripts/seo.sh`, `scripts/lib_parts.sh`, `prompts/brief-structure.md`, `README.md`, `INSTRUCTIONS.md`.
- The structure stage receives the target length and a section ceiling, and `fill_prompt.sh` derives the same band for the outline from the brief's `word_count`. A brief that produced 9 topic sections against a 3-5 table produced 5. Telling the outline prompt to "group subtopics" had been tried first and measured worse.
- `proper_noun_keywords` no longer reads the brief's `topic`: a Title Case title made every ordinary word look like a lowercased brand and fired on 4 of 5 keywords.
- `n` at the menu lists every figure the facts do not support, in its sentence, and takes the ones the author vouches for into the facts source before redoing the facts stage and the merge. A procedural page cannot pass its own number check without this, by construction.

### Phases 69 to 73: The word count, the types, and the furniture (done 2026-09-22)
- Files: `scripts/fetch_page.sh`, `scripts/brief_stages.sh`, `scripts/research_collect.sh`, `scripts/check.sh`, `prompts/*-type-how-to.md`, `prompts/brief.schema.json`, `README.md`.
- `fetch_page.sh` strips whole regions (script, style, nav, header, footer, aside, form, svg, template, comments) before counting, because `sed` cannot match non-greedily and a Shopify page with its catalogue inlined measured 60,273 words. The four collected competitors went from 17969, 60273, 1700 and 2277 words to 1725, 1505, 997 and 1318.
- `target_words()` excludes counts outside 150 to 8000 before taking the median and says what it ignored, so the 600-to-3000 clamp can no longer turn a 39,121-word median into a confident 3000.
- `how-to` joins review, roundup and guide, and every brief stage now reads the type, so the call to action and the facts question are shaped by what kind of page it is.

### Phase 75: A heading wrapped in a span is still a heading (done 2026-09-22)
- Files: `scripts/fetch_page.sh`, `README.md`.
- The heading pattern allowed nested opening tags but not closing ones, so `<h2><span>Title</span></h2>` matched nothing. On a cached competitor it extracted 8 headings where the page has 31.
- Consequence for everything upstream of the brief: `must_cover`, `gaps`, the intent read and the grounding haystack `check.sh stage` traces against had all been working from about a quarter of the competitors' structure. Both briefs were rebuilt on the corrected research: the cleaning page's sections now trace to competitor H3s with none resting on the page purpose, and the fountain page's `must_cover` went from one competitor's table of contents to six buying criteria.
- Three schema caps were raised on evidence from `check.sh truncated` while rebuilding: `gaps` 200 to 400, `cta` 120 to 200, `cta_reason` 300 to 500.

### Phases 76 to 82: What a /verify run of phases 36 to 75 found (done 2026-09-22)
- Files: `scripts/seo.sh`, `scripts/brief_stages.sh`, `scripts/research_collect.sh`, `scripts/fetch_page.sh`, `scripts/check.sh`, `prompts/brief-stage.schema.json`, `README.md`, `.claude/skills/verify/SKILL.md`.
- 76: `e` deleted the recorded answer before re-asking, so an invalid new answer lost the old one. It now restores it.
- 77: `check.sh truncated` ran after a stage was already written and could not stop it, and a cut `target_audience` reached a merged brief that passed `check.sh brief`. A cut reply is now retried at the next seed like an unusable one, and the stage exits 3 when both seeds are cut. `target_audience` went from 200 to 300.
- 78: Phase 75 made retail catalogues visible, and product tiles such as `PetSafe® Viva ... 1.8L/64 oz` entered the grounding haystack. A heading with a trademark or pack size is a tile, and a page with at least half tiles keeps only its H1. PetSmart went from 42 headings to 1, and the 35 editorial headings were all kept.
- 79: the fetch cache defaulted to the repo's `research/_cache` even under a scratch `RESEARCH_DIR`. It now follows `RESEARCH_DIR`.
- 80: titles, descriptions and headings kept HTML entities, so `&` never matched `&amp;` in a grounding check. The entities seen in live research are decoded. `&ndash;` was missed by the audit and is deferred.
- 81: a piped `./seo` with an invalid slug rendered a menu and exited 0. The slug is now checked first.
- 82: staleness was pairwise, so after a brief change the draft and final still read `done`. It now runs down the chain, and `a` stops at a stale stage you declined to replace, because otherwise it rebuilt every later stage from the one you kept.
- Closing the work: both slugs were re-collected from the cache. The fountain page lost 41 PetSmart tiles, the how-to page only had entities decoded, and neither brief traced to anything removed, so neither was rebuilt. The fountain page's `30 60` decibel FAIL was an unsourced "below 30 dB is recommended". It was closed by redoing that one part with `p` rather than accepting the figures with `n`, and the redone part states no figures.

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
