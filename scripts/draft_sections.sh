#!/usr/bin/env bash
# Draft an article section by section from a brief and its outline.
# Usage: draft_sections.sh <brief.json> [--fresh]
# Reads outputs/<slug>/outline.md, where <slug> is the brief's basename.
# Writes outputs/<slug>/sections/NN-<heading>.md (00 is the intro) plus each
# part's .prompt.txt, then stitches them into outputs/<slug>/draft.md.
#
# Each part is one llm_call.sh call, checked with `check.sh section`. A failed
# check is retried at the next two seeds (DRAFT_SEED, default 1, then +1, +2); a
# third failure is saved as
# NN-<heading>.ERROR.md and the script stops with exit 1. Re-running skips
# parts that already exist and pass, so a stopped run resumes where it failed.
# --fresh, or an outline newer than the saved parts, discards them first.
#
# Env: OUTPUTS_DIR (default outputs) relocates the output tree.
# Each passing part then gets a fact-verification call (see verify_part).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIEF="${1:?brief required}"
FRESH="${2:-}"
TEMPERATURE=0.5
VERIFY_MODEL="${VERIFY_MODEL:-${LLM_MODEL:-qwen}}"
source "$ROOT/scripts/lib_parts.sh"

SLUG=$(basename "$BRIEF" .json)
# OUTPUTS_DIR relocates the whole output tree, the same variable scripts/seo.sh
# reads, so a test run can stay out of the repo's own outputs/.
OUT="${OUTPUTS_DIR:-$ROOT/outputs}/$SLUG"
OUTLINE="$OUT/outline.md"
SEC="$OUT/sections"
[[ -r "$OUTLINE" ]] || { echo "no outline at $OUTLINE; run /seo-outline first" >&2; exit 2; }

