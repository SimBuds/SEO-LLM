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

echo
if (( FAILED )); then
  echo "$FAILED case(s) failed"
  exit 1
fi
echo "all cases passed"
