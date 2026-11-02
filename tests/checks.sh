#!/usr/bin/env bash
# Pinning tests for the deterministic helpers and checks: scripts/lib_parts.sh
# and scripts/check.sh, run on fixtures. No router, no network.
#
# Usage: bash tests/checks.sh
#
# tests/auto_contract.sh covers what ./seo --auto promises a caller. This file
# covers the rules underneath it, which decide what counts as a number, a stub
# or a match. Prints PASS or FAIL per case and exits 1 if any case failed.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$ROOT" || exit 2
# shellcheck source=../scripts/lib_parts.sh
source "$ROOT/scripts/lib_parts.sh"

FAILED=0
# expect_eq <case> <expected> <actual>
expect_eq() {
  if [[ "$2" == "$3" ]]; then echo "PASS  $1"; else echo "FAIL  $1: expected [$2], got [$3]"; FAILED=$((FAILED + 1)); fi
}
# nums <text>: what numbers() finds in the text, space separated
nums() { printf '%s\n' "$1" | numbers | paste -sd' '; }

# --- numbers(): a digit run inside a word is part of a name -----------------
# Phase 96. "Everything4Cats" read as an invented 4 and failed every E4C page.

expect_eq "numbers: a digit inside a brand name is not a number" "" "$(nums 'Everything4Cats ships across Canada.')"
expect_eq "numbers: a digit ending a model name is not a number" "" "$(nums 'The MP3 player and the iPhone15 case.')"
expect_eq "numbers: a digit inside a formula is not a number" "" "$(nums 'Filtered H2O tastes better.')"
expect_eq "numbers: a number glued to its unit is still a number" "250 3 4" "$(nums 'Pour 250ml, rinse 3x, film in 4K.')"
expect_eq "numbers: money keeps its digits and loses its comma" "2500" "$(nums 'It costs $2,500.')"
expect_eq "numbers: a range is two numbers, as before" "4 6" "$(nums 'Every 4-6 weeks.')"
expect_eq "numbers: a decimal stays whole" "2.5" "$(nums 'About 2.5 litres.')"
expect_eq "numbers: a list marker is not a number" "" "$(nums '1. Unplug the pump.')"
expect_eq "numbers: a line with no digits gives nothing" "" "$(nums 'Clean the parts.')"
expect_eq "numbers: a hyphen is not a letter, so COVID-19 still gives 19" "19" "$(nums 'Since COVID-19.')"

# check.sh draft end to end: the brand in a draft no longer fails the numbers rule.
mkdir -p "$WORK/draft"
printf '%s\n' '# Choosing a Cat Water Fountain' '' '## How a Fountain Works' '_Intent: explain the pump_' '' \
  '## FAQ' '_Intent: answer questions_' '' '### How often should it be cleaned?' '' \
  '## Conclusion' '_Intent: sum up_' > "$WORK/draft/outline.md"
printf '%s\n' '# Choosing a Cat Water Fountain' '' 'Everything4Cats stocks quiet fountains.' '' \
  '## How a Fountain Works' '' 'A pump moves water through a filter.' '' \
  '## FAQ' '' '### How often should it be cleaned?' '' 'On a regular schedule.' '' \
  '## Conclusion' '' 'Visit a local jeweler for a private consultation.' > "$WORK/draft/draft.md"
bash scripts/check.sh draft "$WORK/draft/draft.md" "$WORK/draft/outline.md" briefs/example.json > "$WORK/draft/check.txt"
rc=$?
expect_eq "check.sh draft: a draft naming Everything4Cats has no FAIL line" "0 0" \
  "$rc $(grep -c '^FAIL' "$WORK/draft/check.txt")"

# --- verify_part: a stub replacement is a deletion --------------------------
# Phase 97. On the how-to page (its brief's one fact is used below, which is
# what let "parts" pass the new-words check) the fact checker replaced method sentences with
# "Clean the parts.", so final.md read "Clean the parts. Clean the parts." The
# replies below are the shapes it returned there. verify_part reaches the model
# through llm_call.sh, so a fake curl answers with the canned reply.
V="$WORK/verify"
mkdir -p "$V/bin" "$V/part"
cat > "$V/bin/curl" <<'FAKE'
#!/usr/bin/env bash
url=""; for a in "$@"; do [[ "$a" =~ ^https?:// ]] && url="$a"; done
case "$url" in
  */models) printf '%s\n' '{"data":[{"id":"qwen","status":{"value":"loaded"},"meta":{"n_ctx":65536}}]}' ;;
  */v1/chat/completions) cat > /dev/null; jq -n --rawfile c "$FAKE_REPLY" '{choices: [{message: {content: $c}}]}' ;;
  *) echo "fake curl: unexpected URL $url" >&2; exit 99 ;;
