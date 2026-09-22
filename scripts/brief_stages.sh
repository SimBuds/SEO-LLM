#!/usr/bin/env bash
# Build a brief one approved stage at a time.
#
# Usage: brief_stages.sh <slug> [--purpose "one line"] [--redo <stage>] [--merge]
#
# Runs the first stage that has no file yet, writes it, prints it, and stops, so
# the user reads and edits it before the next stage runs. Rerunning continues
# from where it stopped. Each stage sees the stages already approved, so an edit
# to an earlier stage is carried into every later one.
#
# Reads research/<slug>/{research.json,keywords.json} and the purpose recorded on
# the first run. Writes research/<slug>/brief-stages/NN-<stage>.{json,prompt.txt}.
#
# --merge assembles the approved stages into briefs/<slug>.json and checks it.
#
# Env: RESEARCH_DIR (default research), BRIEFS_DIR (default briefs),
#      STAGE_MODEL (default the wrapper's qwen).
#
# Exit codes: 1 usage, 2 missing input, 3 the model's reply was unusable twice.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="${RESEARCH_DIR:-research}"
TEMP=0.3

# Stage order.
STAGES=(intent structure targets facts)

# Used when no competitor page was fetched, so a brief still has a target.
DEFAULT_WORDS=1000
MIN_WORDS=600
MAX_WORDS=3000

SLUG="${1:?usage: brief_stages.sh <slug> [--purpose \"one line\"] [--redo <stage>]}"; shift
PURPOSE="" REDO="" MERGE=0 FORCE=0 TYPE=""
while (( $# )); do
  case "$1" in
    --purpose) PURPOSE="${2:?--purpose needs text}"; shift 2 ;;
    --type)    TYPE="${2:?--type needs a content type}"; shift 2 ;;
    --redo)    REDO="${2:?--redo needs a stage name}"; shift 2 ;;
    --merge)   MERGE=1; shift ;;
    --force)   FORCE=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

# A bad type is an argument error, so it is caught before any file precondition:
# reporting "no research.json" for a misspelled type sends the reader to the
# wrong problem.
if [[ -n "$TYPE" ]]; then
  TYPE_PROMPT="prompts/brief-type-$TYPE.md"
  [[ -r "$TYPE_PROMPT" ]] || TYPE_PROMPT="$HERE/../prompts/brief-type-$TYPE.md"
  [[ -r "$TYPE_PROMPT" ]] || { echo "unknown content type: $TYPE (accepted: review)" >&2; exit 1; }
fi

DIR="$ROOT/$SLUG"
STAGE_DIR="$DIR/brief-stages"
RESEARCH="$DIR/research.json"
KEYWORDS="$DIR/keywords.json"
PURPOSE_FILE="$STAGE_DIR/purpose.txt"
# The type lives beside research.json rather than inside brief-stages/, because
# the keyword stage reads it and runs before brief-stages/ exists. An empty file
# means the type was asked for and declined, which is why the content is read
# rather than the file merely tested for existence.
TYPE_FILE="$DIR/type.txt"
RECORDED_TYPE=""
if [[ -r "$TYPE_FILE" ]]; then
  RECORDED_TYPE=$(tr -d '[:space:]' < "$TYPE_FILE")
fi

[[ -r "$RESEARCH" ]] || { echo "no $RESEARCH: run /seo-research $SLUG first" >&2; exit 2; }
[[ -r "$KEYWORDS" ]] || { echo "no $KEYWORDS: run /seo-keywords $SLUG first" >&2; exit 2; }
mkdir -p "$STAGE_DIR"

# The content type is recorded once and reused, the same way the purpose is. A
# type that changed between stages would produce a brief half-shaped as one thing
# and half as another. Leaving it unset keeps the generic behaviour, which is
# what seo.sh and every slug written before this flag existed do.
if [[ -n "$TYPE" ]]; then
  if [[ -n "$RECORDED_TYPE" && "$RECORDED_TYPE" != "$TYPE" ]]; then
    echo "$SLUG is already recorded as $RECORDED_TYPE, not $TYPE." >&2
    echo "A brief keeps one type. Change it with 'e' at the menu, which clears the" >&2
    echo "stages written from the old type, or start a new slug." >&2
    exit 1
  fi
  printf '%s\n' "$TYPE" > "$TYPE_FILE"
  RECORDED_TYPE="$TYPE"
