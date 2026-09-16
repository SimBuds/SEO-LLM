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

## 1. `/seo-ingest <file>`: document → brief

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

## 2. `/seo-outline <brief>`: brief → outline

1. **Model call:** Qwen at temperature 0.3 writes headings only. Every section gets an `_Intent:` line and a `Keywords:` line.
2. **Size:** the number of topic sections depends on the word count: 2 to 3 up to 1,000 words, 3 to 5 up to 1,800, and 4 to 6 above that.
3. **`check.sh outline`:**
   - **Fails** on anything other than one H1, any body text, a missing FAQ or Conclusion, or a section without an intent line.
   - **Warns** on section or question counts outside the size table, subsections under the Conclusion, and keywords pasted into headings.
4. **Retry:** on a failure, Claude Code asks whether to regenerate with seed 2 (then 3). The same seed repeats the same outline. Warnings don't block the draft.

## 3. `/seo-draft <brief>`: outline → `draft.md` (`scripts/draft_sections.sh`)

1. **Preconditions:** the brief passes its check and `outline.md` exists and passes its check. Otherwise the run stops and asks for `/seo-outline` first.
2. **Split:** the outline becomes an intro plus one part per section, including the FAQ and the Conclusion.
3. **Budget:** the draft aims at **135%** of the word count, because the rewrite cuts it back. `DRAFT_FACTOR` overrides it.
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
7. **Output:** the parts are joined into `draft.md`. Rerunning skips parts that already passed. A newer outline or `--fresh` redoes everything.
8. **`check.sh draft … draft`:**
   - **Fails** if the headings don't match the outline or outline notes are left in.
   - **Warns** on length, keyword overuse, bold, numbers that aren't in the facts, and absolute wording ("all", "every", "guaranteed"…).
9. **Fact check:** Claude Code lists the fact-checker's rejected issues, which are still in the draft, then reviews the rest against the facts. It reports findings and doesn't edit the draft.

## 4. `/seo-rewrite <brief>`: `draft.md` → `final.md` (`scripts/rewrite_sections.sh`)

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

## Shared pieces

- **`scripts/llm_call.sh`:** the only way to reach the model.
  - It always sends `prompts/system.md`, which says to use only the source facts.
  - It checks the router's context size before every call and requires at least 32,768 tokens.
  - Thinking is off, and all sampling settings are fixed in the script.
  - `LLM_MODEL`, `LLM_MAX_TOKENS` and `LLM_TIMEOUT` change the model, output limit and timeout.
- **`scripts/fill_prompt.sh`:** fills every prompt from the brief, outline and source text, and fails if a placeholder is left unfilled.
- **`scripts/check.sh`:** holds every rule (brief, outline, section, draft, rewrite). A problem that must be fixed is a FAIL. One worth a look is a WARN.
- **`scripts/lib_parts.sh`:** shared by the loops and `check.sh`. It holds the fact-check pass, heading restore, bold removal, the absolute-wording pattern and the draft multiplier.
- **Models:** Qwen is the default everywhere. `VERIFY_MODEL=gemma` and `REWRITE_MODEL=gemma` switch those two stages. In the comparisons, Gemma was close but slightly worse.

## Settings at a glance

| Stage | Model | Temperature | Seed | Retry |
| --- | --- | --- | --- | --- |
| ingest | qwen | 0.2 | 1 | ask, then 0.1 |
| outline | qwen | 0.3 | 1 | ask, then seed 2 or 3 |
| draft part | qwen | 0.5 | 1 | automatic, seed 2 |
| fact check | qwen (`VERIFY_MODEL`) | 0.1 | 1 | on rerun |
| rewrite part | qwen (`REWRITE_MODEL`) | 0.7 | 1 | automatic, seed 2 |

## Typical run

```
/seo-ingest  briefs/client-page.pdf     # then review/edit briefs/client-page.json
/seo-outline briefs/client-page.json
/seo-draft   briefs/client-page.json
/seo-rewrite briefs/client-page.json    # read outputs/client-page/final.md
```

## Where files land

| Path | Stage | What it is |
| --- | --- | --- |
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

- **The brief.** The model sometimes overstates facts or turns design notes into facts.
- **Absolute claims** that the fact-checker flagged but couldn't safely fix. List them with:
  `jq -r '.issues[]? | select(.accepted == false) | .sentence' outputs/<slug>/*/*.verify.json`
- **Missed claims** in sections that kept their draft text, since those aren't fact-checked a second time.
- **Outlines for short pages** that have too many subsections. They push 800-word pages toward 940 words, so trim or regenerate the outline when `check.sh outline` warns.
