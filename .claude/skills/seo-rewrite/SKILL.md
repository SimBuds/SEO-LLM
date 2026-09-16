---
name: seo-rewrite
description: Edit a section-by-section SEO draft for readability (natural keyword phrasing, less filler and repetition) without changing its facts or structure, using the local llama.cpp router. Phase 5 stage — runs after /seo-draft and writes final.md. Use when the user runs /seo-rewrite <brief.json> or asks to polish, humanize, or finalize a draft.
---

# seo-rewrite

Polish a drafted article part by part. `scripts/rewrite_sections.sh` does the loop; this skill runs it, checks the stitched result, and compares it with the draft.

## Inputs

- `$1` — path to a JSON brief (e.g. `briefs/example.json`). If missing, ask the user which brief to use.

## Preconditions

1. The llama.cpp router serves the rewrite model: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen` (or the model named in `REWRITE_MODEL`). If not, tell the user and stop.
2. `outputs/<slug>/sections/00-intro.md` exists and there is no `outputs/<slug>/sections/*.ERROR.md`. Otherwise tell the user to run `/seo-draft <brief.json>` first and stop.

## Steps

1. The slug is the brief's basename without `.json`.
2. Run: `bash scripts/rewrite_sections.sh <brief.json>` (add `--fresh` only when the user asks to redo every part; prefix `REWRITE_MODEL=gemma` when the user asks for Gemma). The script edits each part in order with `prompts/rewrite.md` at temperature 0.7, giving each call the parts already edited and the verifier's rejected issues for that part; checks each edit with `check.sh rewrite` (same headings, 50–120% length, no CTA added to other parts, no new numbers, no more absolute-wording sentences, CTA kept); retries once with seed 2; keeps the unedited part with a WARN after a second failure; and stitches `outputs/<slug>/final.md`.
3. Check: `bash scripts/check.sh draft outputs/<slug>/final.md outputs/<slug>/outline.md <brief.json>`
4. Compare `final.md` with `draft.md`: note which rejected verifier issues were fixed, any claim in `final.md` that the brief's `facts` do not support, and whether awkward keyword phrasing and repetition improved.
5. Report: per-part lines from the script, every WARN (including parts that kept unedited text), the check output, and your comparison.

## Failure handling

- A part whose rewrite fails its check twice keeps its drafted text; report it, do not retry silently beyond the script's one retry.
- If `llm_call.sh` fails for both seeds of a part, the script warns and keeps the drafted text; report the error.
- Do not edit `final.md` by hand unless the user asks.

## Out of scope

No redrafting (that is `/seo-draft`), no metadata or keywords (Phase 6).
