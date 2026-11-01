#!/usr/bin/env bash
# Pinning tests for what ./seo --auto promises a caller: which file a failed
# stage leaves behind, and the exit code it ends with.
#
# Usage: bash tests/auto_contract.sh
#
# No router, no network, no GPU. A fake `curl` first on PATH answers /models as a
# router serving qwen and answers each chat call from FAKE_POST, so a router
# failure can be staged at any call. LLM_HOST points at a closed local port, so a
# real curl that slipped past the fake fails with 7 rather than reaching the
# router on 8080. Every run writes to a scratch tree through RESEARCH_DIR,
# BRIEFS_DIR and OUTPUTS_DIR, and the tree is removed on exit.
#
# Prints PASS or FAIL per case and exits 1 if any case failed.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
SLUG=contract-page

for tool in jq script timeout; do
  command -v "$tool" > /dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done

# --- the fake router -------------------------------------------------------
# FAKE_POST and FAKE_MODELS are comma lists, one entry per call in order, the
# last entry repeating. A POST entry is down (curl 7), noload (HTTP 500, the
# model failed to load), toobig (HTTP 400, prompt over the context) or
# reply:<file> (the file's text as the model's reply). A /models entry is ok or
# down. Counters live in FAKE_DIR so each run starts from call 1.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<'FAKE'
#!/usr/bin/env bash
url=""
for a in "$@"; do [[ "$a" =~ ^https?:// ]] && url="$a"; done
pick() { # pick <list> <counter>: this call's entry
  local n items
  n=$(( $(cat "$FAKE_DIR/$2" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$FAKE_DIR/$2"
  IFS=, read -ra items <<< "$1"
  (( n <= ${#items[@]} )) || n=${#items[@]}
  printf '%s' "${items[$((n - 1))]}"
}
case "$url" in
  */models)
    mode=$(pick "${FAKE_MODELS:-ok}" models.count)
    echo "models $mode" >> "$FAKE_DIR/calls.log"
    [[ "$mode" == down ]] && { echo "curl: (7) Failed to connect to the fake router" >&2; exit 7; }
    printf '%s\n' '{"data":[{"id":"qwen","status":{"value":"loaded"},"meta":{"n_ctx":65536}}]}'
    ;;
  */v1/chat/completions)
    cat > /dev/null
    mode=$(pick "${FAKE_POST:-down}" post.count)
    echo "post $mode" >> "$FAKE_DIR/calls.log"
    case "$mode" in
      down)   echo "curl: (7) Failed to connect to the fake router" >&2; exit 7 ;;
      noload) printf '%s' '{"error":{"code":500,"message":"model name=qwen failed to load","type":"server_error"}}'; exit 22 ;;
      toobig) printf '%s' '{"error":{"code":400,"message":"the request exceeds the available context size, try increasing it","type":"exceed_context_size_error"}}'; exit 22 ;;
      reply:*) jq -n --rawfile c "${mode#reply:}" '{choices: [{message: {content: ($c | rtrimstr("\n"))}}]}' ;;
      *)      echo "fake curl: unknown POST mode $mode" >&2; exit 99 ;;
    esac
    ;;
  *) echo "fake curl: unexpected URL $url" >&2; exit 99 ;;
esac
FAKE
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH" LLM_HOST="http://127.0.0.1:9"
fake=$(command -v curl)
[[ "$fake" == "$WORK/bin/curl" ]] || { echo "the fake curl is not first on PATH: $fake" >&2; exit 2; }

# --- fixtures --------------------------------------------------------------
FIX="$WORK/fixtures"
mkdir -p "$FIX"
cat > "$FIX/research.json" <<'JSON'
{
  "keywords": [
    {"keyword": "cat water fountain", "volume": 900},
    {"keyword": "quiet cat water fountain", "volume": 200},
    {"keyword": "ceramic cat water fountain", "volume": 150}
  ],
  "competitors": [],
  "existing_page": {"exists": false},
  "inputs": []
}
JSON
cat > "$FIX/keywords.json" <<'JSON'
{
  "primary_keyword": "cat water fountain",
  "secondary_keywords": ["quiet cat water fountain", "ceramic cat water fountain"],
  "intent": {"type": "commercial", "format": "guide", "angle": "how to choose one"},
  "business_potential": {"score": 2, "reason": "the shop sells fountains"},
  "questions": ["how often should a cat water fountain be cleaned"],
  "must_cover": ["noise", "materials"],
  "rationale": "The head term matches the page purpose."
}
JSON
cat > "$FIX/outline.md" <<'MD'
# Choosing a Cat Water Fountain

