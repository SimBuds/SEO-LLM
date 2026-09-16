#!/usr/bin/env bash
# Edit a section-by-section draft for readability, part by part.
# Usage: rewrite_sections.sh <brief.json> [--fresh]
# Reads outputs/<slug>/sections/NN-<heading>.md (written by draft_sections.sh)
# and writes outputs/<slug>/rewrite/NN-<heading>.md plus each .prompt.txt,
# then stitches outputs/<slug>/final.md.
#
# Parts are edited in order; each call sees the parts already edited, so it
# can avoid repeating them, and the verifier's rejected issues for its part.
# Each edit is checked with `check.sh rewrite` against its input (same
# headings, similar length, no new numbers, no new absolute wording, CTA kept)
# and retried once with seed 2. A part that fails twice keeps its unedited
# text, with a WARN; the rewrite is polish, so it never stops the run.
# Every edited part then gets the same fact-verification call as the draft
# (verify_part in lib_parts.sh), because an edit can reintroduce or reword a
# claim. REWRITE_MODEL picks the model (default qwen). Re-running skips parts whose
# edit is newer than its input and passes; --fresh redoes every part.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIEF="${1:?brief required}"
FRESH="${2:-}"
MODEL="${REWRITE_MODEL:-qwen}"
VERIFY_MODEL="${VERIFY_MODEL:-qwen}"
TEMPERATURE=0.7
source "$ROOT/scripts/lib_parts.sh"

SLUG=$(basename "$BRIEF" .json)
OUT="$ROOT/outputs/$SLUG"
SEC="$OUT/sections"
RW="$OUT/rewrite"
[[ -s "$SEC/00-intro.md" ]] || { echo "no drafted sections in $SEC; run /seo-draft first" >&2; exit 2; }
if compgen -G "$SEC/*.ERROR.md" > /dev/null; then
  echo "draft has failed parts ($SEC/*.ERROR.md); rerun /seo-draft first" >&2; exit 2
fi

mkdir -p "$RW"
[[ "$FRESH" == "--fresh" ]] && rm -f "$RW"/*

PARTS=(00-intro)
for b in "$SEC"/*.block.md; do PARTS+=("$(basename "$b" .block.md)"); done

EARLIER="$RW/_earlier.md"
: > "$EARLIER"

for name in "${PARTS[@]}"; do
  in="$SEC/$name.md" out="$RW/$name.md" prompt="$RW/$name.prompt.txt"
  check=(bash "$ROOT/scripts/check.sh" rewrite "$out" "$in" "$BRIEF")
  if [[ -s "$out" && "$out" -nt "$in" ]] && "${check[@]}" > /dev/null; then
    echo "skip $name (edited, passes)"
    verify_part "$name" "$out" "$RW" "$in" "${check[@]}"
  else
    rm -f "$RW/$name.verify.json" "$RW/$name.unverified.md" "$RW/$name".rejected-seed*.md
    problems="(none)"
    if [[ -s "$SEC/$name.verify.json" ]]; then
      p=$(jq -r '.issues[]? | select(.accepted == false and .found) | "- \"\(.sentence)\" — \(.problem)"' "$SEC/$name.verify.json")
      [[ -z "$p" ]] || problems="$p"
    fi
    bash "$ROOT/scripts/fill_prompt.sh" "$ROOT/prompts/rewrite.md" --brief "$BRIEF" \
      --set-file "SECTION_TEXT=$in" \
      --set "EARLIER=$( [[ -s "$EARLIER" ]] && cat "$EARLIER" || echo '(none yet; this is the opening)')" \
      --set "PROBLEMS=$problems" > "$prompt"
    ok=0
    for seed in 1 2; do
      if ! LLM_MODEL="$MODEL" LLM_MAX_TOKENS=2500 LLM_TIMEOUT=180 \
          bash "$ROOT/scripts/llm_call.sh" "$prompt" "$TEMPERATURE" "$seed" > "$out"; then
        echo "WARN: $name rewrite call failed (seed $seed)" >&2; continue
      fi
      restore_headings "$in" "$out"
      unbold "$out"
      if "${check[@]}"; then ok=1; break; fi
      cp "$out" "$RW/$name.rejected-seed$seed.md"
    done
    if (( ok )); then
      echo "ok   $name ($MODEL, $(grep -v '^#' "$in" | wc -w) -> $(grep -v '^#' "$out" | wc -w) words, seed $seed)"
      verify_part "$name" "$out" "$RW" "$in" "${check[@]}"
    else
      cp "$in" "$out"
      # The drafted text was verified already; record that instead of re-checking.
      echo '{"issues": [], "skipped": "kept drafted text, verified in sections/"}' > "$RW/$name.verify.json"
      echo "WARN: $name kept its unedited text; the rewrite failed its check twice" >&2
    fi
  fi
  { cat "$out"; printf '\n\n'; } >> "$EARLIER"
done

{
  grep -m1 '^# ' "$OUT/outline.md"
  printf '\n'
  for name in "${PARTS[@]}"; do cat "$RW/$name.md"; printf '\n\n'; done
} | cat -s > "$OUT/final.md"

echo "stitched $OUT/final.md ($(wc -w < "$OUT/final.md") words)"
