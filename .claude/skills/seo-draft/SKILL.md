---
name: seo-draft
description: Generate an SEO article draft section by section from a JSON brief plus the outline produced by /seo-outline, using the local llama.cpp router (model `qwen`). One model call per outline section (intro, each H2, FAQ, conclusion), stitched into one markdown file. Use when the user runs /seo-draft <brief.json> or asks for an article draft from a brief.
---

# seo-draft

Draft an SEO article section by section from a JSON brief + outline via the llama.cpp router. `scripts/draft_sections.sh` does the loop; this skill runs it, checks the stitched result, and audits the facts.

## Inputs

- `$1` — path to a JSON brief (e.g. `briefs/example.json`). If missing, ask the user which brief to use.

## Preconditions

1. The llama.cpp router serves `qwen`: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen`. If it prints nothing or exits non-zero, tell the user the router on `localhost:8080` is not serving `qwen` and stop.
2. The brief passes `bash scripts/check.sh brief <brief.json>`. If it fails, show the FAIL line and stop.
3. `outputs/<slug>/outline.md` exists and passes `bash scripts/check.sh outline outputs/<slug>/outline.md <brief.json>`. If it is missing, tell the user to run `/seo-outline <brief.json>` first and stop. If the check fails, report it and stop.

## Steps

1. The slug is the brief's basename without `.json` (`briefs/test-brief.json` → `test-brief`).
2. Run: `bash scripts/draft_sections.sh <brief.json>` (add `--fresh` only when the user asks to redraft everything). The script:
   - splits the outline into an intro plus one block per H2, gives each a word budget, and keeps each primary keyword's cue in at most two parts;
   - fills `prompts/intro.md`, `prompts/section.md` (topic sections and FAQ), or `prompts/conclusion.md`, and makes one `llm_call.sh` call per part at temperature 0.5;
   - restores the outline's heading wording, strips bold, and runs `check.sh section`, retrying a failed part once with seed 2;
   - runs a fact-verification call on each passing part (`prompts/verify.md`, schema `prompts/verify.schema.json`, temperature 0.1, capped at 1500 tokens and 120 s). The call lists unsupported sentences with a replacement; replacements are applied as literal swaps unless rejected (sentence not found, holds the CTA, introduces new words, or a "strengthened" fix that drops over half the sentence). The report is `sections/NN-<heading>.verify.json`, the pre-verification text `sections/NN-<heading>.unverified.md`. `VERIFY_MODEL=gemma` switches the verifier model;
   - skips parts that already exist and pass (and have a verify report), and discards saved parts when the outline is newer than them;
   - stitches `outputs/<slug>/draft.md`.
3. Check: `bash scripts/check.sh draft outputs/<slug>/draft.md outputs/<slug>/outline.md <brief.json> 135`. The draft deliberately aims at 135% of `word_count` (`DRAFT_FACTOR`), because `/seo-rewrite` cuts it back toward the target.
4. List the verifier's rejected issues, which are still in the draft: `jq -r '.issues[] | select(.accepted | not) | "\(.reject): \(.sentence)"' outputs/<slug>/sections/*.verify.json`
5. Audit the draft yourself against the brief's `facts`: list every business specific in the draft (names, prices, timelines, policies, locations, materials, contact channels, who does what) that the facts do not state, and every place a fact was strengthened. Start from the rejected issues and the check's "absolute wording" list, then read the rest; the verifier misses some and sometimes leaves part of an invented claim in its replacement.
6. Report: per-part lines from the script (including the verify counts), total words against target, every FAIL/WARN line, and your fact-audit findings.

## Failure handling

- If a part fails twice, the script saves it as `outputs/<slug>/sections/NN-<heading>.ERROR.md`, prints the FAIL lines, and exits 1. Show those lines and the ERROR file's headings, and ask whether to rerun (it resumes at the failed part) or adjust the outline.
- A verification call that fails or times out leaves that part unverified with a WARN; rerunning the script retries it.
- If `llm_call.sh` exits non-zero inside the script, surface the error (the server's error body is on stderr) and stop. Do not retry silently.
- Report invented or strengthened facts as findings; do not edit the draft unless the user asks.

## Out of scope for this skill

No outline stage, no rewrite pass, no metadata. Those are separate skills added in later phases.