fi

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

  # The facts stage reads a source document instead of the research: business
  # specifics come from what the user supplied, never from competitors.
  local source=""
  if [[ "$stage" == facts ]]; then
    source="${BRIEFS_DIR:-briefs}/_ingest/$SLUG.txt"
    if [[ ! -s "$source" ]]; then
      # No source means no facts. That is a real answer, so it is recorded
      # without spending a call on it.
      jq -n '{facts: [], omitted: ["no source document at briefs/_ingest/<slug>.txt, so no business specifics were available"]}' > "$out"
      echo "wrote $out (no source document, facts left empty)" >&2
      return 0
    fi
  fi

  local -a fill=(prompts/brief-"$stage".md
    --set-file RESEARCH="$RESEARCH"
    --set-file KEYWORD_CHOICE="$KEYWORDS"
    --set PAGE_PURPOSE="$PURPOSE")
  # prompts/brief-facts.md is the only template with {{SOURCE_TEXT}}, and it was
  # never passed: the stage worked only because a missing source returns early.
  # Found 2026-09-21, the first time a source document existed.
  [[ -n "$source" ]] && fill+=(--source "$source")
  prior=$(prior_json "$idx")
  if [[ "$prior" != "{}" ]]; then
    printf '%s\n' "$prior" | jq . > "${out%.json}.prior.json"
    fill+=(--set-file PRIOR="${out%.json}.prior.json")
  fi

  bash "$HERE/fill_prompt.sh" "${fill[@]}" > "$prompt"
  # The intent and structure stages are type-aware: one names the page and the
  # other decides its sections, and those are the two answers a content type
  # changes. A guide titled "Best ... Top Picks" over criteria sections is what
  # happens when only the second one knows (measured 2026-09-22). The block is
  # appended to the filled prompt rather than filled into the template, so a run
  # with no type produces a byte-identical prompt to before this flag existed.
  if [[ ( "$stage" == structure || "$stage" == intent ) && -n "$RECORDED_TYPE" ]]; then
    local recorded type_file
    recorded="$RECORDED_TYPE"
    type_file="prompts/brief-type-$recorded.md"
    [[ -r "$type_file" ]] || type_file="$HERE/../prompts/brief-type-$recorded.md"
    printf '\n' >> "$prompt"
    cat "$type_file" >> "$prompt"
  fi
  [[ -s "$prompt" ]] || { echo "filled prompt for $stage is empty" >&2; exit 2; }

  for seed in 1 2; do
    if reply=$(LLM_MODEL="${STAGE_MODEL:-qwen}" bash "$HERE/llm_call.sh" "$prompt" "$TEMP" "$seed" "$schema") \
       && jq -e . <<< "$reply" > /dev/null 2>&1; then
      printf '%s\n' "$reply" | jq . > "$out"
      echo "wrote $out (seed $seed)" >&2
      # The structure stage is checked as it is written, because an ungrounded
      # section reaches the brief and then the page, and it is cheapest to catch
      # here where a reseed is one command.
      if [[ "$stage" == structure ]]; then
        bash "$HERE/check.sh" stage "$out" "$RESEARCH" "$KEYWORDS" || true
      fi
      # Same reasoning for the call to action: a retailer or brand it invents
      # travels into the draft as fact, and a reseed here is one command.
      if [[ "$stage" == targets ]]; then
        bash "$HERE/check.sh" targets "$out" "$RESEARCH" || true
      fi
      # A maxLength in the schema truncates rather than rejects, so a field that
      # lands exactly on its cap was cut mid-word. The schema is already beside
      # the data for this stage.
      bash "$HERE/check.sh" truncated "$out" "${out%.json}.schema.json" || true
      return 0
    fi
    echo "stage $stage: unusable reply at seed $seed" >&2
  done
  echo "stage $stage failed twice: read $prompt and fix the input before retrying" >&2
  exit 3
}

