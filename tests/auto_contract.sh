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
# Processes the lock cases start in the background are stopped on the way out,
# even when a case fails part way and never reaches its own stop.
HOLDERS=()
cleanup() {
  local p
  for p in "${HOLDERS[@]}"; do [[ -e "/proc/$p" ]] && kill "$p"; done
  rm -rf "$WORK"
}
trap cleanup EXIT
SLUG=contract-page
# brief_stages.sh reads prompts/ relative to the working directory, as it does
# when ./seo runs from the repo root, so the suite runs from there too.
cd "$ROOT" || exit 2

for tool in jq script timeout flock setsid; do
  command -v "$tool" > /dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done

# --- the fake router -------------------------------------------------------
# FAKE_POST and FAKE_MODELS are comma lists, one entry per call in order, the
# last entry repeating. A POST entry is down (curl 7), noload (HTTP 500, the
# model failed to load), loading (HTTP 503, the model still loading), toobig
# (HTTP 400, prompt over the context), timeout (curl 28), empty (curl 52), recv
# (curl 56), probe (logs whether the file FAKE_PROBE exists, then curl 7), slow
# (curl 7 after 3 seconds, so a run stays busy) or reply:<file> (the file's text
# as the model's reply). A /models entry is ok, down, noqwen (a router up but
# serving only gemma), noctx (qwen listed with no context size) or badjson (a
# reply that is not JSON). Counters live in FAKE_DIR so each run starts from
# call 1.
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
    id=qwen
    [[ "$mode" == noqwen ]] && id=gemma
    [[ "$mode" == badjson ]] && { echo "not json"; exit 0; }
    [[ "$mode" == noctx ]] && { printf '{"data":[{"id":"qwen","status":{"value":"unloaded"}}]}\n'; exit 0; }
    printf '{"data":[{"id":"%s","status":{"value":"loaded"},"meta":{"n_ctx":65536}}]}\n' "$id"
    ;;
  */v1/chat/completions)
    cat > /dev/null
    mode=$(pick "${FAKE_POST:-down}" post.count)
    echo "post $mode" >> "$FAKE_DIR/calls.log"
    case "$mode" in
      down)   echo "curl: (7) Failed to connect to the fake router" >&2; exit 7 ;;
      noload) printf '%s' '{"error":{"code":500,"message":"model name=qwen failed to load","type":"server_error"}}'; exit 22 ;;
      empty)  echo "curl: (52) Empty reply from server" >&2; exit 52 ;;
      recv)   echo "curl: (56) Recv failure: Connection reset by peer" >&2; exit 56 ;;
      loading) printf '%s' '{"error":{"code":503,"message":"Loading model","type":"unavailable_error"}}'; exit 22 ;;
      toobig) printf '%s' '{"error":{"code":400,"message":"the request exceeds the available context size, try increasing it","type":"exceed_context_size_error"}}'; exit 22 ;;
      timeout) echo "curl: (28) Operation timed out after 120000 milliseconds with 0 bytes received" >&2; exit 28 ;;
      slow)   sleep 3.01; echo "curl: (7) Failed to connect to the fake router" >&2; exit 7 ;;
      probe)  if [[ -e "$FAKE_PROBE" ]]; then echo "probe present" >> "$FAKE_DIR/calls.log"; else echo "probe absent" >> "$FAKE_DIR/calls.log"; fi
              echo "curl: (7) Failed to connect to the fake router" >&2; exit 7 ;;
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

# --- Phase 92: a router that cannot serve the model exits 13 ---------------
# The wrapper alone first, for the code it gives each kind of failure, then
# --auto, for that code reaching the exit code from each stage that calls it.

printf '%s\n' 'Say hello.' > "$FIX/prompt.txt"
printf '%s\n' 'Hello.' > "$FIX/hello.txt"