esac
FAKE
chmod +x "$V/bin/curl"
jq '.facts = ["Soak removable parts for about 15 to 20 minutes."]' briefs/example.json > "$V/brief.json"
S_STUB1="After the soak, use a soft brush or an old toothbrush to clean each piece."
S_STUB2="For the pump mechanism, ensure the small holes are clear of hair or dust."
S_EMPTY="This method ensures your device operates efficiently and keeps the water fresh for your cat."
S_KEEP="Rinse the filter under running water."
S_HALF="The pump runs quietly at night in most homes."
S_STRONG="Reassemble the fountain only when every component is completely dry and clean."
S_NEW="Make sure no soap residue remains in the basin before refilling."
S_CTA="Visit a local jeweler for a private consultation."
printf '%s\n' "$S_STUB1 $S_STUB2 $S_EMPTY $S_KEEP $S_HALF $S_STRONG $S_NEW $S_CTA" > "$V/part/03-steps.md"
jq -n --arg a "$S_STUB1" --arg b "$S_STUB2" --arg c "$S_EMPTY" --arg d "$S_HALF" --arg e "$S_STRONG" --arg f "$S_NEW" --arg g "$S_CTA" '{issues: [
  {kind: "invented", sentence: $a, problem: "method not in facts", replacement: "Clean the parts."},
  {kind: "invented", sentence: $b, problem: "method not in facts", replacement: "Clean the parts."},
  {kind: "invented", sentence: $c, problem: "claim not in facts", replacement: ""},
  {kind: "invented", sentence: $d, problem: "frequency not in facts", replacement: "The pump runs quietly at night."},
  {kind: "strengthened", sentence: $e, problem: "overstated", replacement: "Reassemble the fountain."},
  {kind: "invented", sentence: $f, problem: "detail not in facts", replacement: "Wipe the parts with vinegar."},
  {kind: "invented", sentence: $g, problem: "call to action", replacement: "Visit."}]}' > "$V/reply.json"
(
  export PATH="$V/bin:$PATH" LLM_HOST="http://127.0.0.1:9" FAKE_REPLY="$V/reply.json"
  BRIEF="$V/brief.json" VERIFY_MODEL=qwen
  verify_part 03-steps "$V/part/03-steps.md" "$V/part" "" true
) > "$V/verify.out" 2>&1
TEXT=$(cat "$V/part/03-steps.md")
has() { [[ "$TEXT" == *"$1"* ]] && echo yes || echo no; }
expect_eq "verify_part: a replacement keeping under half its sentence deletes it, no stub left" "no no no" \
  "$(has "Clean the parts.") $(has "$S_STUB1") $(has "$S_STUB2")"
expect_eq "verify_part: an empty replacement still deletes the sentence" "no" "$(has "$S_EMPTY")"
expect_eq "verify_part: a sentence with no issue is untouched" "yes" "$(has "$S_KEEP")"
expect_eq "verify_part: a replacement keeping half or more is applied as written" "yes no" \
  "$(has "The pump runs quietly at night.") $(has "$S_HALF")"
expect_eq "verify_part: a strengthened fix dropping over half is still rejected, the sentence kept" "yes no" \
  "$(has "$S_STRONG") $(has "Reassemble the fountain. ")"
expect_eq "verify_part: a replacement bringing new words is still rejected" "yes no" \
  "$(has "$S_NEW") $(has "vinegar")"
expect_eq "verify_part: the CTA sentence is never touched" "yes" "$(has "$S_CTA")"
expect_eq "verify_part: the report keeps each stub it turned into a deletion" "2" \
  "$(jq '[.issues[] | select(.accepted and .replacement == "" and .stub == "Clean the parts.")] | length' "$V/part/03-steps.verify.json" 2>&1)"

echo
if (( FAILED )); then
  echo "$FAILED case(s) failed"
  exit 1
fi
echo "all cases passed"
