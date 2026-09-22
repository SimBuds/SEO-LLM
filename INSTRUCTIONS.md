# Pipeline flow

There are two ways to run the pipeline, and they drive the same scripts and write
the same files.

- **`./seo`**, the menu, from a terminal. It asks whether the page is live, which
  page it is, and then for whatever inputs are missing, and shows every stage with
  its state. See "The menu" below.
- **The seven `/seo-*` commands in Claude Code**, run in order. Each one writes
  files that the next one reads, and this document walks through them.

```
/seo-research <slug>  ──▶ research/<slug>/page.json + research.json
   │  (does the page exist? your keyword exports, the competitor pages)
   ▼
/seo-keywords <slug>  ──▶ research/<slug>/keywords.json
   │  (the target keyword, the intent, the questions to answer)
   ▼
/seo-brief <slug>     ──▶ brief-stages/01..04, you approve each
   │  (--merge writes the brief)          ▲
   │                    source doc ───────┘  /seo-ingest <file>
   │                    (.pdf/.md/.txt, optional: the facts stage reads it)
   ▼
briefs/<slug>.json ── you review/edit ──┐
   │  /seo-outline briefs/<slug>.json   │
   ▼                                    │
outputs/<slug>/outline.md               │
   │  /seo-draft briefs/<slug>.json     │
   ▼                                    │
outputs/<slug>/sections/*  →  draft.md  │  all stages read the brief's `facts`
   │  /seo-rewrite briefs/<slug>.json   │
   ▼                                    │
outputs/<slug>/rewrite/*   →  final.md ◀┘
```

The `<slug>` is the brief's file name without `.json`, so a page's research, its document, its brief and its outputs all share one name.

## 0. Before you start

1. **The router is up and serves Qwen.** This must print `qwen`:
   ```bash
   # Runs in: local terminal
   systemctl --user is-active llama-server
   curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'
   ```
   Every command runs this check first and stops if it fails. The router is managed from `~/Apps/Local-LLM`, not from this repo.
2. **Claude Code is open in this repo**, with the trust dialog accepted, so the `/seo-*` commands resolve and the scripts run without a prompt each time.
3. **A brief exists**, either written by hand (copy `briefs/example.json`) or made by `/seo-ingest`. A hand-written brief skips step 1 below.

## 1. `/seo-research <slug>`: research before writing

No model call in this stage. It gathers what the page has to beat.

1. **Does the page exist?** The command asks. Give a URL and it snapshots the live page: title, meta description, H1 to H3 and word count, into `research/<slug>/page.json`. Say no and it records a new page.
2. **Your exports.** `./seo` asks for their paths and copies them in for you. By hand, drop the Search Console Performance export into `research/<slug>/inputs/`, which is the source this pipeline is built around because its numbers are measured rather than estimated. Columns are read by name, so download and drop, with no reshaping, and any other keyword export you happen to have parses as well. Nothing is fetched from Google, and no API key exists anywhere in this repo.
3. **Competitors.** `./seo` asks for these too, one per line. By hand, put the top 3 to 5 ranking URLs into `research/<slug>/competitors.txt`, one per line. You find them in Google, because the pipeline never fetches a results page.
4. **Collect:** `scripts/research_collect.sh` merges the exports by keyword, fetches each competitor (obeying `robots.txt`, waiting between requests to one host, caching the HTML), and writes `research/<slug>/research.json`.
   It also builds your own page inventory from your sitemap, once per site, and records which of your pages already target a researched query. For a page that is not live yet, put your site URL in `research/<slug>/site.txt` so it knows where to look.
5. **The keyword list is capped at 150** by volume (`MAX_KEYWORDS`, `0` keeps all), because a full keyword export is thousands of rows and does not fit the keyword prompt's context. `research.json` records `keywords_total` and `keywords_cutoff`, and the check WARNs when a cut happened. An export that cannot be read stops the run (exit 4) and writes nothing.
6. **`check.sh research`:**
   - **Fails** only when the file's shape is broken.
   - **Warns** on thin research: no keywords, no competitors, fewer than three fetched, an existing page missing its title or meta description, or one of your own pages already targeting the query.
7. **Your review:** read the competitor word counts and their H2 outlines. They set the length and the sections the page has to cover.

