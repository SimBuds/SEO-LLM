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

# --- Phase 102: an input differing only in case, encoding or entity ---------
# Every run here uses the fake curl above, so nothing reaches the network or
# the router, and every tree is under $WORK.
export PATH="$V/bin:$PATH" LLM_HOST="http://127.0.0.1:9"
I="$WORK/inputs"
mkdir -p "$I"
printf 'Keyword\tVolume\ncat water fountain\t900\nquiet cat water fountain\t200\n' > "$I/utf8.csv"
iconv -f UTF-8 -t UTF-16 "$I/utf8.csv" > "$I/utf16le.csv"
{ printf '\xfe\xff'; iconv -f UTF-8 -t UTF-16BE "$I/utf8.csv"; } > "$I/utf16be.csv"
{ printf '\xef\xbb\xbf'; cat "$I/utf8.csv"; } > "$I/utf8bom.csv"
expect_eq "fixtures: the UTF-16 exports carry their byte order marks" "fffe feff" \
  "$(head -c 2 "$I/utf16le.csv" | od -An -tx1 | tr -d ' \n') $(head -c 2 "$I/utf16be.csv" | od -An -tx1 | tr -d ' \n')"

# collect <case> <export>: research_collect.sh on a page with only that export,
# rows in RESULT, exit code in RC
collect() {
  local d="$WORK/collect-$1"
  mkdir -p "$d/research/p/inputs"
  printf '%s\n' '{"exists": false}' > "$d/research/p/page.json"
  cp "$2" "$d/research/p/inputs/export.csv"
  RESEARCH_DIR="$d/research" bash scripts/research_collect.sh p > "$d/out.txt" 2>&1
  RC=$?
  RESULT=$(jq -c '[.keywords[] | {keyword, volume, sources}]' "$d/research/p/research.json" 2>&1)
}
collect utf8 "$I/utf8.csv"; WANT="$RESULT"
expect_eq "collect: a UTF-8 export parses (the reference)" "0 2" "$RC $(jq length <<< "$WANT" 2>&1)"
collect utf16le "$I/utf16le.csv"
expect_eq "collect: a UTF-16 LE export gives the same rows as the UTF-8 one" "0 $WANT" "$RC $RESULT"
collect utf16be "$I/utf16be.csv"
expect_eq "collect: a UTF-16 BE export gives the same rows as the UTF-8 one" "0 $WANT" "$RC $RESULT"
collect utf8bom "$I/utf8bom.csv"
expect_eq "collect: a UTF-8 export with a byte order mark is unchanged" "0 $WANT" "$RC $RESULT"

# An export named X.CSV is counted by every count, as research_collect.sh
# already parses it: the preflight, the intake and the collect stage's message.
U="$WORK/upper"
mkdir -p "$U/research/p/inputs" "$U/research/p/brief-stages" "$U/briefs/_ingest" "$U/outputs" "$U/fake"
printf '%s\n' '{"exists": false}' > "$U/research/p/page.json"
cp "$I/utf8.csv" "$U/research/p/inputs/EXPORT.CSV"
printf '%s\n' 'https://competitor.example/page' > "$U/research/p/competitors.txt"
echo "A guide." > "$U/research/p/brief-stages/purpose.txt"; : > "$U/research/p/type.txt"; : > "$U/research/p/suggested.txt"; : > "$U/briefs/_ingest/p.txt"
FAKE_REPLY="$V/reply.json" RESEARCH_DIR="$U/research" BRIEFS_DIR="$U/briefs" OUTPUTS_DIR="$U/outputs" \
  timeout 120 ./seo --auto p > "$U/auto.txt" 2>&1
expect_eq "count: the preflight counts EXPORT.CSV and the run collects it" "no yes" \
  "$(grep -qF 'no keyword export' "$U/auto.txt" && echo yes || echo no) $([[ -s "$U/research/p/research.json" ]] && echo yes || echo no)"
mkdir -p "$U/m/research/p/inputs" "$U/m/outputs"
cp "$U/research/p/page.json" "$U/research/p/competitors.txt" "$U/m/research/p/"
cp "$I/utf8.csv" "$U/m/research/p/inputs/EXPORT.CSV"
printf '2\n\nq\n' | timeout 120 script -qec "env PATH='$PATH' LLM_HOST='$LLM_HOST' RESEARCH_DIR='$U/m/research' BRIEFS_DIR='$U/briefs' OUTPUTS_DIR='$U/m/outputs' ./seo p" /dev/null > "$U/menu.txt" 2>&1
expect_eq "count: the intake does not ask again for an export that is there" "no" \
  "$(grep -qF 'Keyword exports to use' "$U/menu.txt" && echo yes || echo no)"
expect_eq "count: the collect stage reports the export it will read" "yes" \
  "$(grep -qF '(1 file(s) found)' "$U/menu.txt" && echo yes || echo no)"

# fetch_page.sh on a cached page, so no request is made: the cache holds the
# page and its robots.txt (a 404, so everything is allowed).
C="$WORK/cache"
mkdir -p "$C"
url="https://shop.example/page"; robots="https://shop.example/robots.txt"
k=$(printf '%s' "$url" | sha1sum | cut -c1-40); rk=$(printf '%s' "$robots" | sha1sum | cut -c1-40)
printf '%s\n' '<html><head><title>Cat Bowls &ndash; Feeders &hellip;</title></head><body><h1>Fountains &ndash; a guide</h1></body></html>' > "$C/$k.body"
echo "200 text/html; charset=utf-8" > "$C/$k.meta"
: > "$C/$rk.body"; echo "404 text/plain" > "$C/$rk.meta"
PAGE=$(FETCH_CACHE_DIR="$C" bash scripts/fetch_page.sh "$url" 2> "$C/fetch.err")   # stderr says "cache hit"
expect_eq "entities: &ndash; in a title is decoded" "Cat Bowls – Feeders &hellip;" "$(jq -r '.title' <<< "$PAGE" 2>&1)"
expect_eq "entities: &ndash; in a heading is decoded" "Fountains – a guide" "$(jq -r '.headings[0].text' <<< "$PAGE" 2>&1)"

# --- fill_prompt.sh: a --set-file value past the 128 KB argv limit ----------
# Phase 109. Linux caps one argv string at 128 KB, and the keyword and brief
# prompts carry research.json whole: at 550 keywords (121 KB) fill died with
# "Argument list too long".
printf 'A {{BIG}} Z\n' > "$WORK/big.tpl"
printf '%0200000d' 0 > "$WORK/big.txt"
OUT=$(bash scripts/fill_prompt.sh "$WORK/big.tpl" --set-file BIG="$WORK/big.txt" 2>&1)
expect_eq "fill: a 200 KB --set-file value fills in full" "200004" "$(printf '%s' "$OUT" | wc -c)"
printf 'A {{SMALL}} {{NAME}} Z\n' > "$WORK/small.tpl"; printf 'x\ny\n' > "$WORK/small.txt"
expect_eq "fill: a small value fills as before" "A x
y v Z" "$(bash scripts/fill_prompt.sh "$WORK/small.tpl" --set-file SMALL="$WORK/small.txt" --set NAME=v 2>&1)"
bash scripts/fill_prompt.sh "$WORK/small.tpl" --set NAME=v > /dev/null 2> "$WORK/fill.err"
expect_eq "fill: an unfilled placeholder still exits 1" "1 unfilled placeholders in $WORK/small.tpl: {{SMALL}}" "$? $(cat "$WORK/fill.err")"

echo
if (( FAILED )); then
  echo "$FAILED case(s) failed"
  exit 1
fi
echo "all cases passed"