# The length target is computed, never asked of the model: the median of the
# competitor pages that were actually fetched, rounded to 50 and clamped. A
# number the research already implies should be auditable, not sampled.
target_words() {
  local counts median
  counts=$(jq -r '.competitor_word_counts // [] | .[]' "$RESEARCH" | sort -n)
  if [[ -z "$counts" ]]; then
    echo "$DEFAULT_WORDS"
    return 0
  fi
  median=$(awk '{a[NR]=$1} END {print (NR % 2) ? a[(NR+1)/2] : int((a[NR/2] + a[NR/2+1]) / 2)}' <<< "$counts")
  median=$(( (median + 25) / 50 * 50 ))
  (( median < MIN_WORDS )) && median=$MIN_WORDS
  (( median > MAX_WORDS )) && median=$MAX_WORDS
  echo "$median"
}

merge_brief() {
  local i=1 stage f words brief
  for stage in "${STAGES[@]}"; do
    f=$(stage_file "$i" "$stage")
    [[ -r "$f" ]] || { echo "stage $stage is missing ($f): run brief_stages.sh $SLUG first" >&2; exit 2; }
    i=$((i + 1))
  done
  brief="${BRIEFS_DIR:-briefs}/$SLUG.json"
  if [[ -e "$brief" ]] && (( ! FORCE )); then
    echo "$brief already exists. Review it, then rerun with --merge --force to replace it." >&2
    exit 2
  fi
  words=$(target_words)
  mkdir -p "$(dirname "$brief")"
  # The structure stage and the keyword choice ride along in the optional
  # research keys, so the outline stage can see what the ranking pages cover.
  jq -n \
    --slurpfile intent "$(stage_file 1 intent)" \
    --slurpfile structure "$(stage_file 2 structure)" \
    --slurpfile targets "$(stage_file 3 targets)" \
    --slurpfile facts "$(stage_file 4 facts)" \
    --slurpfile keywords "$KEYWORDS" \
    --slurpfile research "$RESEARCH" \
    --argjson words "$words" \
    --arg ctype "$RECORDED_TYPE" '
    {
      topic: $intent[0].topic,
      target_audience: $intent[0].target_audience,
      tone: $intent[0].tone,
      word_count: $words,
      keywords: $targets[0].keywords,
      cta: $targets[0].cta,
      facts: $facts[0].facts,
      search_intent: $keywords[0].intent,
      must_cover: [$structure[0].sections[].heading],
      questions: $structure[0].faq_questions
    }
    + (if $ctype == "" then {} else {content_type: $ctype} end)
    + (if $research[0].existing_page.exists then
         {existing_page: ($research[0].existing_page
            | {url, title, word_count} | with_entries(select(.value != null)))}
       else {} end)' > "$brief"
  echo "wrote $brief (word_count $words from the competitor median)" >&2
  bash "$HERE/check.sh" brief "$brief"
}

if (( MERGE )); then
  merge_brief
  jq . "${BRIEFS_DIR:-briefs}/$SLUG.json"
  exit 0
fi

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
      echo "all stages done. Review them, then rerun with --merge to write the brief." >&2
    fi
    jq . "$file"
    exit 0
  fi
  i=$((i + 1))
done

echo "every stage already exists in $STAGE_DIR. Use --merge to write the brief, or --redo <stage> to rebuild one." >&2
# Name the stage files rather than globbing: the prompt, schema and prior
# sidecars sit beside them and must not be merged in.
files=(); i=1
for stage in "${STAGES[@]}"; do files+=("$(stage_file "$i" "$stage")"); i=$((i + 1)); done
jq -n --arg names "${STAGES[*]}" --slurpfile all <(cat "${files[@]}") \
  '[$names | split(" "), $all] | transpose | map({(.[0]): .[1]}) | add'
