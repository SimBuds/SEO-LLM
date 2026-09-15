---
name: seo-outline
description: Generate an SEO article outline (H1 + H2/H3 + intent notes + FAQ) from a YAML brief using the local llama.cpp router (model `qwen`). Phase 2 stage — outline only, no drafting. Use when the user runs /seo-outline <brief.yaml> or asks for an article outline from a brief.
---

# seo-outline

Generate a structured article outline from a YAML brief via the llama.cpp router. The outline is consumed by `/seo-draft` in the next stage.

## Inputs

- `$1` — path to a YAML brief (e.g. `briefs/example.yaml`). If missing, ask the user which brief to use.

## Preconditions

1. The llama.cpp router serves `qwen`: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen`. If it prints nothing or exits non-zero, tell the user the router on `localhost:8080` is not serving `qwen` and stop.

## Steps

1. Read the brief. Extract: `topic`, `target_audience`, `tone`, `word_count`, `keywords` (list), `cta`.
2. Derive an output slug from `topic` (lowercase, hyphens, no punctuation).
3. Read `prompts/outline.md`. Substitute placeholders:
   - `{{TOPIC}}` → `topic`
   - `{{AUDIENCE}}` → `target_audience`
   - `{{TONE}}` → `tone`
   - `{{WORD_COUNT}}` → `word_count`
   - `{{KEYWORDS}}` → comma-joined keywords
   - `{{CTA}}` → `cta`
4. Write the filled prompt to `outputs/<slug>/_outline_prompt.txt`.
5. Run: `bash scripts/llm_call.sh outputs/<slug>/_outline_prompt.txt 0.3 1`
6. Save stdout to `outputs/<slug>/outline.md`.
7. Report: model used, output path, count of H2 sections, whether `## FAQ` and `## Conclusion` are present.

## Failure handling

- If the script exits non-zero, surface the error and stop. Do not retry silently.
- If the outline lacks `# ` H1, `## FAQ`, or `## Conclusion`, report which is missing and ask whether to regenerate.

## Out of scope

No drafting, no per-section calls, no rewrite, no metadata. Drafting from this outline is `/seo-draft`'s job (Phase 3+).
