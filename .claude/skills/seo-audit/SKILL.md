---
name: seo-audit
description: Audit a finished article against its research, keyword choice and facts, and write the verdict to outputs/<slug>/audit.md. Read-only on every other file and makes no model call. The judge after `./seo --auto <slug>` exits 0, run as `claude -p "/seo-audit <slug>"`, or by hand. Use when the user runs /seo-audit <slug> or asks whether a finished article can be trusted.
---

# seo-audit

The local model wrote this article and the scripts checked what can be counted.
This skill is the part no script can do: Claude Code reads the article against the
research and the facts and says what is wrong with it (PLAN.md design principle 3).
It runs after `./seo --auto <slug>` exits 0, so an article nobody watched being
written is read before anybody publishes it.

`outputs/<slug>/audit.md` is this skill's output, a pipeline artifact like
`final.md` that a scheduler reads for its verdict line. Writing it is the task, not
a report written on the side.

## Inputs

- `$1`: the slug, for example `how-to-clean-cat-water-fountain`. If missing, ask
  which page to audit.

Paths, all relative to the repo root:
- `outputs/<slug>/final.md`, the article, and `outputs/<slug>/outline.md`
- `briefs/<slug>.json`, whose `facts` list is the only source of business specifics
- `research/<slug>/research.json` and `research/<slug>/keywords.json`
- `outputs/<slug>/sections/*.verify.json` and `outputs/<slug>/rewrite/*.verify.json`,
  the fact checker's reports

## Preconditions

1. Every input above exists. If `final.md` is missing, say the article is not
   finished, name the missing file, and stop without writing `audit.md`: an audit of
   nothing must not leave a verdict a scheduler could read.

## Steps

1. Run the deterministic check on the article:
   `bash scripts/check.sh draft outputs/<slug>/final.md outputs/<slug>/outline.md briefs/<slug>.json`
   Every FAIL line becomes a FAIL in the audit. Keep the WARN lines for the notes.
2. List the claims the fact checker flagged and could not safely fix, which are
   still in the article:
   `jq -r '.issues[]? | select(.accepted == false) | "\(.kind): \(.sentence)"' outputs/<slug>/sections/*.verify.json outputs/<slug>/rewrite/*.verify.json`
3. Read `final.md` against the brief's `facts`. List every business specific the
   facts do not state: names of businesses, products or people, prices,
   timelines, policies, guarantees, locations, stock, shipping, contact channels,
   and who does what. List every place a fact is strengthened, such as "most"
   becoming "all" or "from $20" becoming "$20". Each one is a FAIL with its sentence
   quoted exactly. When `facts` is empty, the article may state no business
   specific at all, so any one is a FAIL. Start from the step 2 claims, then read
   every section, because the checker misses some.
4. Read `final.md` for text that is broken as written. The fact checker swaps a
   flagged sentence for a replacement, and a bad swap leaves a stub ("Clean the
   parts."), the same stub twice in a row, a fragment, or a sentence whose "it",
   "this" or "instead" now points at nothing. On a how-to page it can strip the
   steps themselves, so a section promises instructions it no longer gives. Each
   one is a FAIL with its sentence quoted exactly, because a reader cannot use it
   and nothing downstream will notice. Awkward but intact wording is a note, not a
   FAIL. (Added 2026-10-07: the first audit passed a how-to article whose cleaning
   steps read "Clean the parts. Clean the parts.")
5. Read the keyword choice in `keywords.json` against `research.json`, as
   `/seo-keywords` step 5 does. Check each claim the `rationale` makes about the
   data (which term has the most volume, impressions or clicks), and check that
   the primary keyword is in `research.json`. A claim the figures contradict is a
   FAIL with the figure that contradicts it. A claim the research cannot settle
   either way is a note.
6. Write `outputs/<slug>/audit.md` in exactly this shape, replacing any earlier
   one:

   ```
   # Audit: <slug>
   Verdict: PASS
   Audited: <YYYY-MM-DD>, final.md at <N> words

   ## Checks
   PASS check.sh draft
   ## Business specifics against the facts
   PASS none found
   ## Text as written
   PASS none broken
   ## Keyword choice against the research
   PASS the rationale matches the research
   ## Notes
   - <each WARN line, and each general claim that is unsourced but not a business specific>
   ```

   Each FAIL is its own line starting `FAIL `, under its section, with the
   sentence or claim quoted. `Verdict:` is `FAIL` when any line starts `FAIL `,
   otherwise `PASS`. A note never changes the verdict. The second line is always
   the verdict, so `grep -x 'Verdict: PASS' outputs/<slug>/audit.md` decides.
7. Reply with the verdict and every FAIL line, in a few lines.

## Rules

- Run each command in the steps exactly as written, one per Bash call, with
  nothing chained before or after it (no `echo`, `;`, `&&` or redirect). An
  unattended run allows those exact commands and nothing else, so a combined
  command is denied. Read files with the Read tool, not `cat` or `ls`.
- Write `audit.md` with the Write tool, never through the shell. The Write tool
  on that one file is the only write an unattended run allows, and a shell
  redirect is denied, which leaves no verdict at all. (Added 2026-10-07: a
  scheduled audit decided PASS and could not save it.)
- Write `audit.md` and nothing else. Never edit the article, the brief, the facts,
  the research or any stage file, even to fix what you found: fixing is the
  pipeline's job, through `p` or a person.
- Make no model call and run no pipeline stage. Every input is already on disk.
- Quote sentences exactly as they appear in `final.md`, so they can be found.
- A general claim with no number and no business in it ("cats prefer moving
  water") is not a business specific. Put it in the notes when it is unsourced.