## 2. `/seo-keywords <slug>`: research → the target keyword

One model call at temperature 0.2 against `research.json`, one line from you about what the page is for, the content type, and any keywords you suggested. From the menu the suggestions are asked for once per page and saved to `research/<slug>/suggested.txt`, one per line: the model may return one of them even though the research does not carry it, and it still judges them on demand and fit against the researched terms. It writes `research/<slug>/keywords.json`: the primary keyword, 2 to 6 secondary keywords, the intent (type, format, angle), a business-potential score of 0 to 3, the questions the ranking pages answer, and the subtopics they share.

`check.sh keywords <keywords.json> <research.json> [suggested.txt]` **fails** when any keyword is missing from the research file, which catches a reworded keyword as well as an invented one. With the optional third argument your suggested keywords count as grounding too, so a term you asked for is not reported as invented, while a term in neither still fails. It **warns** when the reasoning repeats research figures or when your live page targets something else.

## 3. `/seo-brief <slug>`: research → brief, one stage at a time

Four stages, one model call each, and each stage sees the ones before it. From the menu one press runs every stage that is still missing and stops once at the end with all four to read. `/seo-brief` in Claude Code still walks them one at a time.

The content type shapes stages 1 and 2. `review` is one product you have used, `roundup` is several you have tested and supply as facts, `guide` teaches the choice and names no product, `how-to` is the steps of a task in order, and an empty answer is a general article.

1. **intent:** topic, audience, reader goal, tone, each with its reason.
2. **structure:** the sections this page needs, each tagged with where it came from, plus the FAQ questions and the gaps in the ranking pages.
3. **targets:** the brief's keywords and the call to action.
4. **facts:** the business specifics, taken only from `briefs/_ingest/<slug>.txt`. The menu asks for them before the stages run and writes that file, so a document is no longer the only way to supply them. With nothing supplied the list is written empty and no call is made.

Editing a stage file is usually better than rerunning it, because a rerun is a fresh sample and may change other fields too. `--redo <stage>` rebuilds one and drops every stage after it.

**`--merge`** writes `briefs/<slug>.json` from the approved stages and runs `check.sh brief`. It refuses to overwrite an existing brief without `--force`. The word count is computed from the competitor median, not asked of the model, and the menu then offers it to you as a default you can replace. The merge also carries the research forward into the brief's four optional keys: `search_intent` from the keyword choice, `must_cover` and `questions` from the structure stage, and `existing_page` from the research when the page is live.

## 4. `/seo-ingest <file>`: document → brief

1. **Guard:** if `briefs/<slug>.json` already exists, it asks before overwriting it.
2. **Extract:** the text is pulled out with `pdftotext` (PDF), `pandoc` (Word, not installed yet) or a plain copy (`.md`, `.txt`) into `briefs/_ingest/<slug>.txt`. Under 50 characters stops the run, since the PDF is probably a scan.
3. **Fill:** `fill_prompt.sh` squeezes extra spaces and cuts very long text at 24,000 characters, saying so when it does.
4. **Model call:** Qwen at temperature 0.2 fills a fixed JSON format (`prompts/brief.schema.json`) with these fields:
   - topic, audience, tone
   - word count, set from the page type (About ~800, Contact ~1,000, FAQ ~1,500, standalone article ~2,000)
   - 3 to 6 keywords, keeping capitals on place names
   - call to action
   - **facts**: up to 40 business details copied from the document
5. **`check.sh brief`:**
   - **Fails** if the brief doesn't match that format.
   - **Warns** about a call to action that mentions page UI, weak keywords, an empty facts list, or fact numbers that aren't in the source.
6. **Fact check:** Claude Code compares each fact against the source text and lists anything added or overstated. It proposes fixes but doesn't make them.
7. **Your review:** check and edit the brief before going on, since everything after this step is built from it.

## 5. `/seo-outline <brief>`: brief → outline

1. **Model call:** Qwen at temperature 0.3 writes headings only. Every section gets an `_Intent:` line and a `Keywords:` line.
2. **Size:** the number of topic sections depends on the word count: 2 to 3 up to 1,000 words, 3 to 5 up to 1,800, and 4 to 6 above that.
3. **`check.sh outline`:**
   - **Fails** on anything other than one H1, any body text, a missing FAQ or Conclusion, or a section without an intent line.
   - **Warns** on section or question counts outside the size table, subsections under the Conclusion, and keywords pasted into headings.
