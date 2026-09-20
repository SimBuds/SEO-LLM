---
name: seo-brief
description: Build a content brief one approved stage at a time from a page's research and keyword choice, stopping after each stage so the user can correct it, then merge the approved stages into briefs/<slug>.json. Phases 9 and 10, between /seo-keywords and /seo-outline. Use when the user runs /seo-brief <slug> or asks to turn research into a brief.
---

# seo-brief

Run `research/<slug>/` through the brief stages, one call per stage, stopping
after each so the user reads and edits it. Stage files live in
`research/<slug>/brief-stages/`.

The four stages: **intent** (topic, audience, reader goal, tone), **structure**
(sections, FAQ questions, gaps in the ranking pages), **targets** (keywords and
the call to action) and **facts** (the business specifics the article may state).
Then `--merge` writes `briefs/<slug>.json`.

## Inputs

- `$1` the slug. If missing, ask which page.
- On the first run only, a one-line purpose: **"In one line, what is this page for
  and who is it for?"** It is saved to `brief-stages/purpose.txt` and reused, so
  later stages cannot drift onto a different page.

## Preconditions

1. The router serves `qwen`: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen`.
2. `research/<slug>/research.json` and `research/<slug>/keywords.json` exist. The
   script exits 2 naming the command to run if either is missing.
3. For the facts stage, `briefs/_ingest/<slug>.txt` from `/seo-ingest` if the
   user has a source document. Without it the facts list is written empty with no
   model call, which is correct for a page with no business specifics. Tell the
   user that is what will happen, and offer `/seo-ingest` first if they have a
   document.

## Steps

1. Run one stage:
   ```bash
   bash scripts/brief_stages.sh <slug> --purpose "<the one-line purpose>"   # first run
   bash scripts/brief_stages.sh <slug>                                      # each later stage
   ```
   It runs the first stage with no file, prints it, and stops. It never runs two
   stages in one invocation, because each one is yours to approve.
2. Show the stage's JSON and say what it commits the article to. Then ask
   plainly: **approve, or say what to change?**
3. If the user wants a change, either edit the stage file directly with their
   wording, or rerun that stage with `--redo <stage>`. Editing is better when
   they told you the exact value they want, because a rerun is a fresh sample
   and may change other fields too.
4. `--redo <stage>` deletes that stage **and every stage after it**, since the
   later ones were built on the version being replaced. Say that before running
   it, and show which files will go.
5. When the user approves, run the script again for the next stage. Each stage
   sees the approved ones, so an edit carries forward.
6. After the fourth stage, merge:
   ```bash
   bash scripts/brief_stages.sh <slug> --merge
   ```
   It refuses when `briefs/<slug>.json` already exists. Show the user the existing
   brief and ask before rerunning with `--merge --force`.
7. The merge runs `check.sh brief` on the result. Report its WARN lines, then say:
   *"Review `briefs/<slug>.json`, then run `/seo-outline briefs/<slug>.json`."*

## What the merge does and does not carry

- `word_count` is **computed**, not generated: the median of the competitor word
  counts that were actually fetched, rounded to 50 and clamped to 600 to 3000,
  or 1000 when no competitor page was fetched. Say which number it used and why.
  If the user wants a different length, they edit the brief.
- The structure stage is **not** merged. The seven-key brief has nowhere to put
  sections, questions or gaps, so they stay in `02-structure.json` until the
  brief schema carries them. Tell the user where to find them, because the
  outline stage cannot see them yet.

## What to check in each stage

The router enforces the shape, so read for substance instead:

- **intent**: is the audience a real description rather than a category? Is
  `reader_goal` the reader's goal and not the business's? Does `tone_reason`
  point at something in the research?
- **structure**: every section carries a `source`. Challenge any marked
  `page purpose` that looks like it came from the model's own knowledge, and any
  `must_cover` or `competitor heading` you cannot find in `research.json`. An
  empty `faq_questions` is correct when the competitors have no question
  headings, and it means the FAQ will need real customer questions later.
- **targets**: the keywords must be the ones in `keywords.json`. The call to
  action is the field most likely to promise something the business does not
  offer, such as a downloadable file or a free trial. Read it against what the
  user actually has and say so.
- **facts**: read `omitted` as carefully as `facts`. Design notes and marketing
  adjectives belong there, but a real business detail can land there too, and
  the user is the one who knows. Check every kept fact still carries its
  qualifier ("most", "from", "up to"): a dropped qualifier is an invented
  promise.

## Failure handling

- Exit 2: a missing input, named in the message. Run the command it names.
- Exit 3: the model returned an unusable reply twice, at seed 1 and seed 2. The
  filled prompt is kept. Read it, since the usual cause is thin or contradictory
  research rather than the model.
- Never write a stage file by hand from the model's chat output. The stage files
  come from the script, or from the user's own edit.

## Out of scope

No outline, draft or metadata. Do not add business specifics, prices, or claims
at these stages: facts come from a source document in Phase 10, and the prompts
forbid inventing them.
