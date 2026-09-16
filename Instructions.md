# Pipeline flow

The pipeline has four commands, run in order in Claude Code. Each one writes files that the next one reads.

```
source doc (.pdf/.docx/.md/.txt)
   │  /seo-ingest <file>
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

The `<slug>` is the brief's file name without `.json`, so a document, its brief and its outputs all share one name.

## 1. `/seo-ingest <file>`: document → brief

1. **Guard:** if `briefs/<slug>.json` already exists, it asks before overwriting it.
2. **Extract:** the text is pulled out with `pdftotext` or `pandoc` into `briefs/_ingest/<slug>.txt`. Extra spaces are squeezed and very long text is cut at 24,000 characters.
3. **Model call:** Qwen at temperature 0.2 fills a fixed JSON format (`prompts/brief.schema.json`) with these fields:
   - topic, audience, tone
   - word count: set from the page type (About ~800, Contact ~1,000, FAQ ~1,500, standalone article ~2,000)
   - 3–6 keywords, keeping capitals on place names
   - call to action
   - **facts**: up to 40 business details copied from the document
4. **`check.sh brief`:**
   - **Fails** if the brief doesn't match that format.
   - **Warns** about a call to action that mentions page UI, weak keywords, an empty facts list, or fact numbers that aren't in the source.
5. **Fact check:** Claude Code compares each fact against the source text.
6. **Your review:** check the brief before going on, since everything after this step is built from it.

## 2. `/seo-outline <brief>`: brief → outline

1. **Model call:** Qwen at temperature 0.3 writes headings only. Every section gets an `_Intent:` line and a `Keywords:` line.
2. **Size:** the number of sections depends on the word count: 2–3 up to 1,000 words, 3–5 up to 1,800, and 4–6 above that.
3. **`check.sh outline`:**
   - **Fails** on any body text, a missing FAQ or Conclusion, or a section without an intent line.
   - **Warns** on section or question counts outside the size table, and on too many subsections for the length.
4. **Retry:** a failed outline is retried with seed 2.

## 3. `/seo-draft <brief>`: outline → `draft.md` (`scripts/draft_sections.sh`)

1. **Split:** the outline becomes an intro plus one part per section, including the FAQ and the Conclusion.
2. **Budget:** the draft aims at **135%** of the word count, because the rewrite cuts it back. `DRAFT_FACTOR` overrides it.
   - Split: intro 8%, conclusion 6%, FAQ 60 words per question; the rest goes to the topic sections by subsection count.
3. **Keyword spread:** each main keyword's cue is kept in at most 2 parts, and the FAQ gets none.
4. **Drafting:** one Qwen call per part at temperature 0.5, using `prompts/intro.md`, `prompts/section.md` or `prompts/conclusion.md`.
   - Each call sees the audience, tone, facts and all outline headings.
   - The script puts the outline's heading wording back and removes bold.
   - **`check.sh section`** runs next: exact headings, no leftover outline notes, word budget, and the call to action in the Conclusion.
   - A failed part is retried with seed 2. If it fails again, it's saved as `.ERROR.md` and the run stops.
5. **Fact-check pass** (`prompts/verify.md`, temperature 0.1, 1,500-token limit, 120-second timeout):
   - The call lists sentences that invent a detail, overstate a fact, or contradict one, each with a replacement.
   - A replacement is swapped in word for word only if the original sentence is found and it doesn't touch the call to action.
   - It also can't add new words, and a fix to an overstated sentence can't drop more than half of it.
   - Findings are logged in `sections/NN-<heading>.verify.json`. If the fixed part fails its check, the pre-check text is restored.
6. **Output:** the parts are joined into `draft.md`. Rerunning skips parts that already passed; a newer outline or `--fresh` redoes everything.
7. **`check.sh draft … draft`:**
   - **Fails** if the headings don't match the outline or outline notes are left in.
   - **Warns** on length, keyword overuse, bold, numbers that aren't in the facts, and absolute wording ("all", "every", "guaranteed"…).
8. **Fact check:** Claude Code reviews what's left against the facts.

## 4. `/seo-rewrite <brief>`: `draft.md` → `final.md` (`scripts/rewrite_sections.sh`)

1. **Editing:** Qwen at temperature 0.7 edits each part in order with `prompts/rewrite.md`. It fixes awkward keyword phrasing, cuts filler and repetition, and fixes the fact-checker's rejected issues.
   - Each call sees the parts already edited.
2. **`check.sh rewrite`** compares each edit with its input:
   - same headings;
   - 50–120% of the original length;
   - no numbers that aren't in the input or the facts;
   - no more absolute wording than before;
   - the call to action neither lost nor added to another part.
3. **Failures:** a failed edit is retried with seed 2. After a second failure the draft text is kept with a warning, and the run never stops.
4. **Second fact-check:** each accepted edit goes through the same fact-check pass again (`rewrite/NN-<heading>.verify.json`).
5. **Output:** the parts are joined into `final.md`, and `check.sh draft` runs against the real target.
6. **Final review:** Claude Code compares `final.md` with the facts.

## Shared pieces

- **`scripts/llm_call.sh`:** the only way to reach the model.
  - It always sends `prompts/system.md`, which says to use only the source facts.
  - It checks the router's context size before every call and requires at least 32,768 tokens.
  - `LLM_MODEL`, `LLM_MAX_TOKENS` and `LLM_TIMEOUT` change the model, output limit and timeout.
- **`scripts/fill_prompt.sh`:** fills every prompt from the brief, outline and source text, and fails if a placeholder is left unfilled.
- **`scripts/check.sh`:** holds every rule (brief, outline, section, draft, rewrite). A problem that must be fixed is a FAIL; one worth a look is a WARN.
- **`scripts/lib_parts.sh`:** shared by the loops and `check.sh`. It holds the fact-check pass, heading restore, bold removal, the absolute-wording pattern and the draft multiplier.
- **Models:** Qwen is the default everywhere. `VERIFY_MODEL=gemma` and `REWRITE_MODEL=gemma` switch those two stages; in the comparisons, Gemma was close but slightly worse.

## Typical run

```
/seo-ingest  briefs/client-page.pdf     # then review/edit briefs/client-page.json
/seo-outline briefs/client-page.json
/seo-draft   briefs/client-page.json
/seo-rewrite briefs/client-page.json    # read outputs/client-page/final.md
```

## What still needs a person

- **The brief.** The model sometimes overstates facts or turns design notes into facts.
- **Absolute claims** that the fact-checker flagged but couldn't safely fix. List them with:
  `jq -r '.issues[]? | select(.accepted == false) | .sentence' outputs/<slug>/*/*.verify.json`
- **Missed claims** in sections that kept their draft text, since those aren't fact-checked a second time.