4. **Retry:** on a failure, Claude Code asks whether to regenerate with seed 2 (then 3). The same seed repeats the same outline. Warnings don't block the draft.

## 6. `/seo-draft <brief>`: outline → `draft.md` (`scripts/draft_sections.sh`)

1. **Preconditions:** the brief passes its check and `outline.md` exists and passes its check. Otherwise the run stops and asks for `/seo-outline` first.
2. **Split:** the outline becomes an intro plus one part per section, including the FAQ and the Conclusion.
3. **Budget:** the draft aims at **120%** of the word count, because the rewrite cuts it back. It was 135% until 2026-09-21, when two measured runs cut 13% and 17.5% instead of the assumed 20 to 35%. `DRAFT_FACTOR` overrides it. A part over 140% of its own budget now fails and is regenerated instead of being stitched in.
   - Split: intro 8% (at least 60 words), conclusion 6%, FAQ 60 words per question (at most 20%). The rest goes to the topic sections by subsection count.
4. **Keyword spread:** each main keyword's cue is kept in at most 2 parts, and the FAQ gets none.
5. **Drafting:** one Qwen call per part at temperature 0.5, using `prompts/intro.md`, `prompts/section.md` or `prompts/conclusion.md`.
   - Each call sees the audience, tone, facts and all outline headings.
   - The script puts the outline's heading wording back and removes bold.
   - **`check.sh section`** runs next: exact headings, no leftover outline notes, word budget, and the call to action in the Conclusion.
   - A failed part is retried with seed 2. If it fails again, it's saved as `.ERROR.md` and the run stops.
6. **Fact-check pass** (`prompts/verify.md`, temperature 0.1, 1,500-token limit, 120-second timeout):
   - The call lists sentences that invent a detail, overstate a fact, or contradict one, each with a replacement.
   - A replacement is swapped in word for word only if the original sentence is found and it doesn't touch the call to action.
   - It also can't add new words, and a fix to an overstated sentence can't drop more than half of it.
   - Findings are logged in `sections/NN-<heading>.verify.json`, and the text before the pass is kept in `.unverified.md`. If the fixed part fails its check, that text is restored.
   - A fact-check call that fails or times out leaves the part unverified with a warning. Rerunning retries it.
7. **Output:** the parts are joined into `draft.md`. Rerunning skips parts that already passed. A strictly newer outline or `--fresh` redoes everything, and `DRAFT_SEED` moves the seed pair the loop tries. From the menu, `p` redoes one part at a seed you choose and leaves the rest alone.
8. **`check.sh draft … draft`:**
   - **Fails** if the headings don't match the outline or outline notes are left in.
   - **Warns** on length, keyword overuse, bold, numbers that aren't in the facts, and absolute wording ("all", "every", "guaranteed"…).
9. **Fact check:** Claude Code lists the fact-checker's rejected issues, which are still in the draft, then reviews the rest against the facts. It reports findings and doesn't edit the draft.

## 7. `/seo-rewrite <brief>`: `draft.md` → `final.md` (`scripts/rewrite_sections.sh`)

1. **Preconditions:** `sections/00-intro.md` exists and no part is an `.ERROR.md`. Otherwise it asks for `/seo-draft` first.
2. **Editing:** Qwen at temperature 0.7 edits each part in order with `prompts/rewrite.md`. It fixes awkward keyword phrasing, cuts filler and repetition, and fixes the fact-checker's rejected issues for that part.
   - Each call sees the parts already edited.
3. **`check.sh rewrite`** compares each edit with its input:
   - same headings
   - 50 to 120% of the original length
   - no numbers that aren't in the input or the facts
   - no more absolute wording than before
   - the call to action neither lost nor added to another part
