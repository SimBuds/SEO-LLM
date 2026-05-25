---
name: seo-ingest
description: Extract a YAML brief from a source document (.docx, .pdf, .md, or .txt) using a local Ollama model so the user doesn't have to hand-write briefs. Phase 3 stage — sits before /seo-outline. Use when the user runs /seo-ingest <file> or supplies a doc/PDF instead of a YAML brief.
---

# seo-ingest

Convert a source document into a `briefs/<slug>.yaml` brief that the rest of the pipeline can consume.

## Inputs

- `$1` — path to a `.docx`, `.pdf`, `.md`, or `.txt` file. If missing, ask which file to ingest.

## Preconditions

1. Ollama daemon reachable: `curl -sS http://localhost:11434/api/tags | jq '.models | length'` returns ≥ 1.
2. `qwen-custom` present in `ollama list`. If missing, tell the user to run `~/ai/build-qwen` and stop.
3. For `.docx`: `pandoc` is on `PATH`. For `.pdf`: `pdftotext` is on `PATH` (from `poppler-utils`). If a required extractor is missing for the file type given, tell the user the apt/pacman package to install and stop.

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
7. Run: `bash scripts/ollama_call.sh qwen-custom briefs/_ingest/<slug>.prompt.txt 0.2 1`
8. Save stdout to `briefs/<slug>.yaml`. If the model wrapped the YAML in a ```yaml fence anyway, strip the fences before saving.
9. Validate with `yq '.' briefs/<slug>.yaml > /dev/null` and confirm every required key (`topic`, `target_audience`, `tone`, `word_count`, `keywords`, `cta`) is present.
10. Report: source path, output brief path, the six extracted field values, and the instruction: *"Review/edit `briefs/<slug>.yaml`, then run `/seo-outline briefs/<slug>.yaml`."*

## Failure handling

- Extractor fails (non-zero exit): surface stderr, stop.
- YAML doesn't parse with `yq`: show the raw model output, ask whether to retry at temperature 0.1 or hand-fix.
- A required key is missing or empty after parse: report which, ask whether to retry or hand-fill.

## Out of scope

No OCR for scanned PDFs. No outline, draft, rewrite, or metadata — those are downstream skills. The user is expected to review the generated YAML before running `/seo-outline`.
