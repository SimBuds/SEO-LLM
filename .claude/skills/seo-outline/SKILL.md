---
name: seo-outline
description: Generate an SEO article outline (H1 + H2/H3 + intent notes + FAQ) from a JSON brief using the local llama.cpp router (model `qwen`). Phase 2 stage — outline only, no drafting. Use when the user runs /seo-outline <brief.json> or asks for an article outline from a brief.
---

# seo-outline

Generate a structured article outline from a JSON brief via the llama.cpp router. The outline is consumed by `/seo-draft` in the next stage.

## Inputs

- `$1` — path to a JSON brief (e.g. `briefs/example.json`). If missing, ask the user which brief to use.

## Preconditions

1. The llama.cpp router serves `qwen`: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen`. If it prints nothing or exits non-zero, tell the user the router on `localhost:8080` is not serving `qwen` and stop.
2. The brief passes `bash scripts/check.sh brief <brief.json>`. If it fails, show the FAIL line and stop.

## Steps

1. The slug is the brief's basename without `.json` (`briefs/test-brief.json` → `test-brief`). Outputs go to `outputs/<slug>/` (create it if needed).
2. Fill the prompt: `bash scripts/fill_prompt.sh prompts/outline.md --brief <brief.json> > outputs/<slug>/_outline_prompt.txt`
3. Run: `bash scripts/llm_call.sh outputs/<slug>/_outline_prompt.txt 0.3 1 > outputs/<slug>/outline.md`
4. Repair what is deterministically repairable, before checking:
   ```bash
   source scripts/lib_parts.sh && clean_outline outputs/<slug>/outline.md
   ```
   It drops `_Intent:` and `Keywords:` lines that are not directly under an H2,
   and any prose under a heading, printing every line it removed. Those are the
   two faults the model repeats, and three prompt wordings failed to stop them
   (see PLAN.md, Phases 24 and 25). Report what it removed rather than hiding it.
5. Check: `bash scripts/check.sh outline outputs/<slug>/outline.md <brief.json>`
6. Report: output path, topic H2 count, FAQ question count, anything the repair removed, and every FAIL/WARN line. If the check passed, suggest `/seo-draft <brief.json>`.

## Failure handling

- If `llm_call.sh` exits non-zero, surface the error and stop. Do not retry silently.
- If `check.sh outline` fails after the repair, the fault is structural (a missing FAQ or Conclusion, more than one H1, a section with no intent line) rather than stray lines. Report the FAIL lines and ask whether to regenerate. A rerun with the same seed usually repeats the output, so offer seed 2 (then 3) for the retry: `bash scripts/llm_call.sh outputs/<slug>/_outline_prompt.txt 0.3 2`.
- WARN lines do not block `/seo-draft`, but mention them.

## Out of scope

No drafting, no per-section calls, no rewrite, no metadata. Drafting from this outline is `/seo-draft`'s job (Phase 3+).
