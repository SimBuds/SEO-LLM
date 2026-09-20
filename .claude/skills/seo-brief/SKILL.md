---
name: seo-brief
description: Build a content brief one approved stage at a time from a page's research and keyword choice, stopping after each stage so the user can correct it. Phase 9 stage, between /seo-keywords and /seo-outline. Use when the user runs /seo-brief <slug> or asks to turn research into a brief.
---

# seo-brief

Run `research/<slug>/` through the brief stages, one call per stage, stopping
after each so the user reads and edits it. Stage files live in
`research/<slug>/brief-stages/`.

Stages built so far: **intent** (topic, audience, reader goal, tone) and
**structure** (the sections this page needs, the FAQ questions, the gaps in the
ranking pages). Stages 3 and 4, and writing `briefs/<slug>.json`, are Phase 10
and are not built yet. Say so if the user expects a brief file at the end.

## Inputs

- `$1` the slug. If missing, ask which page.
- On the first run only, a one-line purpose: **"In one line, what is this page for
  and who is it for?"** It is saved to `brief-stages/purpose.txt` and reused, so
  later stages cannot drift onto a different page.

## Preconditions

1. The router serves `qwen`: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen`.
2. `research/<slug>/research.json` and `research/<slug>/keywords.json` exist. The
   script exits 2 naming the command to run if either is missing.

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
6. After the last built stage, say that stages 3 and 4 (targets, facts) and the
   merge into `briefs/<slug>.json` arrive in Phase 10.

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
