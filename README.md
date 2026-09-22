# SEO LLM CLI

Local-first SEO content pipeline driven by **Claude Code** (CC) as the runtime and a **llama.cpp router** on `localhost:8080` as the local model server. No standalone Python app. CC's skills, prompts, and Bash tool sequence the work, and a single shell helper posts to the router's OpenAI-compatible chat endpoint.

## Design at a glance

```
./seo                                        (the front door: intake, then the menu)
  └─ scripts/seo.sh: stage state from disk, runs the stage you pick

User in Claude Code
  ├─ /seo-research <slug>                    (Phases 6-7 - research, no model call)
  │    ├─ scripts/fetch_page.sh        -> research/<slug>/page.json
  │    └─ scripts/research_collect.sh  -> research/<slug>/research.json
  │         from inputs/*.csv (your exports) + competitors.txt (URLs you list)
  ├─ /seo-keywords <slug>                    (Phase 8 - what does this page target?)
  │    └─ scripts/llm_call.sh prompts/keywords.md (schema-constrained)
  │         └─ writes research/<slug>/keywords.json
  ├─ /seo-brief    <slug>                    (Phases 9-10 - brief in approved stages)
  │    └─ scripts/brief_stages.sh: one call per stage, you approve each
  │         intent -> structure -> targets -> facts, then --merge
  │         └─ writes briefs/<slug>.json
  ├─ /seo-ingest  <doc.docx|doc.pdf|doc.md>  (Phase 3 — optional: doc → JSON brief)
  │    └─ pandoc / pdftotext → scripts/llm_call.sh prompts/ingest.md → writes briefs/<slug>.json
  ├─ /seo-outline briefs/<brief>.json        (Phase 2 — outline first)
  │    └─ scripts/llm_call.sh prompts/outline.md
  │         └─ writes outputs/<slug>/outline.md
  ├─ /seo-draft   briefs/<brief>.json        (Phase 4 — draft section by section)
  │    └─ scripts/draft_sections.sh: one scripts/llm_call.sh call per part, then a fact-check call
  │         prompts/intro.md, prompts/section.md (each H2 + FAQ), prompts/conclusion.md, prompts/verify.md
  │         └─ writes outputs/<slug>/sections/*.md, stitched into draft.md
  └─ /seo-rewrite briefs/<brief>.json        (Phase 5 — edit for readability)
       └─ scripts/rewrite_sections.sh: one call per part, prompts/rewrite.md, then a fact-check call
            └─ writes outputs/<slug>/rewrite/*.md, stitched into final.md

Every scripts/llm_call.sh call → POST localhost:8080/v1/chat/completions
  model qwen, system message prompts/system.md, thinking off
```

Phases 1 to 13 and 16 to 38 are built, so a page goes from research to a finished article, and `./seo` walks a new page through its inputs first. Later phases add metadata and keywords (`meta.json`), a single `/seo-generate` command, and an SEO knowledge base. See [PLAN.md](PLAN.md) for the full phase breakdown, and [INSTRUCTIONS.md](INSTRUCTIONS.md) for a step-by-step walk through every stage.

### Why this shape
- **CC is the harness.** Skills replace a CLI, the Bash tool replaces a workflow engine, and files replace a database.
- **llama.cpp over HTTP.** One thin shell wrapper (`scripts/llm_call.sh`), no client library. The router's models carry no built-in system prompt, so the wrapper sends `prompts/system.md` on every call.
- **Section-based, multi-pass.** Long articles are never produced in a single call, and drafts get a separate rewrite pass.
- **Deterministic.** Per-stage temperature and seed, with no autonomous loops in MVP.

## Repository layout

