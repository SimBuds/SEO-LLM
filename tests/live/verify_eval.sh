#!/usr/bin/env bash
# Live harness for prompts/verify.md. Run by hand, never part of the suite.
# It replays saved parts through the fact-check call at several seeds and scores
# the replies against a label file, so a change to the prompt is measured before
# it ships. A changed prompt invalidates earlier output (AGENTS.md).
#
# Usage:
#   verify_eval.sh run   <verify-prompt.md> <brief.json> <out-dir> <part.md>...
#   verify_eval.sh score <out-dir> <labels.tsv>
#
# run    builds each part's prompt the way verify_part in scripts/lib_parts.sh
#        does, calls scripts/llm_call.sh at each seed in SEEDS (default "1 2 3"),
#        and writes <out-dir>/<part>.prompt.txt and <out-dir>/<part>.seed<N>.json,
#        the raw reply. <part> is the file name without .unverified.md or .md. It
#        refuses an out-dir inside the repo's outputs/, so a measurement never
#        lands where the pipeline reads results, and it stops at the first call
#        the router cannot serve.
# score  reads each run directory directly under <out-dir> and, for every label
#        class, counts the labelled sentences each seed flagged. labels.tsv holds
#        <class> TAB <part> TAB <sentence> lines. A reported sentence matches a
#        label when either contains the other once whitespace is squeezed.
#
# This calls the router. Ask before running it, because the GPU may be in use.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../../scripts/lib_parts.sh
source "$ROOT/scripts/lib_parts.sh"

part_name() { local b; b=$(basename "$1"); b=${b%.unverified.md}; echo "${b%.md}"; }

run() {
  local tpl="${1:?verify prompt required}" brief="${2:?brief required}" out="${3:?out-dir required}"
  shift 3
  (( $# )) || { echo "no parts given" >&2; return 2; }
  # Resolved before anything is created: making the directory first and then
  # refusing it left an empty directory inside outputs/ (found 2026-11-02).
  local real; real=$(realpath -m "$out")
  [[ "$real/" == "$ROOT/outputs/"* ]] && { echo "refusing $out: it is inside outputs/" >&2; return 2; }
  mkdir -p "$out"
  local part name suspects seed rc n
  for part in "$@"; do
    name=$(part_name "$part")
    # The same three steps as verify_part, so a seed-1 run of the current prompt
    # sends the prompt the pipeline sent.
    suspects=$(grep -v '^#' "$part" | grep -oiE "$ABSOLUTE_SENTENCE" | sed 's/^ */- /' || true)
    bash "$ROOT/scripts/fill_prompt.sh" "$tpl" --brief "$brief" \
      --set-file "SECTION_TEXT=$part" --set "SUSPECTS=${suspects:-(none)}" > "$out/$name.prompt.txt" || return 2
    for seed in ${SEEDS:-1 2 3}; do
      rc=0
      LLM_MODEL="${VERIFY_MODEL:-qwen}" LLM_MAX_TOKENS=1500 LLM_TIMEOUT=120 \
        bash "$ROOT/scripts/llm_call.sh" "$out/$name.prompt.txt" 0.1 "$seed" \
        "$ROOT/prompts/verify.schema.json" > "$out/$name.seed$seed.json" || rc=$?
      n=$(jq '.issues | length' "$out/$name.seed$seed.json" 2>/dev/null || echo "?")
      printf '%-48s seed %s  rc %s  issues %s\n' "$name" "$seed" "$rc" "$n"
      router_down "$rc" && { echo "the router could not serve the model, stopping" >&2; return "$rc"; }
    done
  done
  return 0
}

score() {
  local out="${1:?out-dir required}" labels_file="${2:?labels.tsv required}" run_dir f b labels replies
  labels=$(jq -R -s 'split("\n") | map(select(length > 0) | split("\t") | {class: .[0], part: .[1], sentence: .[2]})' "$labels_file")
  for run_dir in "$out"/*/; do
    replies=$(for f in "$run_dir"*.seed*.json; do
        [[ -e "$f" ]] || continue
        b=$(basename "$f" .json)
        jq -c --arg p "${b%.seed*}" --arg s "${b##*.seed}" '{part: $p, seed: $s, sentences: [.issues[]?.sentence]}' "$f" \
          || jq -nc --arg p "${b%.seed*}" --arg s "${b##*.seed}" '{part: $p, seed: $s, sentences: null}'
      done | jq -s .)
    jq -rn --argjson L "$labels" --argjson R "$replies" --arg run "$(basename "$run_dir")" '
      def sq: gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ");
      def hit($l; $r): [($r.sentences // [])[] | sq | select(length > 0)]
        | any(. as $x | ($l.sentence | sq) as $y | ($x | contains($y)) or ($y | contains($x)));
      ($R | map(.seed) | unique) as $seeds
      | "== \($run): \($R | length) replies, \([$R[] | select(.sentences == null)] | length) unreadable",
        ( $L | group_by(.class)[] | . as $group
          | "  \($group[0].class): " + ([ $seeds[] as $s
              | ([ $group[] as $l | $R[] | select(.part == $l.part and .seed == $s) | select(hit($l; .)) ] | length) as $n
              | "seed \($s) \($n)/\($group | length)" ] | join(", ")),
            ( $group[] | . as $l
              | ([ $seeds[] as $s | $R[] | select(.part == $l.part and .seed == $s) | select(hit($l; .)) ] | length) as $c
              | select($l.class != "step" or $c > 0)
              | "    \($c) of \($seeds | length) seeds  \($l.part): \($l.sentence[0:70])" ) )'
  done
}

case "${1:-}" in
  run)   shift; run "$@" ;;
  score) shift; score "$@" ;;
  *) echo "usage: verify_eval.sh run <verify-prompt.md> <brief.json> <out-dir> <part.md>... | score <out-dir> <labels.tsv>" >&2; exit 2 ;;
esac
