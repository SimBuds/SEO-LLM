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
2. Derive the slug from the file's basename (lowercase, hyphens, no punctuation, no extension).
3. If `briefs/<slug>.json` already exists, show it and ask before overwriting: the user may have edited it. Stop unless they confirm.
4. Extract plain text to `briefs/_ingest/<slug>.txt` (create `briefs/_ingest/` if needed):
   - `.docx` → `pandoc -t plain "<file>" -o briefs/_ingest/<slug>.txt`
   - `.pdf`  → `pdftotext -layout "<file>" briefs/_ingest/<slug>.txt`
   - `.md` / `.txt` → copy the file to `briefs/_ingest/<slug>.txt`
5. If the extracted text is empty or < 50 characters, stop and report the file likely has no text layer (PDFs may be scans — OCR is out of scope).
6. Fill the prompt: `bash scripts/fill_prompt.sh prompts/ingest.md --source briefs/_ingest/<slug>.txt > briefs/_ingest/<slug>.prompt.txt`. The script squeezes layout whitespace and cuts the text at 24 000 characters with a visible marker; if it prints `source truncated`, say so in the report.
7. Run: `bash scripts/llm_call.sh briefs/_ingest/<slug>.prompt.txt 0.2 1 prompts/brief.schema.json > briefs/<slug>.json`. The schema argument makes the router return only a JSON object with the seven brief keys, so nothing needs stripping.
8. Check: `bash scripts/check.sh brief briefs/<slug>.json briefs/_ingest/<slug>.txt`. It fails on a schema mismatch and warns on UI-referencing CTAs, weak keywords, an empty facts list, and fact numbers that do not appear in the source.
9. Audit the facts yourself against `briefs/_ingest/<slug>.txt`: the model sometimes adds details, strengthens wording, or turns design/UI instructions into facts. List any fact that is not stated in the source.
10. Report: source path, output brief path, topic, audience, tone, word_count, keywords, cta, the facts list, every WARN line, and your fact-audit findings, then: *"Review/edit `briefs/<slug>.json`, then run `/seo-outline briefs/<slug>.json`."*

## Failure handling

- Extractor fails (non-zero exit): surface stderr, stop.
- `check.sh brief` exits non-zero: show the raw model output and the FAIL line, and ask whether to retry at temperature 0.1 or hand-fix.
- Do not fix facts or keywords silently. Propose the edits and let the user decide.

## Out of scope

No OCR for scanned PDFs. No outline, draft, rewrite, or metadata — those are downstream skills. The user is expected to review the generated JSON before running `/seo-outline`.
