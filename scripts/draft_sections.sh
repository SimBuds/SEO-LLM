#!/usr/bin/env bash
# Draft an article section by section from a brief and its outline.
# Usage: draft_sections.sh <brief.json> [--fresh]
# Reads outputs/<slug>/outline.md, where <slug> is the brief's basename.
# Writes outputs/<slug>/sections/NN-<heading>.md (00 is the intro) plus each
# part's .prompt.txt, then stitches them into outputs/<slug>/draft.md.
#
# Each part is one llm_call.sh call, checked with `check.sh section`. A failed
# check is retried once with seed 2; a second failure is saved as
# NN-<heading>.ERROR.md and the script stops with exit 1. Re-running skips
# parts that already exist and pass, so a stopped run resumes where it failed.
# --fresh, or an outline newer than the saved parts, discards them first.
# Each passing part then gets a fact-verification call (see verify_part).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIEF="${1:?brief required}"
FRESH="${2:-}"
TEMPERATURE=0.5
VERIFY_MODEL="${VERIFY_MODEL:-${LLM_MODEL:-qwen}}"
# Kept in sync with the absolute-wording warning in check.sh.
ABSOLUTE_SENTENCE='[^.!?]*\b(all|every|always|never|guarantee[sd]?|any circumstances|complete control|entirely|without compromise)\b[^.!?]*[.!?]'

SLUG=$(basename "$BRIEF" .json)
OUT="$ROOT/outputs/$SLUG"
OUTLINE="$OUT/outline.md"
SEC="$OUT/sections"
[[ -r "$OUTLINE" ]] || { echo "no outline at $OUTLINE; run /seo-outline first" >&2; exit 2; }

mkdir -p "$SEC"
if [[ "$FRESH" == "--fresh" ]] || [[ -n "$(find "$SEC" -maxdepth 1 -name '*.md' ! -newer "$OUTLINE" -print -quit)" ]]; then
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
# The rewrite pass cuts filler and lands near 70% of the draft, so the draft
# aims above the brief's word_count. DRAFT_FACTOR is a percentage.
DRAFT_FACTOR="${DRAFT_FACTOR:-135}"
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

# restore_headings <block> <part>: headings are fixed by the outline, but the
# model rewords them (often stuffing keywords in). When the part has the same
# number of headings at the same levels, put the outline's wording back.
# Anything else is left for check.sh to fail.
restore_headings() {
  local block=$1 part=$2
  [[ "$(grep -oE '^#{1,6} ' "$block")" == "$(grep -oE '^#{1,6} ' "$part")" ]] || return 0
  awk 'NR == FNR { if ($0 ~ /^#{1,6} /) h[++n] = $0; next }
       /^#{1,6} / { print h[++i]; next } { print }' "$block" "$part" > "$part.tmp"
  mv "$part.tmp" "$part"
}

# unbold <part>: the prompts never ask for bold, but the model bolds keyword
# phrases anyway. Strip bold from every non-heading line.
unbold() {
  sed -i -E '/^#/!s/\*\*([^*]+)\*\*/\1/g' "$1"
}

