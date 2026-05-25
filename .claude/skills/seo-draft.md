---
name: seo-draft
description: Generate a single-pass SEO article draft from a YAML brief using a local Ollama model. Walking-skeleton stage — one prompt, one model call, one markdown file. Use when the user runs /seo-draft <brief.yaml> or asks for a first-pass article from a brief.
---

# seo-draft

Generate a first-pass SEO article from a YAML brief via Ollama.

## Inputs

- `$1` — path to a YAML brief (e.g. `briefs/example.yaml`). If missing, ask the user which brief to use.

## Preconditions (check before generating)

1. Ollama daemon is reachable: `curl -sS http://localhost:11434/api/tags | jq '.models | length'` returns ≥ 1.
2. The target model is pulled. Default model: `qwen-custom`. If not present in `ollama list`, tell the user to run `~/ai/build-qwen` (builds the `qwen-custom` tag) and stop.

## Steps

1. Read the brief file. Extract: `topic`, `target_audience`, `tone`, `word_count`, `keywords` (list), `cta`.
2. Derive an output slug from `topic` (lowercase, hyphens, no punctuation).
3. Read `prompts/section.md`. Substitute placeholders:
   - `{{BRIEF}}` → the topic line
   - `{{WORD_COUNT}}` → `word_count`
   - `{{TONE}}` → `tone`
   - `{{AUDIENCE}}` → `target_audience`
   - `{{KEYWORDS}}` → comma-joined keywords
   - `{{CTA}}` → `cta`
4. Write the filled prompt to `outputs/<slug>/_prompt.txt`.
5. Run: `bash scripts/ollama_call.sh qwen-custom outputs/<slug>/_prompt.txt 0.7 0`
6. Save stdout to `outputs/<slug>/draft.md`.
7. Report: model used, output path, word count of result, first H1 line.

## Failure handling

- If Ollama returns non-200 or the script exits non-zero, surface the error and stop. Do not retry silently.
- If the response is empty or < 200 words, report it and ask whether to retry with a different model or temperature.

## Out of scope for this skill

No outline stage, no per-section loop, no rewrite pass, no metadata. Those are separate skills added in later phases.