4. **Failures:** a failed edit is retried with seed 2, and rejected edits are kept as `rejected-seedN.md`. After a second failure the draft text is kept with a warning, so the run never stops.
5. **Second fact-check:** each accepted edit goes through the same fact-check pass again (`rewrite/NN-<heading>.verify.json`).
6. **Output:** the parts are joined into `final.md`, and `check.sh draft` runs against the real target. Rerunning skips edits that are newer than their input and still pass. `--fresh` redoes every part.
7. **Final review:** Claude Code compares `final.md` with `draft.md` and the facts. It notes which rejected issues were fixed and any claim the facts don't support.

## The menu

From the menu, `n` accepts a flagged figure into the facts and rebuilds the brief, `p` redoes one drafted part, and `e` changes a recorded answer.

`./seo [slug]` runs the whole thing from one place (`scripts/seo.sh` is the script
behind it, and still works when called directly). It reads each stage's state from
the files on disk, so it always knows what is done, what is ready and what is
blocked, and picking a number runs that stage.

With no slug it asks whether the page already exists on your site, then which page
it is, and then walks a new page through the inputs it is missing: the live page's
URL, or your site's URL when it is not live yet, the keyword export paths, and the
competitor URLs. Each question takes a blank answer, and a page that already has
these is asked nothing.

```
SEO pipeline: example-domains
router: serving qwen

  1 [done   ] Page check         live page, title 62 chars, 268 words
  2 [done   ] Collect research   4 keywords, 2/2 competitors, 2 exports
  3 [ready  ] Keyword choice       <- next
  4 [blocked] Brief stages       needs keywords.json
```

All nine stages run from the menu, and `a` runs every ready one in turn. It
stops before the two stages that need you (the page check wants a URL or a no,
the collection wants your exports and competitor URLs), stops after the brief
stages so you read all four, and stops at the first failure. From a
finished brief, one `a` takes you through the outline, the draft, the rewrite
and the review.

The menu asks the page purpose, the content type, your suggested keywords and the
facts the page may state once each and reuses them, with `e` to change any of them
later and clear whatever was built on the old answer. It checks the router before any model call, offers a reseed when
a check fails rather than retrying behind your back, and always asks before
replacing an artifact.

## Shared pieces

- **`scripts/llm_call.sh`:** the only way to reach the model.
  - It always sends `prompts/system.md`, which says to use only the source facts.
  - It checks the router's context size before every call and requires at least 32,768 tokens.
  - Thinking is off, and all sampling settings are fixed in the script.
  - `LLM_MODEL`, `LLM_MAX_TOKENS` and `LLM_TIMEOUT` change the model, output limit and timeout.
- **`scripts/fetch_sitemap.sh`:** reads your sitemap (and a sitemap index) into a plain URL list, once per site, through the fetcher below.
- **`scripts/fetch_page.sh`:** the only way this repo reaches the open web. It obeys `robots.txt`, waits between requests to one host, caches the HTML in `research/_cache/`, and pulls out the title, meta description, headings and word count. `FETCH_UA` sets the User-Agent, which carries no contact address by default.
- **`scripts/research_collect.sh`:** merges your keyword exports by column name and fetches the competitor URLs into one `research.json`.
- **`./seo`:** the launcher at the repo root. It resolves the repository from its own path and hands over to `scripts/seo.sh`, so it works from any directory.
- **`scripts/seo.sh`:** the interactive menu, and the intake that fills in a new page's inputs before it. It runs the other scripts and reads state from the artifacts, so it holds no state of its own.
- **`scripts/brief_stages.sh`:** one model call per brief stage, stopping after each for your approval, then `--merge` assembles `briefs/<slug>.json` and computes the word count from the competitor median.
- **`scripts/fill_prompt.sh`:** fills every prompt from the brief, outline and source text, and fails if a placeholder is left unfilled.
- **`scripts/check.sh`:** holds every rule (research, brief, outline, section, draft, rewrite). A problem that must be fixed is a FAIL. One worth a look is a WARN.
- **`scripts/lib_parts.sh`:** shared by the loops and `check.sh`. It holds the fact-check pass, heading restore, bold removal, the absolute-wording pattern and the draft multiplier.
- **Models:** Qwen is the default everywhere. `VERIFY_MODEL=gemma` and `REWRITE_MODEL=gemma` switch those two stages. In the comparisons, Gemma was close but slightly worse.

## Settings at a glance