## How a Fountain Works
_Intent: explain the pump and the filter_

## FAQ
_Intent: answer the researched questions_

### How often should a fountain be cleaned?

## Conclusion
_Intent: sum up and point to the call to action_
MD

# tree <name>: a fresh scratch tree, path in T
tree() {
  T="$WORK/$1"
  mkdir -p "$T"/{research,briefs/_ingest,outputs,fake}
}

# seed_research: the page check and the collection done, and every answer the
# keyword stage and the brief stages read, so the keyword choice runs next.
seed_research() {
  local r="$T/research/$SLUG"
  mkdir -p "$r/brief-stages" "$r/inputs"
  printf '%s\n' '{"exists": false, "checked_at": "2026-11-01T00:00:00Z"}' > "$r/page.json"
  cp "$FIX/research.json" "$r/research.json"
  printf '%s\n' "A buyer's guide to cat water fountains." > "$r/brief-stages/purpose.txt"
  : > "$r/type.txt"
  : > "$r/suggested.txt"
  : > "$T/briefs/_ingest/$SLUG.txt"
}

# seed_brief: seed_research plus a keyword choice, four brief stages and the
# brief, so the outline runs next.
seed_brief() {
  seed_research
  local r="$T/research/$SLUG" s
  cp "$FIX/keywords.json" "$r/keywords.json"
  for s in 01-intent 02-structure 03-targets 04-facts; do echo '{}' > "$r/brief-stages/$s.json"; done
  cp "$ROOT/briefs/example.json" "$T/briefs/$SLUG.json"
}

env_for() { echo "RESEARCH_DIR=$T/research BRIEFS_DIR=$T/briefs OUTPUTS_DIR=$T/outputs FAKE_DIR=$T/fake"; }

# auto: ./seo --auto on the current tree, exit code in RC, output in $T/out.txt
auto() {
  rm -f "$T"/fake/*
  env $(env_for) timeout 120 "$ROOT/seo" --auto "$SLUG" > "$T/out.txt" 2>&1
  RC=$?
}

# menu <keys>: the interactive menu in a terminal, fed the keys given
menu() {
  rm -f "$T"/fake/*
  printf '%b' "$1" | timeout 120 script -qec "env PATH='$PATH' LLM_HOST='$LLM_HOST' $(env_for) '$ROOT/seo' $SLUG" /dev/null > "$T/menu.txt" 2>&1
  RC=$?
}

# state <label>: the stage's state as the next run reads it, from the piped table
state() {
  env $(env_for) "$ROOT/seo" "$SLUG" < /dev/null 2>&1 \
    | sed -nE "s/^ +[0-9]+ \[([a-z]+) *\] $1 .*/\1/p"
}

FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1: $2"; FAILED=$((FAILED + 1)); }
# expect <case> <description of what was wrong> <test command...>
expect() {
  local name=$1 why=$2; shift 2
  if "$@"; then pass "$name"; else fail "$name" "$why"; fi
}
no_leftovers() { [[ -z "$(find "$T/research" "$T/outputs" -name '*.new' -print -quit)" ]]; }
same_file() { cmp -s "$1" "$2"; }
size_of() { if [[ -e "$1" ]]; then echo "$(wc -c < "$1") bytes"; else echo "no file"; fi; }
# saw <file> <text>: the run printed this line, so the case reached the code it
# is about rather than passing because it stopped somewhere earlier
saw() { grep -qF -- "$2" "$1"; }

# --- Phase 91: a failed call leaves the previous file -----------------------

tree kw-fail-first
seed_research
FAKE_POST=down auto
expect "keyword call fails on a first run: the run reached the keyword call" "no 'the call failed' line" \
  saw "$T/out.txt" "the call failed, see the message above. The prompt is kept"
expect "keyword call fails on a first run: no keywords.json" \
  "keywords.json left behind (size: $(size_of "$T/research/$SLUG/keywords.json")), rc $RC" \
  test ! -e "$T/research/$SLUG/keywords.json"
