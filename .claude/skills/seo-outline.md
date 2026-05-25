---
name: seo-outline
description: Generate an SEO article outline (H1 + H2/H3 + intent notes + FAQ) from a YAML brief using a local Ollama model. Phase 2 stage — outline only, no drafting. Use when the user runs /seo-outline <brief.yaml> or asks for an article outline from a brief.
---

# seo-outline

Generate a structured article outline from a YAML brief via Ollama. The outline is consumed by `/seo-draft` in the next stage.

## Inputs

- `$1` — path to a YAML brief (e.g. `briefs/example.yaml`). If missing, ask the user which brief to use.

## Preconditions

1. Ollama daemon reachable: `curl -sS http://localhost:11434/api/tags | jq '.models | length'` returns ≥ 1.
2. `qwen-custom` is present in `ollama list`. If missing, tell the user to run `~/ai/build-qwen` and stop.

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
5. Run: `bash scripts/ollama_call.sh qwen-custom outputs/<slug>/_outline_prompt.txt 0.3 1`
6. Save stdout to `outputs/<slug>/outline.md`.
7. Report: model used, output path, count of H2 sections, whether `## FAQ` and `## Conclusion` are present.

## Failure handling

- If the script exits non-zero, surface the error and stop. Do not retry silently.
- If the outline lacks `# ` H1, `## FAQ`, or `## Conclusion`, report which is missing and ask whether to regenerate.

## Out of scope

No drafting, no per-section calls, no rewrite, no metadata. Drafting from this outline is `/seo-draft`'s job (Phase 3+).
