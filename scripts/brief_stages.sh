#!/usr/bin/env bash
# Build a brief one approved stage at a time.
#
# Usage: brief_stages.sh <slug> [--purpose "one line"] [--redo <stage>]
#
# Runs the first stage that has no file yet, writes it, prints it, and stops, so
# the user reads and edits it before the next stage runs. Rerunning continues
# from where it stopped. Each stage sees the stages already approved, so an edit
# to an earlier stage is carried into every later one.
#
# Reads research/<slug>/{research.json,keywords.json} and the purpose recorded on
# the first run. Writes research/<slug>/brief-stages/NN-<stage>.{json,prompt.txt}.
#
# Env: RESEARCH_DIR (default research), STAGE_MODEL (default the wrapper's qwen).
#
# Exit codes: 1 usage, 2 missing input, 3 the model's reply was unusable twice.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="${RESEARCH_DIR:-research}"
TEMP=0.3

# Stage order. Phase 10 appends targets and facts.
STAGES=(intent structure)

SLUG="${1:?usage: brief_stages.sh <slug> [--purpose \"one line\"] [--redo <stage>]}"; shift
PURPOSE="" REDO=""
while (( $# )); do
  case "$1" in
    --purpose) PURPOSE="${2:?--purpose needs text}"; shift 2 ;;
    --redo)    REDO="${2:?--redo needs a stage name}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

DIR="$ROOT/$SLUG"
STAGE_DIR="$DIR/brief-stages"
RESEARCH="$DIR/research.json"
KEYWORDS="$DIR/keywords.json"
PURPOSE_FILE="$STAGE_DIR/purpose.txt"

[[ -r "$RESEARCH" ]] || { echo "no $RESEARCH: run /seo-research $SLUG first" >&2; exit 2; }
[[ -r "$KEYWORDS" ]] || { echo "no $KEYWORDS: run /seo-keywords $SLUG first" >&2; exit 2; }
mkdir -p "$STAGE_DIR"

# The purpose is asked once and reused, because every stage needs it and a
# different wording between stages would quietly change the brief.
if [[ -n "$PURPOSE" ]]; then
  printf '%s\n' "$PURPOSE" > "$PURPOSE_FILE"
elif [[ -r "$PURPOSE_FILE" ]]; then
  PURPOSE=$(cat "$PURPOSE_FILE")
else
  echo "no purpose recorded: rerun with --purpose \"what this page is for and who it is for\"" >&2
  exit 2
fi

stage_file() { printf '%s/%02d-%s.json' "$STAGE_DIR" "$1" "$2"; }

# The stages approved so far, as one object the next stage reads.
prior_json() { # prior_json <index-before>
  local i=1 f out='{}'
  for s in "${STAGES[@]}"; do
    (( i < $1 )) || break
    f=$(stage_file "$i" "$s")
    if [[ -r "$f" ]]; then
      out=$(jq --arg k "$s" --slurpfile v "$f" '. + {($k): $v[0]}' <<< "$out")
    fi
    i=$((i + 1))
  done
  printf '%s' "$out"
}

run_stage() { # run_stage <index> <stage>
  local idx="$1" stage="$2"
  local out prompt schema prior seed reply
  out=$(stage_file "$idx" "$stage")
  prompt="${out%.json}.prompt.txt"
  schema="${out%.json}.schema.json"

  # response_format takes one concrete schema, so the stage's own object is
  # pulled out of the shared file. A stage with no schema is a bug, not a
  # free-form call.
  jq -e --arg s "$stage" '.[$s]' prompts/brief-stage.schema.json > "$schema" \
    || { echo "no schema for stage $stage in prompts/brief-stage.schema.json" >&2; exit 2; }

  local -a fill=(prompts/brief-"$stage".md
    --set-file RESEARCH="$RESEARCH"
    --set-file KEYWORD_CHOICE="$KEYWORDS"
    --set PAGE_PURPOSE="$PURPOSE")
  prior=$(prior_json "$idx")
  if [[ "$prior" != "{}" ]]; then
    printf '%s\n' "$prior" | jq . > "${out%.json}.prior.json"
    fill+=(--set-file PRIOR="${out%.json}.prior.json")
  fi

  bash "$HERE/fill_prompt.sh" "${fill[@]}" > "$prompt"
  [[ -s "$prompt" ]] || { echo "filled prompt for $stage is empty" >&2; exit 2; }

  for seed in 1 2; do
    if reply=$(LLM_MODEL="${STAGE_MODEL:-qwen}" bash "$HERE/llm_call.sh" "$prompt" "$TEMP" "$seed" "$schema") \
       && jq -e . <<< "$reply" > /dev/null 2>&1; then
      printf '%s\n' "$reply" | jq . > "$out"
      echo "wrote $out (seed $seed)" >&2
      return 0
    fi
    echo "stage $stage: unusable reply at seed $seed" >&2
  done
  echo "stage $stage failed twice: read $prompt and fix the input before retrying" >&2
  exit 3
}

# Redo drops that stage and everything after it: a changed stage invalidates the
# stages that were built on it.
if [[ -n "$REDO" ]]; then
  found=0 i=1
  for s in "${STAGES[@]}"; do
    if [[ "$s" == "$REDO" ]]; then found=1; fi
    # Once the redone stage is reached, it and every later stage go: they were
    # built on the version being replaced.
    if (( found )); then
      f=$(stage_file "$i" "$s")
      # The prompt, schema and prior sidecars go with the stage they belong to,
      # otherwise a stale prior sits next to a regenerated stage.
      rm -f "$f" "${f%.json}".prompt.txt "${f%.json}".schema.json "${f%.json}".prior.json
    fi
    i=$((i + 1))
  done
  (( found )) || { echo "unknown stage: $REDO (stages: ${STAGES[*]})" >&2; exit 1; }
fi

i=1
for stage in "${STAGES[@]}"; do
  file=$(stage_file "$i" "$stage")
  if [[ ! -r "$file" ]]; then
    run_stage "$i" "$stage"
    remaining=$(( ${#STAGES[@]} - i ))
    if (( remaining > 0 )); then
      echo "review $file, then rerun for the next stage ($remaining left)" >&2
    else
      echo "all stages done: ${STAGE_DIR}" >&2
    fi
    jq . "$file"
    exit 0
  fi
  i=$((i + 1))
done

echo "every stage already exists in $STAGE_DIR. Use --redo <stage> to rebuild one." >&2
# Name the stage files rather than globbing: the prompt, schema and prior
# sidecars sit beside them and must not be merged in.
files=(); i=1
for stage in "${STAGES[@]}"; do files+=("$(stage_file "$i" "$stage")"); i=$((i + 1)); done
jq -n --arg names "${STAGES[*]}" --slurpfile all <(cat "${files[@]}") \
  '[$names | split(" "), $all] | transpose | map({(.[0]): .[1]}) | add'