# wrapper <post-modes> [models-modes]: llm_call.sh on its own, code in RC
wrapper() {
  rm -f "$T"/fake/*
  env FAKE_DIR="$T/fake" FAKE_POST="$1" FAKE_MODELS="${2:-ok}" \
    timeout 60 bash "$ROOT/scripts/llm_call.sh" "$FIX/prompt.txt" 0.2 1 > "$T/stdout.txt" 2> "$T/stderr.txt"
  RC=$?
}

tree wrapper
wrapper down
expect "wrapper: a chat call that cannot connect exits 7" "rc $RC" test "$RC" -eq 7
wrapper noload
expect "wrapper: a model the router failed to load exits 75" "rc $RC" test "$RC" -eq 75
expect "wrapper: the load failure's body is still printed" "stderr: $(head -c 200 "$T/stderr.txt")" \
  saw "$T/stderr.txt" "model name=qwen failed to load"
wrapper toobig
expect "wrapper: an oversized prompt still exits 22" "rc $RC" test "$RC" -eq 22
wrapper "reply:$FIX/hello.txt"
expect "wrapper: a reply is printed and exits 0" "rc $RC, stdout $(head -c 200 "$T/stdout.txt")" \
  bash -c '[[ $2 -eq 0 ]] && cmp -s "$1" "$3"' _ "$T/stdout.txt" "$RC" "$FIX/hello.txt"
wrapper down down
expect "wrapper: /models unreachable exits 7" "rc $RC" test "$RC" -eq 7

tree auto-kw-down
seed_research
FAKE_POST=down auto
expect "--auto: keyword call that cannot connect exits 13" "rc $RC" test "$RC" -eq 13

tree auto-kw-noload
seed_research
FAKE_POST=noload auto
expect "--auto: keyword call whose model failed to load exits 13" "rc $RC" test "$RC" -eq 13

tree auto-kw-toobig
seed_research
FAKE_POST=toobig auto
expect "--auto: keyword call with an oversized prompt still exits 12" "rc $RC" test "$RC" -eq 12

tree auto-outline-down
seed_brief
FAKE_POST=down auto
expect "--auto: outline call that cannot connect exits 13" "rc $RC" test "$RC" -eq 13

tree auto-draft-down
seed_brief
mkdir -p "$T/outputs/$SLUG"
cp "$FIX/outline.md" "$T/outputs/$SLUG/outline.md"
touch -d '1 hour ago' "$T/briefs/$SLUG.json"
FAKE_POST=down auto
expect "--auto: the draft made its first part call" "no chat call in $(cat "$T/fake/calls.log" 2>/dev/null)" \
  bash -c 'sed -n "/^--- Draft/,\$p" "$1" | grep -qF "the draft stopped" && grep -q "^post down" "$2"' _ "$T/out.txt" "$T/fake/calls.log"
expect "--auto: draft part call that cannot connect exits 13" "rc $RC" test "$RC" -eq 13

tree auto-router-gone
seed_research
FAKE_MODELS="ok,down" FAKE_POST=down auto
expect "--auto: router listed at the preflight but gone at the next stage exits 13" "rc $RC" test "$RC" -eq 13
expect "--auto: router gone at the next stage: no chat call was made" "calls: $(paste -sd' ' "$T/fake/calls.log")" \
  bash -c '! grep -q "^post" "$1"' _ "$T/fake/calls.log"

# Only the stage's own router check can catch this one: the wrapper would exit 5
# for a model missing from /models, which is not a router-down code.
tree auto-qwen-gone
seed_research
FAKE_MODELS="ok,noqwen" FAKE_POST=down auto
expect "--auto: router up but no longer serving qwen at the next stage exits 13" "rc $RC" test "$RC" -eq 13

tree auto-preflight-down
seed_research
FAKE_MODELS=down auto
expect "--auto: router down at the preflight exits 13" "rc $RC" test "$RC" -eq 13

tree menu-kw-down
seed_research
FAKE_POST=down menu '3\n\nq\n'
expect "menu: a router failure at a picked stage reports the call and returns to the menu" \
  "rc $RC, or the failed call or the second menu is missing" \
  bash -c '[[ $2 -eq 0 ]] && grep -qF "the call failed" "$1" && (( $(grep -c "Choose: " "$1") >= 2 ))' _ "$T/menu.txt" "$RC"

# --- Phase 93: the stage scripts pass the router code up ------------------
# The brief stages turned it into exit 3, the rewrite into a kept draft, and the
# fact check into a WARN. Where the call under test is the fact check, it is the
# last call of the run: any later call would fail too and hide whether the fact
# check passed the code up.

mkdir -p "$FIX/parts"
printf '%s\n' 'A fountain keeps water moving, which many cats prefer. This guide explains how to choose one.' \
  > "$FIX/parts/00-intro.md"
printf '%s\n' '## How a Fountain Works' '' 'A small pump circulates the water through a filter.' \
  > "$FIX/parts/01-how-a-fountain-works.md"
printf '%s\n' '## FAQ' '' '### How often should a fountain be cleaned?' '' 'Clean it on a regular schedule.' \
  > "$FIX/parts/02-faq.md"
printf '%s\n' '## Conclusion' '' 'A fountain is a simple upgrade. Visit a local jeweler for a private consultation.' \
  > "$FIX/parts/03-conclusion.md"
printf '%s\n' '{"issues": []}' > "$FIX/verify-empty.json"
printf '%s\n' '# A heading no part may gain' '' 'Some words.' > "$FIX/bad-edit.md"
printf '%s\n' 'this is not json' > "$FIX/notjson.txt"
PARTS=(00-intro 01-how-a-fountain-works 02-faq 03-conclusion)

# seed_draft: the brief carries one fact, so every part gets a fact check, and
# four drafted parts with their checks and draft.md are in place, so the rewrite
# runs next. Each artifact is older than the ones built from it.
seed_draft() {
  seed_brief
  jq '.facts = ["The shop sells ceramic fountains."]' "$ROOT/briefs/example.json" > "$T/briefs/$SLUG.json"
  local o="$T/outputs/$SLUG" p
  mkdir -p "$o/sections"
  cp "$FIX/outline.md" "$o/outline.md"
  for p in "${PARTS[@]}"; do
    cp "$FIX/parts/$p.md" "$o/sections/$p.md"
    cp "$FIX/verify-empty.json" "$o/sections/$p.verify.json"
    [[ "$p" == 00-intro ]] || head -1 "$FIX/parts/$p.md" > "$o/sections/$p.block.md"
  done
  for p in "${PARTS[@]}"; do cat "$o/sections/$p.md"; echo; done > "$o/draft.md"
  touch -d '3 hours ago' "$T/briefs/$SLUG.json"
  touch -d '2 hours ago' "$o/outline.md"
  touch -d '1 hour ago' "$o/sections"/* "$o/draft.md"
}
posts() { grep -c '^post' "$T/fake/calls.log" 2>/dev/null || echo 0; }

tree auto-brief-down
seed_research
cp "$FIX/keywords.json" "$T/research/$SLUG/keywords.json"
FAKE_POST=down auto
expect "brief stage call that cannot connect: one call, no second seed" "$(posts) chat calls" test "$(posts)" -eq 1
# The schema sidecar is written before the call, so the stage file itself is what counts.
expect "brief stage call that cannot connect: no stage file" "01-intent.json was written" \
  test ! -e "$T/research/$SLUG/brief-stages/01-intent.json"
expect "--auto: brief stage call that cannot connect exits 13" "rc $RC" test "$RC" -eq 13

tree auto-brief-unusable
seed_research
cp "$FIX/keywords.json" "$T/research/$SLUG/keywords.json"
FAKE_POST="reply:$FIX/notjson.txt" auto
expect "brief stage reply unusable twice: both seeds tried" "$(posts) chat calls" test "$(posts)" -eq 2
expect "--auto: brief stage reply unusable twice still exits 12" "rc $RC" test "$RC" -eq 12

tree auto-rewrite-down
seed_draft
FAKE_POST=down auto
expect "rewrite call that cannot connect: one call, no second seed" "$(posts) chat calls" test "$(posts)" -eq 1
expect "rewrite call that cannot connect: no final.md" "final.md was stitched" test ! -e "$T/outputs/$SLUG/final.md"
expect "rewrite call that cannot connect: no kept copy of the drafted part" "rewrite/00-intro.md exists" \
  test ! -e "$T/outputs/$SLUG/rewrite/00-intro.md"
expect "--auto: rewrite call that cannot connect exits 13" "rc $RC" test "$RC" -eq 13

tree auto-rewrite-rejected
seed_draft
FAKE_POST="reply:$FIX/bad-edit.md" auto
expect "rewrite failing its check twice: the drafted text is kept with a WARN" \
  "no WARN, or rewrite/00-intro.md is not the drafted part" \
  bash -c 'grep -qF "WARN: 00-intro kept its unedited text" "$1" && cmp -s "$2" "$3"' _ \
  "$T/out.txt" "$T/outputs/$SLUG/sections/00-intro.md" "$T/outputs/$SLUG/rewrite/00-intro.md"
expect "rewrite failing its check twice: final.md is still stitched" "no final.md" test -s "$T/outputs/$SLUG/final.md"

tree auto-rewrite-verify-down
seed_draft
mkdir -p "$T/outputs/$SLUG/rewrite"
for p in 00-intro 01-how-a-fountain-works 02-faq; do
  cp "$FIX/parts/$p.md" "$T/outputs/$SLUG/rewrite/$p.md"
  cp "$FIX/verify-empty.json" "$T/outputs/$SLUG/rewrite/$p.verify.json"
done
FAKE_POST="reply:$FIX/parts/03-conclusion.md,down" auto
expect "fact check of the last edit: the edit was accepted, then checked" "$(posts) chat calls" test "$(posts)" -eq 2
expect "fact check that cannot connect during the rewrite: no final.md" "final.md was stitched" \
  test ! -e "$T/outputs/$SLUG/final.md"
expect "--auto: fact check that cannot connect during the rewrite exits 13" "rc $RC" test "$RC" -eq 13

tree auto-draft-verify-down
seed_draft
rm "$T/outputs/$SLUG/sections/03-conclusion.md" "$T/outputs/$SLUG/sections/03-conclusion.verify.json" "$T/outputs/$SLUG/draft.md"
FAKE_POST="reply:$FIX/parts/03-conclusion.md,down" auto
expect "fact check of the last drafted part: the part was drafted, then checked" "$(posts) chat calls" test "$(posts)" -eq 2
expect "fact check that cannot connect during the draft: draft.md is not stitched" "draft.md was stitched" \
  test ! -e "$T/outputs/$SLUG/draft.md"
expect "fact check that cannot connect during the draft: the part is kept, unverified" \
  "the part is missing or has a report" \
  bash -c '[[ -s "$1.md" && ! -e "$1.verify.json" ]]' _ "$T/outputs/$SLUG/sections/03-conclusion"
expect "--auto: fact check that cannot connect during the draft exits 13" "rc $RC" test "$RC" -eq 13
FAKE_POST="reply:$FIX/verify-empty.json,down" auto
expect "the rerun once the router is back verifies that part and stitches the draft" \
  "no report for the part, or no draft.md, rc $RC" \
  bash -c '[[ -s "$1/sections/03-conclusion.verify.json" && -s "$1/draft.md" ]]' _ "$T/outputs/$SLUG"

tree auto-draft-verify-timeout
seed_draft
rm "$T/outputs/$SLUG/sections/03-conclusion.md" "$T/outputs/$SLUG/sections/03-conclusion.verify.json" "$T/outputs/$SLUG/draft.md"
FAKE_POST="reply:$FIX/parts/03-conclusion.md,timeout,down" auto
expect "fact check that times out: the part is left unverified with a WARN and the draft is stitched" \
  "no WARN, a report exists, or no draft.md" \
  bash -c 'grep -qF "WARN: 03-conclusion verification call failed or ran away" "$1" && [[ ! -e "$2/sections/03-conclusion.verify.json" && -s "$2/draft.md" ]]' _ \
  "$T/out.txt" "$T/outputs/$SLUG"

# --- Phase 94: every --auto exit writes status.json -------------------------

STATUS_KEYS='["exit_code","final","finished_at","missing","reason","slug","stages","stop_reason"]'
status_file() { echo "$T/outputs/$SLUG/status.json"; }
# status_has <jq args...>: the status file holds what the filter tests for
status_has() { jq -e "$@" "$(status_file)" > /dev/null 2>&1; }
status_text() { if [[ -e "$(status_file)" ]]; then jq -c . "$(status_file)" | head -c 400; else echo "no status.json"; fi; }
# shape: every key present with its type, the run's own exit code, the menu's
# nine stages in order, and a UTC timestamp
shape() {
  status_has --arg slug "$SLUG" --argjson rc "$RC" --argjson keys "$STATUS_KEYS" '
    (keys == $keys) and .slug == $slug and .exit_code == $rc
    and (.finished_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    and (.stop_reason == null or (.stop_reason | type == "string"))
    and ([.stages[].id] == ["page","collect","keywords","brief_stages","brief","outline","draft","rewrite","review"])
    and all(.stages[]; (.state | type == "string") and (.detail | type == "string"))
    and (.missing | type == "array")
    and all(.missing[]; (.path == null or (.path | type == "string")) and (.message | type == "string" and length > 0))
    and (.reason == null or (.reason | type == "string"))
    and (.final == null or (.final | type == "string"))'
}
# status_case <name> <expected rc> <jq filter> [jq args...]: the exit code, the
# shape, and what this exit must carry
status_case() {
  local name=$1 want=$2 filter=$3; shift 3
  expect "$name: exits $want" "rc $RC" test "$RC" -eq "$want"
  expect "$name: status.json has the full shape" "$(status_text)" shape
  expect "$name: status.json carries what this exit means" "$(status_text)" status_has "$@" "$filter"
}

printf '%s\n' 'Most cats drink about 250 ml of water a day. This guide explains how to choose a fountain.' > "$FIX/intro-250.md"
jq '.primary_keyword = "orthopedic dog bed"' "$FIX/keywords.json" > "$FIX/bad-keywords.json"
printf '%s\n' 'foo,bar' '1,2' > "$FIX/no-keyword-column.csv"

tree status-finished
seed_draft
cp "$T/outputs/$SLUG/draft.md" "$T/outputs/$SLUG/final.md"
auto
status_case "status, finished" 0 \
  '.stop_reason == null and .final == $f and .missing == [] and .reason == null
   and ([.stages[] | select(.id != "review") | .state] | all(. == "done"))' --arg f "$T/outputs/$SLUG/final.md"

tree status-preflight
seed_research
rm "$T/research/$SLUG/type.txt" "$T/research/$SLUG/suggested.txt"
auto
status_case "status, two inputs missing at the preflight" 10 \
  '.stop_reason == "input" and [.missing[].path] == [$a, $b] and .reason == null and .final == null' \
  --arg a "$T/research/$SLUG/type.txt" --arg b "$T/research/$SLUG/suggested.txt"

tree status-auto-not-object
seed_research
printf '%s\n' '[1]' > "$T/research/$SLUG/auto.json"
auto
status_case "status, auto.json not an object" 10 \
  '.stop_reason == "input" and [.missing[].path] == [$a]' --arg a "$T/research/$SLUG/auto.json"

tree status-word-count
seed_research
printf '%s\n' '{"word_count": 50}' > "$T/research/$SLUG/auto.json"
auto
status_case "status, word_count out of range" 10 \
  '.stop_reason == "input" and [.missing[].path] == [$a] and (.missing[0].message | test("word_count"))' \
  --arg a "$T/research/$SLUG/auto.json"

tree status-bad-export
seed_research
rm "$T/research/$SLUG/research.json"
cp "$FIX/no-keyword-column.csv" "$T/research/$SLUG/inputs/export.csv"
printf '%s\n' 'https://competitor.example/page' > "$T/research/$SLUG/competitors.txt"
auto
status_case "status, an export with no keyword column" 10 \
  '.stop_reason == "input" and [.missing[].path] == [$a]' --arg a "$T/research/$SLUG/inputs/"

tree status-kept-stale
seed_brief
mkdir -p "$T/outputs/$SLUG"
cp "$FIX/outline.md" "$T/outputs/$SLUG/outline.md"
touch -d '1 hour ago' "$T/outputs/$SLUG/outline.md"
auto
status_case "status, a stale outline kept" 11 \
  '.stop_reason == "kept" and (.reason | test("Outline")) and .missing == [] and .final == null'

tree status-keyword-rejected
seed_research
FAKE_POST="reply:$FIX/bad-keywords.json" auto
status_case "status, a keyword choice rejected at both seeds" 11 \
  '.stop_reason == "decision" and (.reason | test("keywords.rejected.json"))'

tree status-numbers
seed_draft
cp "$FIX/intro-250.md" "$T/outputs/$SLUG/sections/00-intro.md"
rm "$T/outputs/$SLUG/draft.md"
FAKE_POST="reply:$FIX/intro-250.md,reply:$FIX/verify-empty.json,reply:$FIX/intro-250.md,reply:$FIX/verify-empty.json" auto
expect "status, numbers after two redrafts: the part was redrafted twice" "$(posts) chat calls" test "$(posts)" -eq 4
status_case "status, numbers after two redrafts" 11 \
  '.stop_reason == "decision" and (.reason | test("250"))'

tree status-stage-failed
seed_research
FAKE_POST=toobig auto
status_case "status, a stage that failed" 12 \
  '.stop_reason == "failed" and .missing == [] and .reason == null and .final == null'

tree status-router-preflight
seed_research
FAKE_MODELS=down auto
status_case "status, router down at the preflight" 13 '.stop_reason == "router"'
FAKE_POST=toobig auto
status_case "status, the next run replaces the file" 12 '.stop_reason == "failed"'
expect "status: no temporary file is left beside it" "a status.json.tmp is left" \
  test ! -e "$(status_file).tmp"

tree status-router-midrun
seed_research
FAKE_POST=down auto
status_case "status, router gone at the keyword call" 13 '.stop_reason == "router"'

tree status-removed-first
seed_research
mkdir -p "$T/outputs/$SLUG"
printf '%s\n' '{"left": "by an earlier run"}' > "$(status_file)"
FAKE_POST=probe FAKE_PROBE="$(status_file)" auto
expect "status: the previous file is gone while the run is going" "calls: $(paste -sd' ' "$T/fake/calls.log")" \
  saw "$T/fake/calls.log" "probe absent"
status_case "status, after a run that found an old file" 13 '.stop_reason == "router"'

tree status-bad-slug
env $(env_for) "$ROOT/seo" --auto Not_A_Slug > "$T/out.txt" 2>&1
RC=$?
expect "status: an invalid slug exits 2" "rc $RC" test "$RC" -eq 2
env $(env_for) "$ROOT/seo" --auto > "$T/out.txt" 2>&1
RC=$?
expect "status: no slug exits 2" "rc $RC" test "$RC" -eq 2
expect "status: exit 2 writes no status.json anywhere" "$(find "$T/outputs" -name status.json)" \
  test -z "$(find "$T/outputs" -name status.json)"

# --- Phase 95: one run per slug ---------------------------------------------

lockfile() { echo "$T/outputs/${1:-$SLUG}/.lock"; }
# wait_for <file> <text>: up to ten seconds for a background run to print it
wait_for() {
  local i
  for i in $(seq 100); do
    [[ -e "$1" ]] && grep -qF -- "$2" "$1" && return 0
    sleep 0.1
  done
  echo "gave up waiting for '$2' in $1" >&2
  return 1
}
# is_held and is_free tell a lock someone holds from one that could not be read:
# flock exits 75 only on a real conflict, and with any other code when it cannot
# open the file, which a bare "! flock -n" would read as held.
is_held() { flock -n -E 75 "$1" true; (( $? == 75 )); }
is_free() { [[ -e "$1" ]] && flock -n -E 75 "$1" true; }
# hold <lockfile>: a single process holding the lock as a run would, so killing
# it is what releases the lock (bash execs sleep with the descriptor still open)
hold() {
  mkdir -p "$(dirname "$1")"
  bash -c 'exec 9> "$1" && flock 9 && exec sleep 120' _ "$1" &
  HOLDER=$!; HOLDERS+=("$HOLDER")
  local i
  for i in $(seq 50); do is_held "$1" && return 0; sleep 0.1; done
  echo "the holder never took $1" >&2
  return 1
}
unhold() { kill "$HOLDER"; wait "$HOLDER"; }
# auto_bg <fake-dir> <post-modes>: an --auto run in the background, in its own
# process group so a test can kill the whole run, PID in BG
auto_bg() {
  mkdir -p "$1"
  env $(env_for) FAKE_DIR="$1" FAKE_POST="$2" setsid "$ROOT/seo" --auto "$SLUG" > "$1/run.txt" 2>&1 &
  BG=$!; HOLDERS+=("$BG")
}

tree lock-auto-auto
seed_research
SLUG=third-page; seed_research; SLUG=contract-page
auto_bg "$T/holder" slow
wait_for "$T/holder/calls.log" "post slow"
mkdir -p "$T/second"
t0=$(date +%s%N)
env $(env_for) FAKE_DIR="$T/second" "$ROOT/seo" --auto "$SLUG" > "$T/second/out.txt" 2>&1
RC=$?
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
expect "lock: --auto on a slug another --auto holds exits 14" "rc $RC" test "$RC" -eq 14
expect "lock: the busy exit is at once" "${ms} ms" test "$ms" -lt 1000
expect "lock: the busy exit says so" "$(head -c 300 "$T/second/out.txt")" saw "$T/second/out.txt" "busy"
expect "lock: the busy exit wrote no status.json while the holder runs" "$(status_text)" test ! -e "$(status_file)"
mkdir -p "$T/third"
SLUG=third-page
env $(env_for) FAKE_DIR="$T/third" FAKE_POST=down "$ROOT/seo" --auto "$SLUG" > "$T/third/out.txt" 2>&1
RC=$?
SLUG=contract-page
expect "lock: a different slug runs while this one is held" "rc $RC" test "$RC" -eq 13
wait "$BG"
RC=$?
expect "lock: the holder finishes unaffected" "holder rc $RC, $(status_text)" \
  bash -c '[[ $1 -eq 13 ]] && jq -e ".exit_code == 13" "$2" > /dev/null' _ "$RC" "$(status_file)"
expect "lock: the busy exit added nothing to the holder's run.log" \
  "$(grep -c "^seo --auto $SLUG, " "$T/outputs/$SLUG/run.log") run headers" \
  test "$(grep -c "^seo --auto $SLUG, " "$T/outputs/$SLUG/run.log")" -eq 1
FAKE_POST=down auto
expect "lock: once the holder has exited, the next run proceeds" "rc $RC" test "$RC" -eq 13

tree lock-killed
seed_research
auto_bg "$T/holder" slow
wait_for "$T/holder/calls.log" "post slow"
echo "note: bash reports the next run as Killed, because this case kills it on purpose" >&2
kill -9 -- "-$BG"
wait "$BG"
FAKE_POST=down auto
expect "lock: after the holding run is killed, the next run proceeds" "rc $RC" test "$RC" -eq 13

tree lock-menu-auto
seed_research
{ sleep 4; printf 'q\n'; } | timeout 60 script -qec "env PATH='$PATH' LLM_HOST='$LLM_HOST' $(env_for) '$ROOT/seo' $SLUG" /dev/null > "$T/menu.txt" 2>&1 &
menu_pid=$!; HOLDERS+=("$menu_pid")
wait_for "$T/menu.txt" "Choose: "
FAKE_POST=down auto
expect "lock: --auto on a slug the menu holds exits 14" "rc $RC" test "$RC" -eq 14
wait "$menu_pid"
RC=$?
expect "lock: the menu holding it carries on and quits normally" "menu rc $RC" test "$RC" -eq 0

tree lock-auto-menu
seed_research
hold "$(lockfile)"
menu ''
expect "lock: the menu on a slug another run holds exits 14" "menu rc $RC" test "$RC" -eq 14
expect "lock: the menu says the slug is busy" "$(tr -d '\r' < "$T/menu.txt" | head -c 300)" saw "$T/menu.txt" "busy"
env $(env_for) "$ROOT/seo" "$SLUG" < /dev/null > "$T/table.txt" 2>&1
RC=$?
expect "lock: the piped stage table still prints while the slug is held" "rc $RC" \
  bash -c '[[ $1 -eq 0 ]] && grep -qF "SEO pipeline: $2" "$3"' _ "$RC" "$SLUG" "$T/table.txt"
unhold

tree lock-switch
seed_research
SLUG=third-page; seed_research; SLUG=contract-page
hold "$(lockfile other-busy)"
{ printf 's\nother-busy\nthird-page\n'; sleep 4; printf 'q\n'; } \
  | timeout 60 script -qec "env PATH='$PATH' LLM_HOST='$LLM_HOST' $(env_for) '$ROOT/seo' $SLUG" /dev/null > "$T/menu.txt" 2>&1 &
menu_pid=$!; HOLDERS+=("$menu_pid")
wait_for "$T/menu.txt" "SEO pipeline: third-page"
expect "lock: s to a busy page says so and asks again" "no busy line for other-busy" saw "$T/menu.txt" "other-busy is busy"
expect "lock: s released the page it left" "contract-page's lock is held or was never taken" is_free "$(lockfile)"
expect "lock: s holds the page it moved to" "third-page's lock is not held" is_held "$(lockfile third-page)"
wait "$menu_pid"
RC=$?
expect "lock: the menu quits normally after the switch" "menu rc $RC" test "$RC" -eq 0
unhold

# --- Phase 99: a plain signal stops the whole run ---------------------------
# Before, a SIGTERM to the main process left its stages running, holding the
# lock, and writing their own status.json later (seen 2026-11-02).

stage_alive() { pgrep -f '^sleep 3\.01$' | wc -l; }   # the fake's slow call
pgid_of() { ps -o pgid= -p "$1" | tr -d ' '; }
# sig_case <name> <signal> <code>: the run stopped by that signal stops within a
# second (the fake call takes 3), leaves nothing
# running, and leaves a status.json naming the signal and a free lock
sig_case() {
  expect "$1: exits $3" "rc $RC" test "$RC" -eq "$3"
  expect "$1: stops at once, not after the stage finishes on its own" "${STOP_MS} ms" test "$STOP_MS" -lt 1000
  expect "$1: no stage is left running" "$(stage_alive) left" test "$(stage_alive)" -eq 0
  expect "$1: status.json has the full shape" "$(status_text)" shape
  expect "$1: status.json says the run was stopped by a signal" "$(status_text)" \
    status_has '.stop_reason == "signal" and .missing == [] and .reason == null and .final == null'
  expect "$1: the lock is free at once" "the lock is held or missing" is_free "$(lockfile)"
}

tree sig-term
seed_research
mkdir -p "$T/bg"
env $(env_for) FAKE_DIR="$T/bg" FAKE_POST=slow "$ROOT/seo" --auto "$SLUG" > "$T/bg/out.txt" 2>&1 &
pid=$!; HOLDERS+=("$pid")
wait_for "$T/bg/calls.log" "post slow"
expect "signal: a run started without setsid leads its own process group, under the same PID" \
  "pgid $(pgid_of "$pid") for PID $pid" test "$(pgid_of "$pid")" = "$pid"
t0=$(date +%s%N); kill -TERM "$pid"
wait "$pid"
RC=$?; STOP_MS=$(( ($(date +%s%N) - t0) / 1000000 ))
sig_case "signal: SIGTERM to the PID" TERM 143

tree sig-int
seed_research
mkdir -p "$T/bg"
# A job started with & from a script inherits SIGINT ignored, which bash cannot
# trap, so the default is restored first, as a terminal or a supervisor gives it.
env --default-signal=INT $(env_for) FAKE_DIR="$T/bg" FAKE_POST=slow "$ROOT/seo" --auto "$SLUG" > "$T/bg/out.txt" 2>&1 &
pid=$!; HOLDERS+=("$pid")
wait_for "$T/bg/calls.log" "post slow"
t0=$(date +%s%N); kill -INT "$pid"
wait "$pid"
RC=$?; STOP_MS=$(( ($(date +%s%N) - t0) / 1000000 ))
sig_case "signal: SIGINT to the PID" INT 130

tree sig-group
seed_research
auto_bg "$T/holder" slow
wait_for "$T/holder/calls.log" "post slow"
t0=$(date +%s%N); kill -TERM -- "-$BG"
wait "$BG"
RC=$?; STOP_MS=$(( ($(date +%s%N) - t0) / 1000000 ))
sig_case "signal: SIGTERM to the run's process group, the documented way" TERM 143

# --- Phase 100: every way the router can be gone exits 13 -------------------
# A dropped connection, a model still loading and qwen gone from /models all
# meant 12 before, "read the log", for an outage a retry would get past.

tree wrapper-100
wrapper empty
expect "wrapper: an empty reply passes curl's 52 up" "rc $RC" test "$RC" -eq 52
wrapper recv
expect "wrapper: a dropped connection passes curl's 56 up" "rc $RC" test "$RC" -eq 56
wrapper loading
expect "wrapper: a model still loading (HTTP 503) exits 75" "rc $RC" test "$RC" -eq 75
expect "wrapper: the loading body is still printed" "stderr: $(head -c 200 "$T/stderr.txt")" saw "$T/stderr.txt" "Loading model"
wrapper down noqwen
expect "wrapper: qwen missing from /models exits 76" "rc $RC" test "$RC" -eq 76
wrapper down noctx
expect "wrapper: qwen listed with no context size still exits 5" "rc $RC" test "$RC" -eq 5
wrapper down badjson
expect "wrapper: a /models reply that is not JSON still exits 5" "rc $RC" test "$RC" -eq 5
wrapper timeout
expect "wrapper: a timeout still exits 28" "rc $RC" test "$RC" -eq 28

# auto_100 <case> <expected> <post-modes> [models-modes]: the keyword call made
# under that failure, on a fresh tree
auto_100() {
  N100=$(( ${N100:-0} + 1 ))
  tree "auto-100-$N100"   # numbered: a case name with spaces would split env_for's paths
  seed_research
  FAKE_POST="$3" FAKE_MODELS="${4:-ok}" auto
  expect "--auto: $1 exits $2" "rc $RC, calls: $(paste -sd' ' "$T/fake/calls.log")" test "$RC" -eq "$2"
}
auto_100 "an empty reply at the keyword call" 13 empty
auto_100 "a dropped connection at the keyword call" 13 recv
auto_100 "a model still loading at the keyword call" 13 loading
# The preflight and the stage's own router check read /models first, so the
# third read is the wrapper's, the one between the check and the call.
auto_100 "qwen gone between the stage's check and its call" 13 down "ok,ok,noqwen"
auto_100 "qwen listed with no context size at the call" 12 down "ok,ok,noctx"
auto_100 "a /models reply that is not JSON at the call" 12 down "ok,ok,badjson"
auto_100 "a timeout at the keyword call" 12 timeout

echo
if (( FAILED )); then
  echo "$FAILED case(s) failed"
  exit 1
fi
echo "all cases passed"
