---
name: seo-ingest
description: Extract a JSON brief from a source document (.docx, .pdf, .md, or .txt) using the local llama.cpp router (model `qwen`) so the user doesn't have to hand-write briefs. Phase 3 stage — sits before /seo-outline. Use when the user runs /seo-ingest <file> or supplies a doc/PDF instead of a JSON brief.
---

# seo-ingest

Convert a source document into a `briefs/<slug>.json` brief that the rest of the pipeline can consume.

## Inputs

- `$1` — path to a `.docx`, `.pdf`, `.md`, or `.txt` file. If missing, ask which file to ingest.

## Preconditions

1. The llama.cpp router serves `qwen`: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen`. If it prints nothing or exits non-zero, tell the user the router on `localhost:8080` is not serving `qwen` and stop.
2. For `.docx`: `pandoc` is on `PATH`. For `.pdf`: `pdftotext` is on `PATH` (from `poppler-utils`). If a required extractor is missing for the file type given, tell the user the apt/pacman package to install and stop.

## Steps

1. Inspect the file extension (lowercase). Reject anything other than `.docx`, `.pdf`, `.md`, `.txt` with a clear error.
2. Derive an output slug from the file's basename (lowercase, hyphens, no punctuation, no extension).
3. Extract plain text to `briefs/_ingest/<slug>.txt`:
   - `.docx` → `pandoc -t plain "<file>" -o briefs/_ingest/<slug>.txt`
   - `.pdf`  → `pdftotext -layout "<file>" briefs/_ingest/<slug>.txt`
   - `.md` / `.txt` → copy the file to `briefs/_ingest/<slug>.txt`
4. If the extracted text is empty or < 50 characters, stop and report the file likely has no text layer (PDFs may be scans — OCR is out of scope).
5. Read `prompts/ingest.md`. Substitute `{{SOURCE_TEXT}}` with the extracted text. If the text exceeds ~24 000 characters, truncate to the first 24 000 and append `\n\n[... source truncated for ingest ...]\n` so the model sees a clear boundary.
6. Write the filled prompt to `briefs/_ingest/<slug>.prompt.txt`.
7. Run: `bash scripts/llm_call.sh briefs/_ingest/<slug>.prompt.txt 0.2 1 prompts/brief.schema.json`. The schema argument makes the router return only a JSON object with the six brief keys.
8. Save stdout to `briefs/<slug>.json` as-is. Schema-constrained output carries no code fences, so nothing is stripped.
9. Validate: the following must exit 0. It checks exactly the six keys (`topic`, `target_audience`, `tone`, `word_count`, `keywords`, `cta`), non-empty strings, an integer `word_count`, and 3 to 6 non-empty keywords.
   ```
   jq -e '(keys == ["cta","keywords","target_audience","tone","topic","word_count"]) and all(.topic, .target_audience, .tone, .cta; type == "string" and length > 0) and (.word_count | type == "number" and . == floor and . >= 1) and (.keywords | type == "array" and length >= 3 and length <= 6 and all(.[]; type == "string" and length > 0))' briefs/<slug>.json
   ```
10. Report: source path, output brief path, the six extracted field values, and the instruction: *"Review/edit `briefs/<slug>.json`, then run `/seo-outline briefs/<slug>.json`."*

## Failure handling

- Extractor fails (non-zero exit): surface stderr, stop.
- The step 9 check exits non-zero (the JSON does not parse, or a key is missing, empty, or the wrong type): show the raw model output and which condition failed, ask whether to retry at temperature 0.1 or hand-fix.

## Out of scope

No OCR for scanned PDFs. No outline, draft, rewrite, or metadata — those are downstream skills. The user is expected to review the generated JSON before running `/seo-outline`.