```
SEO-LLM/
├── seo                 # the launcher: ./seo [slug], asks which page, then shows the menu
├── .claude/
│   ├── skills/         # one directory per slash command, each holding SKILL.md
│   └── settings.json   # Bash allow-list: the entry scripts, the router model check, jq, doc extractors
├── prompts/            # markdown prompt templates with {{PLACEHOLDERS}}, plus system.md (sent on every call)
│                       # keywords-type-<type>.md and keywords-suggested.md are appended to a filled prompt, never templated into it
├── scripts/
│   ├── seo.sh          # interactive menu: stage status from disk, runs the stage you pick
│   ├── fetch_page.sh   # polite fetch: robots.txt, per-host delay, cache, extraction (--raw for non-HTML)
│   ├── fetch_sitemap.sh # sitemap.xml (and sitemap indexes) → research/_sitemaps/<host>.txt
│   ├── research_collect.sh # exports + competitor pages → research/<slug>/research.json
│   ├── brief_stages.sh # one model call per brief stage, then the merge into briefs/<slug>.json
│   ├── llm_call.sh     # curl wrapper: prompt-file + prompts/system.md → reply on stdout
│   ├── fill_prompt.sh  # fills a template's {{PLACEHOLDERS}} from a brief, outline, or source text
│   ├── draft_sections.sh # section-by-section drafting loop: split, budget, call, verify, check, retry, stitch
│   ├── rewrite_sections.sh # per-part readability edit with guards and re-verification, stitched into final.md
│   ├── lib_parts.sh      # shared helpers: fact verification, heading restore, unbold, outline repair, draft_factor
│   └── check.sh        # deterministic checks on a brief, outline, or draft (FAIL/WARN lines)
├── research/           # per-page research: <slug>/page.json, inputs/, _cache/ (cache gitignored)
├── briefs/             # user inputs (JSON)
├── outputs/            # generated articles, one directory per brief (gitignored)
├── AGENTS.md           # workflow contract for any AI agent in this repo
├── INSTRUCTIONS.md     # stage-by-stage walk through the whole pipeline
├── PLAN.md             # architecture + phased MVP plan
├── README.md
└── SEO-GUIDE.md        # the SEO reference behind the pipeline: fundamentals, intermediate practice, glossary
```

## Prerequisites

