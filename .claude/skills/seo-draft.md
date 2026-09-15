---
name: seo-draft
description: Generate an SEO article draft from a YAML brief plus a pre-generated outline using the local llama.cpp router (model `qwen`). Phase 2 stage — one prompt, one model call, one markdown file, but now grounded in the outline produced by /seo-outline. Use when the user runs /seo-draft <brief.yaml> or asks for an article draft from a brief.
---

# seo-draft

Generate a draft SEO article from a YAML brief + outline via the llama.cpp router.

## Inputs

- `$1` — path to a YAML brief (e.g. `briefs/example.yaml`). If missing, ask the user which brief to use.

## Preconditions (check before generating)

1. The llama.cpp router serves `qwen`: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen`. If it prints nothing or exits non-zero, tell the user the router on `localhost:8080` is not serving `qwen` and stop.
2. An outline exists at `outputs/<slug>/outline.md`. If missing, tell the user to run `/seo-outline <brief.yaml>` first and stop.

## Steps

1. Read the brief file. Extract: `topic`, `target_audience`, `tone`, `word_count`, `keywords` (list), `cta`.
2. Derive an output slug from `topic` (lowercase, hyphens, no punctuation).
3. Read `outputs/<slug>/outline.md` (must exist — see precondition 2).
4. Read `prompts/section.md`. Substitute placeholders:
   - `{{BRIEF}}` → the topic line
   - `{{OUTLINE}}` → full contents of `outputs/<slug>/outline.md`
   - `{{WORD_COUNT}}` → `word_count`
   - `{{TONE}}` → `tone`
   - `{{AUDIENCE}}` → `target_audience`
   - `{{KEYWORDS}}` → comma-joined keywords
   - `{{CTA}}` → `cta`
5. Write the filled prompt to `outputs/<slug>/_prompt.txt`.
6. Run: `bash scripts/llm_call.sh outputs/<slug>/_prompt.txt 0.7 0`
7. Save stdout to `outputs/<slug>/draft.md`.
8. Report: model used, output path, word count of result, first H1 line, and whether the draft's H2 headings match the outline's H2 headings.

## Failure handling

- If the router returns an HTTP error or the script exits non-zero, surface the error (the script prints the server's error body to stderr) and stop. Do not retry silently.
- If the response is empty or < 200 words, report it and ask whether to retry with a different model or temperature.

## Out of scope for this skill

No outline stage, no per-section loop, no rewrite pass, no metadata. Those are separate skills added in later phases.