st=$(state "Keyword choice")
expect "keyword call fails on a first run: the next run reads the stage as ready" "it reads $st" test "$st" = ready
expect "keyword call fails on a first run: no .new file left" "a .new file is left" no_leftovers

tree kw-fail-existing
seed_research
cp "$FIX/keywords.json" "$T/research/$SLUG/keywords.json"
FAKE_POST=down menu '3\ny\n\nq\n'
expect "keyword call fails over a choice replaced at the menu: the menu asked and called" \
  "the replace question or the failed call is missing from the transcript" \
  bash -c 'grep -qF "A keyword choice already exists." "$1" && grep -qF "the call failed" "$1"' _ "$T/menu.txt"
expect "keyword call fails over a choice replaced at the menu: the old file is kept" \
  "keywords.json changed (size: $(size_of "$T/research/$SLUG/keywords.json")), menu rc $RC" \
  same_file "$FIX/keywords.json" "$T/research/$SLUG/keywords.json"
expect "keyword call fails over a choice replaced at the menu: no .new file left" "a .new file is left" no_leftovers

tree kw-ok
seed_research
FAKE_POST="reply:$FIX/keywords.json,down" auto
expect "keyword call succeeds: the reply passed its check" "no acceptance line" \
  saw "$T/out.txt" "auto: keyword choice accepted on a passing check"
expect "keyword call succeeds: keywords.json is the reply" \
  "keywords.json differs from the reply, rc $RC" \
  same_file "$FIX/keywords.json" "$T/research/$SLUG/keywords.json"
expect "keyword call succeeds: no .new file left" "a .new file is left" no_leftovers

tree outline-fail-first
seed_brief
FAKE_POST=down auto
expect "outline call fails on a first run: the run reached the outline call" "no '--- Outline' then failed call" \
  bash -c 'sed -n "/^--- Outline/,\$p" "$1" | grep -qF "the call failed"' _ "$T/out.txt"
expect "outline call fails on a first run: no outline.md" \
  "outline.md left behind (size: $(size_of "$T/outputs/$SLUG/outline.md")), rc $RC" \
  test ! -e "$T/outputs/$SLUG/outline.md"
st=$(state "Outline")
expect "outline call fails on a first run: the next run reads the stage as ready" "it reads $st" test "$st" = ready
expect "outline call fails on a first run: no .new file left" "a .new file is left" no_leftovers

tree outline-fail-stale
seed_brief
mkdir -p "$T/outputs/$SLUG"
cp "$FIX/outline.md" "$T/outputs/$SLUG/outline.md"
touch -d '1 hour ago' "$T/outputs/$SLUG/outline.md"
printf '%s\n' '{"rebuild": true}' > "$T/research/$SLUG/auto.json"
FAKE_POST=down auto
expect "outline call fails over a stale outline: the run chose to replace it, then the call failed" \
  "the auto rebuild answer or the failed call is missing" \
  bash -c 'grep -qF "Replace it? [y/N] y   (auto: rebuild)" "$1" && grep -qF "the call failed" "$1"' _ "$T/out.txt"
expect "outline call fails over a stale outline with rebuild true: the old file is kept" \
  "outline.md changed (size: $(size_of "$T/outputs/$SLUG/outline.md")), rc $RC" \
  same_file "$FIX/outline.md" "$T/outputs/$SLUG/outline.md"
expect "outline call fails over a stale outline: no .new file left" "a .new file is left" no_leftovers

tree outline-ok
seed_brief
FAKE_POST="reply:$FIX/outline.md,down" auto
expect "outline call succeeds: the reply passed its check" "no 'check passed' after '--- Outline'" \
  bash -c 'sed -n "/^--- Outline/,/^--- Draft/p" "$1" | grep -qF "check passed"' _ "$T/out.txt"
expect "outline call succeeds: outline.md is the reply" \
  "outline.md differs from the reply, rc $RC" \
  same_file "$FIX/outline.md" "$T/outputs/$SLUG/outline.md"
expect "outline call succeeds: no .new file left" "a .new file is left" no_leftovers

echo
if (( FAILED )); then
  echo "$FAILED case(s) failed"
  exit 1
fi
echo "all cases passed"