mkdir -p "$SEC"
# A part is stale when the outline is strictly newer than it. The old test was
# "not newer than the outline", which is also true when the two share a mtime to
# the second, so a copied or quickly rewritten tree discarded every part and
# redrafted the lot. Found 2026-09-22 while testing a single-part redo.
STALE=0
for _p in "$SEC"/*.md; do
  [[ -e "$_p" ]] || continue
  if [[ "$OUTLINE" -nt "$_p" ]]; then STALE=1; break; fi
done
if [[ "$FRESH" == "--fresh" ]] || (( STALE )); then
  rm -f "$SEC"/*
fi

grep -E '^#{1,3} ' "$OUTLINE" > "$SEC/_outline_headings.md"
H1=$(grep -m1 '^# ' "$OUTLINE")

# Split the outline into one block per H2: NN-<heading-slug>.block.md
awk -v dir="$SEC" '
  /^## / {
    n++
    slug = tolower(substr($0, 4)); gsub(/[^a-z0-9]+/, "-", slug)
    gsub(/^-+|-+$/, "", slug); slug = substr(slug, 1, 40); sub(/-+$/, "", slug)
    file = sprintf("%s/%02d-%s.block.md", dir, n, slug)
    printf "" > file
  }
  n && file { print > file }
' "$OUTLINE"

# Primary keywords: keep each one's cue in only the first two blocks that list
# it. Every block uses its cues, so an outline that repeats a keyword in five
# sections would otherwise put it in the draft five times.
declare -A SEEN
# The intro always uses the primary keyword, so it starts with one use.
SEEN[$(jq -r '.keywords[0]' "$BRIEF")]=1
for b in "$SEC"/*.block.md; do
  line=$(grep -m1 '^Keywords: ' "$b" || true)
  [[ -n "$line" ]] || continue
  kept=()
  IFS=',' read -ra cues <<< "${line#Keywords: }"
  for c in "${cues[@]}"; do
    c=$(sed -E 's/^ +| +$//g' <<< "$c")
    key=$(jq -r --arg c "$c" '.keywords[] | select(ascii_downcase == ($c | ascii_downcase))' "$BRIEF" | head -1)
    if [[ -n "$key" ]]; then
      SEEN[$key]=$(( ${SEEN[$key]:-0} + 1 ))
      (( SEEN[$key] <= 2 )) || continue
    fi
    kept+=("$c")
  done
  new="Keywords: $(IFS=','; echo "${kept[*]}" | sed 's/,/, /g')"
  # FAQ questions are fixed headings; cues there get stuffed into them.
  [[ ${#kept[@]} -gt 0 && "$(head -1 "$b")" != "## FAQ" ]] || new="Keywords: (none; no keyword needed in this section)"
  awk -v new="$new" '/^Keywords: / && !done {print new; done=1; next} {print}' "$b" > "$b.tmp" && mv "$b.tmp" "$b"
done

# Word budget: intro ~8%, conclusion ~6%, FAQ ~60 words per question (capped
# at 20%), the rest split across topic sections weighted by their H3 count.
# The rewrite pass cuts filler, so the draft aims above the brief's
# word_count by draft_factor percent (lib_parts.sh).
DRAFT_FACTOR=$(draft_factor "$(jq .word_count "$BRIEF")")
WC=$(( $(jq .word_count "$BRIEF") * DRAFT_FACTOR / 100 ))
round10() { echo $(( ($1 + 5) / 10 * 10 )); }
INTRO_W=$(( WC * 8 / 100 )); (( INTRO_W >= 60 )) || INTRO_W=60
CONC_W=$(( WC * 6 / 100 )); (( CONC_W >= 50 )) || CONC_W=50
declare -A BUDGET WEIGHT
FAQ_W=0 TOTAL_WEIGHT=0
for b in "$SEC"/*.block.md; do
  head1=$(head -1 "$b")
  h3=$(grep -c '^### ' "$b" || true)
  case "$head1" in
    "## FAQ") FAQ_W=$(( h3 * 60 )); (( FAQ_W <= WC * 20 / 100 )) || FAQ_W=$(( WC * 20 / 100 )); BUDGET[$b]=$FAQ_W ;;
    "## Conclusion") BUDGET[$b]=$CONC_W ;;
    *) w=$(( h3 > 0 ? h3 : 1 )); WEIGHT[$b]=$w; TOTAL_WEIGHT=$(( TOTAL_WEIGHT + w )) ;;
  esac
done
REST=$(( WC - INTRO_W - CONC_W - FAQ_W ))
for b in "${!WEIGHT[@]}"; do
  BUDGET[$b]=$(round10 $(( REST * WEIGHT[$b] / TOTAL_WEIGHT )))
done

# write_part <name> <template> <words> [block]
write_part() {
  local name=$1 template=$2 words=$3 block=${4:-}
  local out="$SEC/$name.md" prompt="$SEC/$name.prompt.txt"
  local check=(bash "$ROOT/scripts/check.sh" section "$out" "${block:--}" "$words" "$BRIEF")
  [[ -s "$out" ]] && unbold "$out"
  if [[ -s "$out" ]] && "${check[@]}" > /dev/null; then
    echo "skip $name (exists, passes)"
    verify_part "$name" "$out" "$SEC" "$block" "${check[@]}"
    return 0
  fi
  rm -f "$SEC/$name.verify.json" "$SEC/$name.unverified.md"
  local args=(--brief "$BRIEF" --set-file "OUTLINE_HEADINGS=$SEC/_outline_headings.md"
              --set "SECTION_WORDS=$words"
              --set "PRIMARY_KEYWORD=$(jq -r '.keywords[0]' "$BRIEF")")
  [[ -n "$block" ]] && args+=(--set-file "SECTION=$block")
  bash "$ROOT/scripts/fill_prompt.sh" "$ROOT/prompts/$template" "${args[@]}" > "$prompt"
  # DRAFT_SEED lets a deliberate redo resample: the same seed returns the same
  # text, so redoing a part at seed 1 would hand back what was just rejected.
  local seed
  # Three attempts, not two: the failures at different seeds have different
  # causes, so a second failure says little about a third. Measured 2026-09-22 on
  # a section with three H3s and a 400-word budget, where seed 1 came back 56%
  # over length and seed 2 fitted the budget by dropping a heading. Each attempt
  # is still judged by the same checks; nothing is relaxed.
  for seed in "${DRAFT_SEED:-1}" $(( ${DRAFT_SEED:-1} + 1 )) $(( ${DRAFT_SEED:-1} + 2 )); do
    bash "$ROOT/scripts/llm_call.sh" "$prompt" "$TEMPERATURE" "$seed" > "$out"
    [[ -n "$block" ]] && restore_headings "$block" "$out"
    unbold "$out"
    if "${check[@]}"; then
      echo "ok   $name ($(grep -v "^#" "$out" | wc -w) words, budget $words, seed $seed)"
      verify_part "$name" "$out" "$SEC" "$block" "${check[@]}"
      return 0
    fi
  done
  mv "$out" "$SEC/$name.ERROR.md"
  echo "failed $name twice; saved as sections/$name.ERROR.md" >&2
  exit 1
}

rm -f "$SEC"/*.ERROR.md
write_part 00-intro intro.md "$(round10 "$INTRO_W")"
for b in "$SEC"/*.block.md; do
  name=$(basename "$b" .block.md)
  case "$(head -1 "$b")" in
    "## Conclusion") write_part "$name" conclusion.md "$(round10 "${BUDGET[$b]}")" "$b" ;;
    *)               write_part "$name" section.md "$(round10 "${BUDGET[$b]}")" "$b" ;;
  esac
done

{
  printf '%s\n\n' "$H1"
  cat "$SEC/00-intro.md"
  for b in "$SEC"/*.block.md; do
    printf '\n\n'
    cat "$SEC/$(basename "$b" .block.md).md"
  done
  printf '\n'
} | cat -s > "$OUT/draft.md"

echo "stitched $OUT/draft.md ($(wc -w < "$OUT/draft.md") words, draft target $WC = $DRAFT_FACTOR% of $(jq .word_count "$BRIEF"))"