- **llama.cpp router** on `http://localhost:8080` serving the model `qwen`. It runs as the `llama-server` systemd user service, configured and deployed from `~/Apps/Local-LLM` (see that repo's README, "Serving other apps"). This repo only calls it.
  - The router keeps one model loaded at a time and puts it to sleep after 10 idle minutes, so the first call after another model was in use waits for `qwen` to load.
  - Context is fixed per model by the router's preset, not per request, and the presets live in Local-LLM, so the number can change under this repo. Read the current value with `curl -s localhost:8080/models | jq -r '.data[] | "\(.id): " + (.status.args | index("--ctx-size") as $i | .[$i+1])'`. The wrapper requires at least 32768 and refuses to run below that (see below). A prompt longer than the served context returns HTTP 400 instead of being truncated.
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
2. Start a page from the terminal:
   ```bash
   # Runs in: local terminal
   ./seo
   ```
   It asks whether the page is live, which page it is, and then for the inputs it
   is missing, and opens the menu. That is the whole pipeline, and the rest of
   this section is the same work driven from Claude Code instead.
3. Open this repo in Claude Code and accept the trust dialog on first run.
   Confirm the commands are available by typing `/` and looking for
   `seo-research`, `seo-keywords`, `seo-brief`, `seo-ingest`, `seo-outline`,
   `seo-draft`, and `seo-rewrite`.
4. Get a brief into `briefs/`, either way:
   - **From a JSON brief you write.** Copy [briefs/example.json](briefs/example.json) and edit it.
   - **From a document.** Run `/seo-ingest path/to/source.{docx,pdf,md,txt}`, which writes `briefs/<slug>.json` for you to review and edit.
5. In Claude Code, run the outline first, then the draft:
   ```
   /seo-outline briefs/example.json
   /seo-draft   briefs/example.json
   ```
   The draft needs the outline, so running `/seo-draft` first stops with a message.
   Then polish it with `/seo-rewrite briefs/example.json`.
6. Inspect `outputs/<slug>/outline.md`, `outputs/<slug>/draft.md`, and `outputs/<slug>/final.md`.

## The menu

`./seo` is the interactive front door. With no slug it asks which page you mean,
then shows every stage of that page with its state and runs the one you pick. It
is a wrapper around `scripts/seo.sh`, which can still be called directly, and it
finds the repository from its own path, so it works from any directory.

```bash
# Runs in: local terminal
./seo                 # lists the pages that have research, or starts one
./seo example-domains # straight to that page

# End the pipeline at the brief, for when you write the page yourself.
SEO_BRIEF_ONLY=1 ./seo example-domains
```

`SEO_BRIEF_ONLY=1` hides the outline, draft and rewrite stages, so the menu is
the five that produce a brief and `a` stops once the brief is written. The
hidden stages still work and their files are left untouched, so unsetting the
variable brings them back exactly as they were.

```
SEO pipeline: example-domains
router: serving qwen

  1 [done   ] Page check         live page, title 62 chars, 268 words, no description
  2 [done   ] Collect research   4 keywords, 2/2 competitors, 2 exports
  3 [ready  ] Keyword choice       <- next
  4 [blocked] Brief stages       needs keywords.json
  5 [blocked] Write the brief    needs all 4 brief stages
  6 [blocked] Outline            needs the brief
  7 [blocked] Draft              needs the outline
  8 [blocked] Rewrite            needs the draft
  9 [blocked] Review             needs final.md

  a run all ready stages   s switch page   q quit
```

- **A new page is walked through its inputs before the menu opens.** `./seo`
  asks whether the page is already live, then which page it is, and then for
  whatever is missing on disk: the live page's URL, or your site's URL when it is
  not live yet, then the keyword exports (paths, one per line, copied into
  `inputs/`) and the competitor URLs (one per line, written to
  `competitors.txt`). An export path that is not there is refused by name and
  asked again rather than skipped quietly, and every question takes a blank
  answer, which leaves the file for you to place by hand. A page that already has
  these is asked nothing, so resuming is unchanged.
- **State comes from the files on disk**, never from a session file, so resuming
  a page you left last month works exactly like resuming one from five minutes
  ago. A stage is `done` when its artifact exists, `ready` when its input does,
  and `blocked` with the reason otherwise.
- **A failing stage returns you to the menu** with the error visible. The menu
  never swallows an exit code, and it prints the `check.sh` verdict for whatever
  it ran.
- **Every model stage checks the router first** and refuses to call when `qwen`
  is not served, so a stage fails before it spends time rather than after.
- **The purpose is asked once per page** and saved to
  `research/<slug>/brief-stages/purpose.txt`, so the keyword choice and all four
  brief stages work from the same sentence.
- **The content type is asked once per page**, before the keyword choice, and
  saved to `research/<slug>/type.txt`. Answering `review` shapes the keyword
  choice and the brief's sections. Pressing enter records an empty answer, which
  keeps the generic behaviour and stops the question being asked again.
- **Your own keyword suggestions are asked for once per page**, after the
  competitor research and before the keyword choice, and saved to
  `research/<slug>/suggested.txt`, one per line. The model may return a
  suggested term even though the research does not carry it, and `check.sh`
  counts the list as grounding, so the term is not reported as invented. They
  are candidates, not a shortlist: the model still chooses on demand and fit and
  will prefer a research term when it fits better. Pressing enter straight away
  records none, which leaves the prompt exactly as it was.
- **A failed check offers a reseed rather than retrying silently.** The keyword
  stage offers seed 2, the outline stage offers seeds 2 and 3, and each one says
  what to do when the retries are exhausted.
- **Replacing an artifact always asks**, and replacing a brief says plainly that
  your edits go with it.
- **One press runs every remaining brief stage.** Choosing the brief stages runs
  intent, structure, targets and facts in order, announcing each as it lands, and
  stops once with all four written and a line on what to check in each. A stage
  that fails stops the loop there and the earlier stages are kept, and a stage
  that returns without writing a file stops it too rather than calling the model
  again on the same stage. `bash scripts/brief_stages.sh <slug> --redo <stage>`
  still rebuilds one stage and everything after it.
- **`a` runs every ready stage in turn.** It stops before a stage that needs you
  to type or place something (the page check and the research collection), stops
  after each brief stage so you read it, and stops at the first failure. From a
  finished brief it will take you to `final.md` in one keypress.
- **The review stage** lists the claims the fact checker flagged but could not
  safely fix, which are still in the article, alongside the brief target and the
  draft and final word counts.
- `RESEARCH_DIR`, `BRIEFS_DIR` and `OUTPUTS_DIR` relocate the whole tree, which
  is how a test run stays out of the real directories. `draft_sections.sh` and
  `rewrite_sections.sh` read `OUTPUTS_DIR` too, so a whole run can land in a
  scratch directory. Set it for one stage and not the next and the next stage
  says plainly that it cannot find the previous stage's files.
- It needs a terminal. Piped or redirected, it prints the status table once and
  exits, so it is safe in a script that just wants the state.

## The research stage

`/seo-research <slug>` is the first stage, and it makes no model call. It asks
whether the page already exists. Answer with a URL and it snapshots the live
page, answer no and it records that this is a new page.

```bash
# Runs in: local terminal
bash scripts/fetch_page.sh https://example.com/about research/about/page.json
bash scripts/fetch_page.sh --absent research/new-service/page.json
```

`scripts/fetch_page.sh <url> [out.json]` writes the page's SEO surface as JSON:
`title`, `meta_description`, `word_count`, and `headings` as a list of H1 to H3
with their levels. With no output path it prints to stdout, so it can be piped.

- **It obeys `robots.txt`** for the User-Agent it sends, using the standard
  longest-match rule, and exits 3 rather than fetching a disallowed path. A
  missing `robots.txt` means allow, as the standard says.
- **It waits between requests to one host**, at least `FETCH_DELAY` seconds
  (default 2) and longer when `robots.txt` asks for more.
- **It caches the raw HTML** under `research/_cache/` for `FETCH_CACHE_TTL`
  seconds (default 86400), so reruns and competitor collection do not re-hit a
  site. That directory is gitignored.
- **`FETCH_UA` sets the User-Agent**, which defaults to `SEO-LLM/1.0` with no
  contact address. Set it to something with a contact if you fetch at volume.
- **`FETCH_TIMEOUT`** (default 20 seconds) caps each request.
- Exit codes: 1 the URL is not http or https, 2 the output cannot be written,
  3 `robots.txt` disallows it, 4 an HTTP error status, 5 the response is not
  HTML, 7 the host is unreachable. A page with no meta description or no H1 is
  not an error, and those fields come back empty.

### Collecting the research

`scripts/research_collect.sh <slug> [--fresh]` turns what you gathered into one
`research/<slug>/research.json`. It needs `page.json` and exits 2 without it.

The three inputs below are what the launch intake asks for, so on a new page you
can type their paths and URLs instead of placing them yourself. Placing them by
hand works exactly the same, and is how you add to a page later.

- **Keyword exports** go in `research/<slug>/inputs/` as CSV or TSV. The source
  this pipeline is built around is the **Search Console Performance export**
  (`Top queries`, `Clicks`, `Impressions`, `CTR`, `Position`), because those
  numbers are measured rather than modelled. Columns are read by name, so any
  other export works as downloaded too: a file carrying `Volume`, `Difficulty`,
  `Traffic potential`, `CPC` or `Parent topic` still parses, and those fields
  are recorded if you have them. Quoted fields containing commas are handled, a tab-separated file
  named `.csv` is detected, and `%` and thousands separators are stripped from
  numbers. Rows are merged by keyword, and each keyword lists the files it came
  from. An export with no recognizable keyword column exits 3 and prints the
  columns it saw rather than writing empty rows.
- **The keyword list is capped at 150** (`MAX_KEYWORDS`, and `0` keeps every row),
  taken from the head of the volume sort. A full Ahrefs "matching terms" export is
  thousands of rows and several hundred KB, which is far past the 32768-token
  context the keyword prompt has to fit in. `research.json` records
  `keywords_total` and a `keywords_cutoff` object naming how many were kept and
  dropped and the volume the cut landed on, and `check.sh research` WARNs about it,
  so nobody reads the list as the whole file. Measured on a real export:
  2782 rows in, the top 150 kept at volume 10 and above, `research.json` 31 KB.
- **An export that cannot be read stops the run** (exit 4), names the file, and
  writes nothing, rather than leaving a `research.json` with no keywords in it that
  looks like a topic with no data. An export with no keyword column still exits 3
  and prints the columns it saw.
- **Competitors** go in `research/<slug>/competitors.txt`, one URL per line with
  `#` comments allowed. Each is fetched through `fetch_page.sh`, so robots.txt,
  the delay and the cache all apply. One that cannot be fetched is recorded with
  its reason and does not stop the others.
- **Your sitemap becomes a page inventory.** When the page is live, or when you
  put your site's URL in `research/<slug>/site.txt`, the collection fetches
  `sitemap.xml` once per site (reading `robots.txt` for its real location, and
  following a sitemap index one level) into `research/_sitemaps/<host>.txt`. It
  is reused by every later page on that site. `research.json` then carries
  `site_pages`: the URL count, and the pages of yours whose path already
  contains every significant word of a researched query. That list is the
  cannibalization check, and those URLs are your internal link candidates.
- `check.sh research` FAILs only on a broken shape. Thin research (no exports, no
  competitors, fewer than the 3 to 5 pages SEO-GUIDE.md asks for) is a WARN,
  because a topic with no tool data is a real case.

Search engine results pages are never fetched, and no search or SEO-tool API is
called. Data enters the pipeline only as files you export, plus the competitor
pages you name.

### Choosing the target keyword

`/seo-keywords <slug>` makes one schema-constrained call (temperature 0.2, seed 1)
against `research.json` plus a one-line description of what the page is for, and
writes `research/<slug>/keywords.json`: the primary keyword, 2 to 6 secondary
keywords, the intent (type, format, angle), a business-potential score of 0 to 3,
the questions the ranking pages answer, and the subtopics they share.

The guard that matters is grounding. `check.sh keywords` FAILs when any keyword
returned is absent from the research file, comparing against the keyword table,
the competitor titles and headings, the existing page, and the keywords you
suggested at the menu when there are any. A reworded keyword fails the same way
an invented one does, because "checklist for technical seo" is a different query
from "technical seo checklist". The prompt also forbids restating the research
figures, so volumes and difficulties stay in `research.json` where they can be
audited, and a repeated figure is a WARN.

The word-count target is not set here. It comes from the competitor word counts
at the brief stage.

### Building the brief in stages

`/seo-brief <slug>` runs `scripts/brief_stages.sh`, which makes **one call per
stage** and stops after each so you can correct it before the next runs:

| Stage | Produces | Reads |
| --- | --- | --- |
| 1 intent | topic, audience, reader goal, tone with its reason | research, keyword choice, your one-line purpose |
| 2 structure | sections with their source, FAQ questions, gaps in the ranking pages | stage 1 plus the research |
| 3 targets | the brief's keywords and the call to action | stages 1 to 2 plus the keyword choice |
| 4 facts | the business specifics the article may state, and what was left out | stages 1 to 3 plus `briefs/_ingest/<slug>.txt` |

The purpose is recorded once in `brief-stages/purpose.txt` and reused, so a later
stage cannot drift onto a different page. The content type in `type.txt` works
the same way and is refused if it changes, because a brief half-shaped as a
review and half as an article is worse than either. Every stage sees the approved ones, so
an edit you make to stage 1 changes what stage 2 produces. `--redo <stage>` drops
that stage and every stage after it, because the later ones were built on the
version being replaced.

Two deliberate choices in the merge:

- **`word_count` is computed, not generated.** It is the median of the competitor
  word counts actually fetched, rounded to 50 and clamped to 600 to 3000, or 1000
  when no competitor page was fetched. A number the research already implies
  should be auditable rather than sampled.
- **Facts come only from your source document.** With no `briefs/_ingest/<slug>.txt`
  the facts list is written empty and no call is made, because a page with no
  source has no business specifics to state. The prompt keeps every qualifier
  ("most orders", "from $450") and pushes design notes and marketing adjectives
  into an `omitted` list with the reason, so you can put anything back.

```bash
# Runs in: local terminal
bash scripts/brief_stages.sh about --purpose "An about page for a Hamilton web studio"
bash scripts/brief_stages.sh about            # each later stage
bash scripts/brief_stages.sh about --merge    # writes briefs/about.json and checks it
```

The merge carries the research forward: `search_intent` comes from the keyword
choice, `must_cover` from the structure stage's headings, `questions` from its
FAQ list, and `existing_page` from the research when the page is live
(`scripts/brief_stages.sh:237-243`). The stage files stay on disk as the record
of what was approved.

## The model wrapper

`scripts/llm_call.sh <prompt-file> [temperature] [seed] [schema-file]`

Posts a non-streaming request to `/v1/chat/completions` and prints `.choices[0].message.content` to stdout. That's the entire model-runtime surface.

- The system message is always `prompts/system.md`, and the prompt file is the user message.
- Temperature defaults to 0.7 and seed to 0. `top_p`, `top_k`, `min_p`, `presence_penalty`, and `repeat_penalty` are pinned in the script and sent on every call.
- Thinking is off (`chat_template_kwargs: {"enable_thinking": false}`).
- With a schema file (a JSON object, as in [prompts/brief.schema.json](prompts/brief.schema.json)), the reply is constrained to that schema via `response_format`. `/seo-ingest` uses this. Without it the payload is unchanged.
- `LLM_HOST` (default `http://localhost:8080`) and `LLM_MODEL` (default `qwen`) override the target. The router also serves `gemma` and `lite`.
- `LLM_MAX_TOKENS` caps the reply and `LLM_TIMEOUT` (seconds) caps the request. Both are unset by default. The verifier sets them because a schema-constrained reply once ran for over ten minutes.
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
  "cta": "Book a consultation",
  "facts": ["Clinic opened in 2012", "New-patient exams are free"]
}
```

Four optional keys carry the research forward when `/seo-brief` wrote the brief:

```json
{
  "search_intent": {"type": "blog post", "format": "how-to guide", "angle": "comprehensive optimization steps"},
  "must_cover": ["Getting indexed", "Increasing prominence"],
  "questions": ["how long does seo take to work?"],
  "existing_page": {"url": "https://example.com/seo", "title": "Old page", "word_count": 400}
}
```

`/seo-outline` uses them: it covers every `must_cover` subtopic, takes the FAQ
from `questions` when there are any, and matches the researched intent's format.
A brief without them behaves exactly as before, so hand-written briefs and
`/seo-ingest` output stay valid. `check.sh brief` accepts a brief with or without
them and rejects an unknown key, which catches a typo such as `mustcover`.

All seven required keys are still required. `facts` lists the business specifics (names, prices, policies, timelines) the outline and draft may state, and the prompts forbid inventing any others. It may be empty for a generic topic and holds at most 40 entries. `tone` is one of `Professional`, `Authoritative`, `Conversational`, `Friendly`, or `Technical`, `word_count` is a whole number, and `keywords` holds 3 to 6 entries. [prompts/brief.schema.json](prompts/brief.schema.json) states the same rules for the router, and `/seo-ingest` checks a generated brief against them with `jq`.

`scripts/fill_prompt.sh` substitutes these into the templates' placeholders (`{{TOPIC}}`, `{{BRIEF}}`, `{{TONE}}`, `{{AUDIENCE}}`, `{{KEYWORDS}}`, `{{WORD_COUNT}}`, `{{CTA}}`, `{{FACTS}}`, plus `{{SEARCH_INTENT}}`, `{{MUST_COVER}}`, `{{QUESTIONS}}`, `{{EXISTING_PAGE}}`, `{{OUTLINE}}` and `{{SOURCE_TEXT}}`) and exits 1 if a template placeholder is left unfilled. The four research placeholders fill with a stated value such as `(none researched)` when the brief does not carry them, so one prompt serves both brief shapes.

The outline is repaired before it is checked. `clean_outline` in
[scripts/lib_parts.sh](scripts/lib_parts.sh) keeps headings, blank lines, and
one `_Intent:` and one `Keywords:` line directly under each H2, and drops
everything else, printing every line it removed. The model repeatedly puts those
guidance lines under the H1 or under H3s, or writes a paragraph under a heading,
and three prompt wordings were measured against it without success, so the fix
is deterministic rather than verbal. A valid outline comes back byte-identical,
and an outline missing something real still fails its check.

`word_count` also sizes the outline: up to 1000 words gets 2 to 3 topic sections, up to 1800 gets 3 to 5, and longer gets 4 to 6 (the table in [prompts/outline.md](prompts/outline.md), mirrored in `scripts/check.sh`).

## Section-by-section drafting

`/seo-draft` runs `scripts/draft_sections.sh <brief.json>`, which turns the outline into parts and drafts each with its own call:

- **Parts.** `00-intro` (no heading, since the H1 is added at stitch time), then one part per H2 in outline order. The FAQ uses `prompts/section.md`, and the Conclusion uses `prompts/conclusion.md`, which ends on the brief's CTA.
- **Budget.** The draft aims at 135% of `word_count` because the rewrite pass and its re-verification cut 20 to 35% (`DRAFT_FACTOR` overrides). A lower factor for short pages left a thin-facts page 28% short, so the factor is the same at every length. A page that keeps some drafted text can overshoot, which only warns. Of that total: intro about 8%, conclusion about 6%, FAQ 60 words per question (at most 20%), and the rest split across topic sections by their H3 count. Each prompt asks for 90 to 110% of its budget.
- **Keywords.** Each primary keyword keeps its cue in only the first two parts that list it (the intro counts as one use of the first keyword), and the FAQ gets none, because the model stuffs cues into its questions.
- **Repairs.** After each call the script puts the outline's heading wording back when the heading structure matches, and strips bold. Then `check.sh section` runs. A failure is retried once with seed 2, and a second failure is saved as `.ERROR.md` and stops the run.
- **Fact verification.** Each passing part gets a second call (`prompts/verify.md`, schema-constrained, temperature 0.1) that lists sentences the facts do not support, typed `invented`, `strengthened`, or `contradiction`, each with a replacement. The script applies replacements as literal swaps and rejects any that is not found verbatim, touches the CTA sentence, brings in words absent from the sentence and the facts (compared by first four letters), or, for `strengthened`, drops over half the sentence. Everything is logged in `sections/NN-<heading>.verify.json`. The original text stays in `.unverified.md`, and is restored if the verified part fails its check. Rejected issues remain in the draft for review. `VERIFY_MODEL=gemma` runs the verifier on Gemma instead. On the About test page the two flagged nearly the same sentences at the same speed.
- **Resume.** Rerunning skips parts that exist and pass. Saved parts older than `outline.md` are discarded, as is everything with `--fresh`.

Every part sees the brief's audience, tone, facts, and the outline's headings, so it knows what the other sections cover without repeating them.

## Rewrite pass

`/seo-rewrite` runs `scripts/rewrite_sections.sh <brief.json>` after `/seo-draft`. Each part is edited in order with `prompts/rewrite.md`: fix pasted keyword phrases, cut filler and sentences that repeat earlier parts, vary sentence openings, and fix the verifier's rejected issues for that part, which are passed in. Each call sees the parts already edited.

The edit is checked against its input with `check.sh rewrite`: identical headings, 50 to 120% of the length (cutting filler shortens parts, and growth is where new claims come from), no call to action added to a part that lacked it, no numbers absent from the input and the facts, no more absolute-wording sentences than before, and the CTA sentence kept. A failure is retried with seed 2, and a second failure keeps the drafted part with a WARN, because the rewrite is polish and never blocks the article. Each accepted edit then goes through the same fact verification as the draft (`verify_part` in `scripts/lib_parts.sh`), logged as `rewrite/NN-<heading>.verify.json`, because an edit can reword a claim into one the facts do not support. `REWRITE_MODEL=gemma` switches the model.

## Checks

`scripts/check.sh` holds every structural rule, and each skill runs it after its model call:

| Mode | FAIL (regenerate or fix) | WARN (look at it) |
| --- | --- | --- |
| `brief <brief.json> [source.txt]` | schema mismatch | CTA mentions on-page UI, single-word or page-name keywords, empty facts, fact numbers absent from the source |
| `outline <outline.md> <brief.json>` | not exactly one H1, missing FAQ/Conclusion, any body text, an H2 without an Intent line | section or FAQ counts outside the size table, H3s under Conclusion, lowercase keyword pasted into a heading |
| `section <part.md> <block.md or -> <words> <brief.json>` | headings differ from the block (or any heading in the intro), guidance lines or code fence left in, CTA missing from the conclusion | words outside 60 to 125% of the budget, bolded keyword |
| `rewrite <new.md> <old.md> <brief.json>` | headings changed, length outside 50 to 120%, CTA added where there was none, numbers absent from the input and facts, more absolute-wording sentences, CTA sentence lost | bold left in |
| `research <research.json>` | the file does not match the expected shape | no keywords, no volume column anywhere, no competitors, fewer than 3 fetched, a competitor that failed, an existing page with no title or no meta description |
| `keywords <keywords.json> <research.json>` | the file does not match the expected shape, a keyword absent from the research, the primary keyword repeated as a secondary | no questions, fewer than 2 must-cover subtopics, research figures repeated in the reasoning, a live page whose title does not contain the chosen keyword |
| `draft <draft.md> <outline.md> <brief.json> [percent]` (`draft` for `draft.md`) | H1/H2 differ from the outline, outline guidance lines left in | length outside ±15%, CTA missing from Conclusion, a keyword used more than twice, bolded keywords, numbers not in the facts or outline, sentences with absolute wording (all, every, guaranteed…) |

The checks catch structure and invented digits, not invented prose. The skills therefore also ask Claude Code to audit facts against the source (ingest) or the brief's `facts` (draft) and report anything added or strengthened.

## Where files land

The slug is the brief's file name without `.json`, so `briefs/test-brief.json`
writes to `outputs/test-brief/`. `/seo-ingest` derives it from the source file's
basename (`client-notes.pdf` → `briefs/client-notes.json`), so a document, its
brief, and its outputs share one name, and editing a brief's `topic` does not
orphan its outline.

| Path | Written by | What it is |
| --- | --- | --- |
| `research/<slug>/page.json` | `/seo-research` | Whether the page exists, and its title, meta description, headings and word count |
| `research/<slug>/inputs/*.csv` | you or the launch intake | Keyword and query exports, read by column name |
| `research/<slug>/competitors.txt` | you or the launch intake | Competitor URLs, one per line |
| `research/<slug>/site.txt` | you or the launch intake | Your site's URL, when the page is not live yet, so the sitemap can be found |
| `research/_sitemaps/<host>.txt` | `/seo-research` | Your own page inventory from the sitemap, fetched once per site |
| `research/<slug>/research.json` | `/seo-research` | The collected research: merged keywords, competitor pages, the existing page, your matching pages |
| `research/<slug>/_keywords_prompt.txt` | `/seo-keywords` | The filled keyword prompt |
| `research/<slug>/keywords.json` | `/seo-keywords` | The target keyword, intent, business potential, questions and subtopics |
| `research/<slug>/type.txt` | `/seo-keywords` | The content type, recorded once, empty when declined |
| `research/<slug>/suggested.txt` | `/seo-keywords` | Keywords you suggested, one per line, recorded once and empty when you suggested none |
| `research/<slug>/brief-stages/purpose.txt` | `/seo-brief` | The one-line page purpose, recorded once and reused by every stage |
| `research/<slug>/brief-stages/NN-<stage>.json` | `/seo-brief` | One approved brief stage, with its `.prompt.txt`, `.schema.json` and `.prior.json` beside it |
| `research/_cache/*.body` | `/seo-research` | Cached raw HTML and response status, gitignored |
| `briefs/_ingest/<slug>.txt` | `/seo-ingest` | Plain text pulled out of the source document |
| `briefs/_ingest/<slug>.prompt.txt` | `/seo-ingest` | The filled ingest prompt sent to the model |
| `briefs/<slug>.json` | `/seo-ingest` | The brief, for you to review and edit |
| `outputs/<slug>/_outline_prompt.txt` | `/seo-outline` | The filled outline prompt |
| `outputs/<slug>/outline.md` | `/seo-outline` | The outline, consumed by `/seo-draft` |
| `outputs/<slug>/sections/NN-<heading>.block.md` | `/seo-draft` | One outline block per H2, keyword cues de-duplicated |
| `outputs/<slug>/sections/NN-<heading>.prompt.txt` | `/seo-draft` | The filled prompt for that part (`00-intro` has no block) |
| `outputs/<slug>/sections/NN-<heading>.md` | `/seo-draft` | The drafted part after verification, or `.ERROR.md` when it failed twice |
| `outputs/<slug>/sections/NN-<heading>.verify.json` | `/seo-draft` | Verifier findings, each marked `accepted` or with a `reject` reason |
| `outputs/<slug>/sections/NN-<heading>.unverified.md` | `/seo-draft` | The part as drafted, before verification |
| `outputs/<slug>/sections/NN-<heading>.verify.prompt.txt` | `/seo-draft` | The filled fact-check prompt |
| `outputs/<slug>/draft.md` | `/seo-draft` | The stitched article draft |
| `outputs/<slug>/rewrite/NN-<heading>.{prompt.txt,md}` | `/seo-rewrite` | Each part's edit prompt and edited text (the drafted text when the edit failed twice) |
| `outputs/<slug>/rewrite/NN-<heading>.{verify.json,verify.prompt.txt,unverified.md}` | `/seo-rewrite` | The fact check of an accepted edit, as in `sections/` |
| `outputs/<slug>/rewrite/NN-<heading>.rejected-seedN.md` | `/seo-rewrite` | An edit that failed `check.sh rewrite`, kept for inspection |
| `outputs/<slug>/final.md` | `/seo-rewrite` | The stitched, edited article |

`outputs/` and `briefs/_ingest/` are gitignored. The `_`-prefixed prompt files are
kept on purpose: when a result looks wrong, they show exactly what the model was
asked. Each stage pins its own sampling: ingest runs at temperature 0.2 seed 1,
outline at 0.3 seed 1, each draft section at 0.5 seed 1, each fact check at 0.1 seed 1,
and each rewrite at 0.7 seed 1. A failed check is retried with seed 2, because the
same seed usually repeats the same output.

## Running without Claude Code

The skills are orchestration. The pipeline underneath is a prompt file plus the
wrapper, so any stage can be driven from a terminal. This is also the fastest way
to check the router end to end:

```bash
# Runs in: local terminal
# 1. A one-line smoke test. Prints a sentence and exits 0.
printf 'In one sentence, what is your role?\n' > /tmp/role.txt
bash scripts/llm_call.sh /tmp/role.txt 0.2 1

# 2. Build an outline prompt from a brief, call the model, check the result.
mkdir -p outputs/example
bash scripts/fill_prompt.sh prompts/outline.md --brief briefs/example.json > outputs/example/_outline_prompt.txt
bash scripts/llm_call.sh outputs/example/_outline_prompt.txt 0.3 1 > outputs/example/outline.md
bash scripts/check.sh outline outputs/example/outline.md briefs/example.json
bash scripts/draft_sections.sh briefs/example.json
bash scripts/check.sh draft outputs/example/draft.md outputs/example/outline.md briefs/example.json draft
bash scripts/rewrite_sections.sh briefs/example.json
bash scripts/check.sh draft outputs/example/final.md outputs/example/outline.md briefs/example.json

# 3. Check a brief against the schema the way /seo-ingest does.
bash scripts/check.sh brief briefs/example.json
```

## Troubleshooting

Every failure is an exit code from `scripts/llm_call.sh`, and the message says
which one. None of them are retried silently.

| Exit | Meaning | What to do |
| --- | --- | --- |
| 1 | No prompt file given | Pass a prompt file as the first argument |
| 2 | A file is unreadable or unusable | Check the path in the message. An empty or malformed schema file lands here deliberately, so a bad schema cannot turn into an unconstrained call, and so does an empty prompt file, because the router would otherwise answer the system message alone and return confident, unrelated text |
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

[AGENTS.md](AGENTS.md) is the source of truth for how work happens here. Read it before making changes. The other pillars are [PLAN.md](PLAN.md) (architecture and the phased MVP plan) and this README (user-facing and developer-facing). [INSTRUCTIONS.md](INSTRUCTIONS.md) is a companion walk-through of the pipeline and must change with it.

The fourth pillar, `IMPLEMENT.md`, is the execution tracker and holds the live state: which phase is active, what is done, what is deferred. It is untracked and gitignored on purpose, so a fresh clone has none. Its absence means no work is in flight, not that state was lost. Create it from the skeleton in `AGENTS.md` when you start a phase.

The short version: one phase at a time, at most five files per phase, walking-skeleton first, verify end-to-end against the live llama.cpp router, and end each phase with the literal handoff line.

This repo is SEO only. The tutor application that used to live alongside it now has its own repo, `~/Apps/Tutor-LLM`, and shares no code with this one.