| Stage | Model | Temperature | Seed | Retry |
| --- | --- | --- | --- | --- |
| research | none, no model call | n/a | n/a | rerun, or `--fresh` to refetch |
| keywords | qwen | 0.2 | 1 | rerun after fixing the research |
| brief stage | qwen (`STAGE_MODEL`) | 0.3 | 1 | automatic, seed 2, then stop |
| ingest | qwen | 0.2 | 1 | ask, then 0.1 |
| outline | qwen | 0.3 | 1 | ask, then seed 2 or 3 |
| draft part | qwen | 0.5 | 1 | automatic, seed 2 |
| fact check | qwen (`VERIFY_MODEL`) | 0.1 | 1 | on rerun |
| rewrite part | qwen (`REWRITE_MODEL`) | 0.7 | 1 | automatic, seed 2 |

## Typical run

From the terminal, the whole run is one command:

```
./seo                                   # answer the intake, then work down the menu
```

Driven from Claude Code, it is the seven commands in order:

```
/seo-research client-page               # answer the page question, add exports and competitor URLs
/seo-keywords client-page               # pick the target keyword
/seo-ingest  briefs/client-page.pdf     # optional: a source document for the facts stage
/seo-brief   client-page                # four approved stages, then --merge
/seo-outline briefs/client-page.json
/seo-draft   briefs/client-page.json
/seo-rewrite briefs/client-page.json    # read outputs/client-page/final.md
```

## Where files land

| Path | Stage | What it is |
| --- | --- | --- |
| `research/<slug>/page.json` | research | Whether the page exists, and its current title, description, headings and length |
| `research/<slug>/inputs/*.csv` | you or the launch intake | The keyword and query exports you downloaded |
| `research/<slug>/competitors.txt` | you or the launch intake | The competitor URLs you listed |
| `research/<slug>/site.txt` | you or the launch intake | Your site's URL, when the page is not live yet |
| `research/<slug>/type.txt` | keywords | The content type, recorded once, empty when declined |
| `research/<slug>/suggested.txt` | keywords | The keywords you suggested, recorded once, empty when you suggested none |
| `research/<slug>/research.json` | research | Merged keywords, fetched competitor pages, the existing page |
| `research/<slug>/keywords.json` | keywords | The target keyword, intent, business potential, questions, subtopics |
| `research/<slug>/brief-stages/NN-<stage>.json` | brief | One approved stage, with its prompt and schema beside it |
| `research/_cache/` | research | Cached competitor HTML, gitignored |
| `briefs/_ingest/<slug>.txt` and `.prompt.txt` | ingest | Extracted source text and the filled prompt |
| `briefs/<slug>.json` | ingest | The brief |
| `outputs/<slug>/_outline_prompt.txt` | outline | The filled outline prompt |
| `outputs/<slug>/outline.md` | outline | The outline |
| `outputs/<slug>/sections/NN-<heading>.*` | draft | Block, prompt, part, `.verify.json`, `.unverified.md`, or `.ERROR.md` |
| `outputs/<slug>/draft.md` | draft | The joined draft |
| `outputs/<slug>/rewrite/NN-<heading>.*` | rewrite | Prompt, edited part, `.verify.json`, rejected attempts |
| `outputs/<slug>/final.md` | rewrite | The finished article |

The prompt files are kept on purpose. When a result looks wrong, they show exactly what the model was asked.

## What still needs a person

- **Finding the competitors.** You search Google and paste the top 3 to 5 URLs. The pipeline never fetches a results page.
- **The call to action.** Stage 3 is where the model is most likely to promise something you do not offer, such as a downloadable checklist or a free trial. Read it before merging.
- **The `omitted` list in stage 4.** Design notes and marketing adjectives belong there, but a real business detail can land there too.
- **The brief.** The model sometimes overstates facts or turns design notes into facts.
- **Absolute claims** that the fact-checker flagged but couldn't safely fix. List them with:
  `jq -r '.issues[]? | select(.accepted == false) | .sentence' outputs/<slug>/*/*.verify.json`
- **Missed claims** in sections that kept their draft text, since those aren't fact-checked a second time.
- **Outlines for short pages** that have too many subsections. They push 800-word pages toward 940 words, so trim or regenerate the outline when `check.sh outline` warns.