# verify_part <name> <out> <check...>: a second call lists sentences the
# facts do not support (prompts/verify.md, schema-constrained) with a
# replacement for each. Replacements are applied as literal string swaps, and
# the report is kept as <name>.verify.json. The unverified text is kept as
# <name>.unverified.md; if the verified part fails its check, it is restored.
verify_part() {
  local name=$1 out=$2; shift 2
  local report="$SEC/$name.verify.json" prompt="$SEC/$name.verify.prompt.txt"
  local orig="$SEC/$name.unverified.md"
  [[ -s "$report" ]] && return 0
  if (( $(jq '.facts | length' "$BRIEF") == 0 )); then
    echo '{"issues": [], "skipped": "brief has no facts"}' > "$report"; return 0
  fi
  cp "$out" "$orig"
  local suspects
  suspects=$(grep -v '^#' "$orig" | grep -oiE "$ABSOLUTE_SENTENCE" | sed 's/^ */- /' || true)
  bash "$ROOT/scripts/fill_prompt.sh" "$ROOT/prompts/verify.md" --brief "$BRIEF" \
    --set-file "SECTION_TEXT=$orig" --set "SUSPECTS=${suspects:-(none)}" > "$prompt"
  if ! LLM_MODEL="$VERIFY_MODEL" LLM_MAX_TOKENS=1500 LLM_TIMEOUT=120 \
      bash "$ROOT/scripts/llm_call.sh" "$prompt" 0.1 1 \
      "$ROOT/prompts/verify.schema.json" > "$report.tmp"; then
    rm -f "$report.tmp" "$orig"
    echo "WARN: $name verification call failed or ran away; part left unverified (rerun to retry)" >&2
    return 0
  fi
  # A replacement may only use words from its sentence or the facts; one that
  # brings in new words ("guarantees" -> "ensures") is marked rejected and not
  # applied. Words compare by their first four letters so that inflections
  # (piece/pieces, commission/commissioned) pass.
  # Also rejected: edits to a sentence holding the CTA, and "strengthened"
  # fixes that drop more than half the sentence (the claim was widened, so a
  # correct fix narrows it rather than gutting it). Deleting an invented
  # sentence outright stays allowed.
  jq --rawfile t "$orig" --argjson b "$(jq -c . "$BRIEF")" '
    def stems: ascii_downcase | [scan("[a-z]{4,}") | .[0:4]] | unique;
    def nwords: [scan("\\S+")] | length;
    ($b.facts | join(" ") | stems) as $fw
    | .issues |= map(
        select(.kind != "supported" and .replacement != .sentence)
        | .sentence as $s | . + {found: ($t | contains($s))}
        | . + {new_words: ((.replacement | stems) - (.sentence | stems) - $fw)}
        | . + {reject: (
            if (.found | not) then "sentence not found"
            elif (.sentence | contains($b.cta)) then "holds the CTA"
            elif (.new_words | length) > 0 then "new words"
            elif .kind == "strengthened" and ((.replacement | nwords) * 2 < (.sentence | nwords)) then "drops over half"
            else null end)}
        | . + {accepted: (.reject == null)})
  ' "$report.tmp" > "$report"
  rm -f "$report.tmp"
  jq -rj --rawfile t "$orig" '
    [.issues[] | select(.accepted)]
    | reduce .[] as $i ($t; split($i.sentence) | join($i.replacement))
  ' "$report" | sed -E 's/ {2,}/ /g; s/ +([.,;:])/\1/g; s/^ +//' > "$out"
  [[ -n "${block:-}" ]] && restore_headings "$block" "$out"
  local total applied rejected
  total=$(jq '.issues | length' "$report")
  applied=$(jq '[.issues[] | select(.accepted)] | length' "$report")
  rejected=$(jq '[.issues[] | select(.accepted | not)] | length' "$report")
  if ! "$@" > /dev/null; then
    cp "$orig" "$out"
    echo "WARN: $name failed its check after verification; kept the unverified text" >&2
    return 0
  fi
  echo "     verify $name ($VERIFY_MODEL): $total flagged, $applied applied, $rejected rejected"
}

# write_part <name> <template> <words> [block]
write_part() {
  local name=$1 template=$2 words=$3 block=${4:-}
  local out="$SEC/$name.md" prompt="$SEC/$name.prompt.txt"
  local check=(bash "$ROOT/scripts/check.sh" section "$out" "${block:--}" "$words" "$BRIEF")
  [[ -s "$out" ]] && unbold "$out"
  if [[ -s "$out" ]] && "${check[@]}" > /dev/null; then
    echo "skip $name (exists, passes)"
    verify_part "$name" "$out" "${check[@]}"
    return 0
  fi
  rm -f "$SEC/$name.verify.json" "$SEC/$name.unverified.md"
  local args=(--brief "$BRIEF" --set-file "OUTLINE_HEADINGS=$SEC/_outline_headings.md"
              --set "SECTION_WORDS=$words"
              --set "PRIMARY_KEYWORD=$(jq -r '.keywords[0]' "$BRIEF")")
  [[ -n "$block" ]] && args+=(--set-file "SECTION=$block")
  bash "$ROOT/scripts/fill_prompt.sh" "$ROOT/prompts/$template" "${args[@]}" > "$prompt"
  local seed
  for seed in 1 2; do
    bash "$ROOT/scripts/llm_call.sh" "$prompt" "$TEMPERATURE" "$seed" > "$out"
    [[ -n "$block" ]] && restore_headings "$block" "$out"
    unbold "$out"
    if "${check[@]}"; then
      echo "ok   $name ($(grep -v "^#" "$out" | wc -w) words, budget $words, seed $seed)"
      verify_part "$name" "$out" "${check[@]}"
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
