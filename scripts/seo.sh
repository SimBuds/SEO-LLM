#!/usr/bin/env bash
# Interactive front door for the pipeline.
#
# Usage: seo.sh [slug]
#
# Shows every stage of a page with its state, read from the files on disk, and
# runs the stage you pick. Nothing is remembered between runs: the artifacts are
# the state, so resuming and rerunning behave the same whether you left five
# minutes ago or last month.
#
# Env: RESEARCH_DIR (default research), BRIEFS_DIR (default briefs),
#      OUTPUTS_DIR (default outputs). The three exist so a test run can point
#      the whole tree at a scratch directory.
#
# Every stage runs from here. "a" runs each ready stage in turn, stopping at the
# first stage that needs you to read something or type something.

# No `set -e`: a failing stage must return to the menu, not end the session.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RESEARCH="${RESEARCH_DIR:-$ROOT/research}"
BRIEFS="${BRIEFS_DIR:-$ROOT/briefs}"
OUTPUTS="${OUTPUTS_DIR:-$ROOT/outputs}"
LLM_HOST="${LLM_HOST:-http://localhost:8080}"

if [[ -t 1 ]] && command -v tput > /dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
  BOLD=$(tput bold); DIM=$(tput dim); RESET=$(tput sgr0)
  GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RED=$(tput setaf 1)
else
  BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""; RED=""
fi

say()  { printf '%s\n' "$*"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$RESET"; }
err()  { printf '%s%s%s\n' "$RED" "$*" "$RESET"; }

# --- state ------------------------------------------------------------------
# Each stage answers three questions: is it done, can it run, and what does the
# artifact say. STATE and DETAIL are filled by stage_status for the stage given.

stage_count_brief_stages() {
  local dir="$RESEARCH/$SLUG/brief-stages"
  [[ -d "$dir" ]] || { echo 0; return; }
  local n=0 f
  # Each stage keeps .schema.json and .prior.json sidecars beside its data file,
  # and both match the same glob, so counting the glob double-counts a stage.
  for f in "$dir"/0[1-9]-*.json; do
    [[ -e "$f" ]] || continue
    case "$f" in *.schema.json|*.prior.json) continue ;; esac
    n=$((n + 1))
  done
  echo "$n"
}

stage_status() { # stage_status <stage-id>; sets STATE and DETAIL
  local id="$1"
  STATE="blocked"; DETAIL=""
  case "$id" in
    page)
      if [[ -r "$RESEARCH/$SLUG/page.json" ]]; then
        STATE="done"
        if jq -e '.exists' "$RESEARCH/$SLUG/page.json" > /dev/null 2>&1; then
          DETAIL=$(jq -r '"live page, title \(.title | length) chars, \(.word_count) words" +
                          (if (.meta_description | length) == 0 then ", no description" else "" end)' \
                        "$RESEARCH/$SLUG/page.json" 2>/dev/null)
        else
          DETAIL="new page, nothing live yet"
        fi
      else
        STATE="ready"
      fi
      ;;
    collect)
      if [[ -r "$RESEARCH/$SLUG/research.json" ]]; then
        STATE="done"
        DETAIL=$(jq -r '"\(.keywords | length) keywords, \(.competitors | map(select(.fetched)) | length)/\(.competitors | length) competitors, \(.inputs | length) exports"' \
                      "$RESEARCH/$SLUG/research.json" 2>/dev/null)
      elif [[ -r "$RESEARCH/$SLUG/page.json" ]]; then
        STATE="ready"
      else
        DETAIL="needs the page check first"
      fi
      ;;
    keywords)
      if [[ -r "$RESEARCH/$SLUG/keywords.json" ]]; then
        STATE="done"
        DETAIL=$(jq -r '"\(.primary_keyword) (+\(.secondary_keywords | length) secondary), \(.intent.format)"' \
                      "$RESEARCH/$SLUG/keywords.json" 2>/dev/null)
      elif [[ -r "$RESEARCH/$SLUG/research.json" ]]; then
        STATE="ready"
      else
        DETAIL="needs research.json"
      fi
      ;;
    brief_stages)
      local n; n=$(stage_count_brief_stages)
      if (( n >= 4 )); then
        STATE="done"; DETAIL="all 4 stages approved"
      elif [[ -r "$RESEARCH/$SLUG/keywords.json" ]]; then
        STATE="ready"; DETAIL="$n of 4 stages written"
      else
        DETAIL="needs keywords.json"
      fi
      ;;
    brief)
      local n; n=$(stage_count_brief_stages)
      if [[ -r "$BRIEFS/$SLUG.json" ]]; then
        STATE="done"
        DETAIL=$(jq -r '"\(.word_count) words, \(.keywords | length) keywords, \(.facts | length) facts"' \
                      "$BRIEFS/$SLUG.json" 2>/dev/null)
      elif (( n >= 4 )); then
        STATE="ready"
      else
        DETAIL="needs all 4 brief stages"
      fi
      ;;
    outline)
      if [[ -r "$OUTPUTS/$SLUG/outline.md" ]]; then
        STATE="done"
        DETAIL="$(grep -c '^## ' "$OUTPUTS/$SLUG/outline.md" 2>/dev/null) H2 sections"
      elif [[ -r "$BRIEFS/$SLUG.json" ]]; then
        STATE="ready"
      else
        DETAIL="needs the brief"
      fi
      ;;
    draft)
      if [[ -r "$OUTPUTS/$SLUG/draft.md" ]]; then
        STATE="done"; DETAIL="$(wc -w < "$OUTPUTS/$SLUG/draft.md" | tr -d ' ') words"
      elif [[ -r "$OUTPUTS/$SLUG/outline.md" ]]; then
        STATE="ready"
      else
        DETAIL="needs the outline"
      fi
      ;;
    rewrite)
      if [[ -r "$OUTPUTS/$SLUG/final.md" ]]; then
        STATE="done"; DETAIL="$(wc -w < "$OUTPUTS/$SLUG/final.md" | tr -d ' ') words"
      elif [[ -r "$OUTPUTS/$SLUG/draft.md" ]]; then
        STATE="ready"
      else
        DETAIL="needs the draft"
      fi
      ;;
    review)
      if [[ -r "$OUTPUTS/$SLUG/final.md" ]]; then
        STATE="ready"
      else
        DETAIL="needs final.md"
      fi
      ;;
  esac
}

STAGE_IDS=(page collect keywords brief_stages brief outline draft rewrite review)
STAGE_LABELS=("Page check" "Collect research" "Keyword choice" "Brief stages" "Write the brief" "Outline" "Draft" "Rewrite" "Review")

router_line() {
  local served
  served=$(curl -s --max-time 3 "$LLM_HOST/models" 2>/dev/null | jq -r '.data[]?.id' 2>/dev/null | paste -sd' ')
  if [[ -z "$served" ]]; then
    printf '%srouter: unreachable at %s%s\n' "$RED" "$LLM_HOST" "$RESET"
  elif [[ " $served " == *" qwen "* ]]; then
    printf '%srouter: serving qwen%s\n' "$GREEN" "$RESET"
  else
    printf '%srouter: up but no qwen (serving: %s)%s\n' "$YELLOW" "$served" "$RESET"
  fi
}

render_menu() {
  local i=1 id label next=""
  printf '\n%sSEO pipeline: %s%s\n' "$BOLD" "$SLUG" "$RESET"
  router_line
  printf '\n'
  for id in "${STAGE_IDS[@]}"; do
    label="${STAGE_LABELS[$((i - 1))]}"
    stage_status "$id"
    local mark="" colour="$DIM"
    case "$STATE" in
      done)  colour="$GREEN" ;;
      ready) colour="$RESET"; [[ -z "$next" ]] && { next="$i"; mark="  <- next"; } ;;
    esac
    printf '  %s%d [%-7s] %-18s %s%s%s\n' "$colour" "$i" "$STATE" "$label" "$DETAIL" "$mark" "$RESET"
    i=$((i + 1))
  done
  printf '\n  %sa%s run all ready stages   %ss%s switch page   %sq%s quit\n' \
    "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET"
}

# --- actions ----------------------------------------------------------------

run_check() { # run_check <check.sh args...>: print the verdict, never abort
  bash "$ROOT/scripts/check.sh" "$@"
  local rc=$?
  (( rc == 0 )) && say "${GREEN}check passed${RESET}" || err "check failed (exit $rc)"
  return $rc
}

action_page() {
  local url
  if [[ -r "$RESEARCH/$SLUG/page.json" ]]; then
    jq . "$RESEARCH/$SLUG/page.json"
    read -r -p "Replace this snapshot? [y/N] " yn
    [[ "$yn" == [yY]* ]] || { say "kept"; return 0; }
  fi
  say "Does this page already exist? Paste its URL, or press enter for a new page."
  read -r -p "URL: " url
  if [[ -z "$url" ]]; then
    bash "$ROOT/scripts/fetch_page.sh" --absent "$RESEARCH/$SLUG/page.json" || return 1
  else
    bash "$ROOT/scripts/fetch_page.sh" "$url" "$RESEARCH/$SLUG/page.json" || {
      err "the fetch failed, see the message above. A 404 usually means the page does not exist, so answer with no URL."
      return 1
    }
  fi
  jq . "$RESEARCH/$SLUG/page.json"
}

action_collect() {
  local dir="$RESEARCH/$SLUG"
  mkdir -p "$dir/inputs"
  local n_inputs n_urls
  n_inputs=$(find "$dir/inputs" -maxdepth 1 -type f \( -name '*.csv' -o -name '*.tsv' -o -name '*.txt' \) | wc -l)
  n_urls=0
  [[ -r "$dir/competitors.txt" ]] && n_urls=$(grep -cve '^[[:space:]]*$' -e '^[[:space:]]*#' "$dir/competitors.txt")
  say ""
  say "Inputs for this page, both optional:"
  say "  exports     $dir/inputs/            ($n_inputs file(s) found)"
  say "  competitors $dir/competitors.txt    ($n_urls URL(s) found)"
  say ""
  say "Put the Ahrefs and Search Console exports in the inputs folder as downloaded,"
  say "and the top 3 to 5 ranking URLs in competitors.txt, one per line."
  if (( n_inputs == 0 && n_urls == 0 )); then
    read -r -p "Nothing to collect from yet. Continue anyway? [y/N] " yn
    [[ "$yn" == [yY]* ]] || return 0
  fi
  local fresh=""
  if [[ -r "$dir/research.json" ]]; then
    read -r -p "Refetch competitor pages instead of using the cache? [y/N] " yn
    [[ "$yn" == [yY]* ]] && fresh="--fresh"
  fi
  bash "$ROOT/scripts/research_collect.sh" "$SLUG" ${fresh:+$fresh} || return 1
  run_check research "$dir/research.json"
}

# Every model stage goes through these three first: the router has to be up, the
# page purpose has to exist, and an existing artifact has to be confirmed before
# it is replaced.

need_router() {
  local served
  served=$(curl -s --max-time 3 "$LLM_HOST/models" 2>/dev/null | jq -r '.data[]?.id' 2>/dev/null | paste -sd' ')
  if [[ " $served " != *" qwen "* ]]; then
    err "the router at $LLM_HOST is not serving qwen, so this stage cannot run."
    say "Check it with: systemctl --user is-active llama-server"
    return 1
  fi
  return 0
}

purpose_file() { printf '%s/%s/brief-stages/purpose.txt' "$RESEARCH" "$SLUG"; }

need_purpose() { # sets PURPOSE, asking once and reusing it afterwards
  local f; f=$(purpose_file)
  if [[ -r "$f" ]]; then
    PURPOSE=$(cat "$f")
    return 0
  fi
  say "In one line: what is this page for, and who is it for?"
  read -r -p "Purpose: " PURPOSE
  if [[ -z "$PURPOSE" ]]; then
    err "the purpose is what keeps every later stage on the same page, so it cannot be empty."
    return 1
  fi
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$PURPOSE" > "$f"
  return 0
}

confirm_replace() { # confirm_replace <path> <description>
  [[ -e "$1" ]] || return 0
  say "$2 already exists."
  read -r -p "Replace it? [y/N] " yn
  [[ "$yn" == [yY]* ]]
}

action_keywords() {
  need_router || return 1
  need_purpose || return 1
  local dir="$RESEARCH/$SLUG"
  confirm_replace "$dir/keywords.json" "A keyword choice" || { say "kept"; return 0; }

  local seed=1
  while true; do
    say "calling the model (temperature 0.2, seed $seed)..."
    bash "$ROOT/scripts/fill_prompt.sh" "$ROOT/prompts/keywords.md" \
      --set-file RESEARCH="$dir/research.json" \
      --set PAGE_PURPOSE="$PURPOSE" > "$dir/_keywords_prompt.txt" \
    && bash "$ROOT/scripts/llm_call.sh" "$dir/_keywords_prompt.txt" 0.2 "$seed" \
         "$ROOT/prompts/keywords.schema.json" > "$dir/keywords.json" || {
      err "the call failed, see the message above. The prompt is kept at $dir/_keywords_prompt.txt"
      return 1
    }
    jq . "$dir/keywords.json"
    if run_check keywords "$dir/keywords.json" "$dir/research.json"; then
      say ""
      say "Read the rationale against your research: it is the one field no check can verify."
      return 0
    fi
    (( seed >= 2 )) && {
      err "it failed at both seeds. The research may not support a confident choice."
      say "Edit $dir/research.json, or pick the primary keyword yourself in $dir/keywords.json"
      return 1
    }
    read -r -p "Retry with seed 2? [Y/n] " yn
    [[ "$yn" == [nN]* ]] && return 1
    seed=2
  done
}

action_brief_stage() {
  need_router || return 1
  need_purpose || return 1
  local n; n=$(stage_count_brief_stages)
  local names=(intent structure targets facts)
  if (( n >= 4 )); then
    say "All four stages are written. To rebuild one, and everything after it:"
    say "  bash scripts/brief_stages.sh $SLUG --redo <intent|structure|targets|facts>"
    return 0
  fi
  say "running brief stage $((n + 1)) of 4 (${names[$n]})..."
  bash "$ROOT/scripts/brief_stages.sh" "$SLUG" --purpose "$PURPOSE" || {
    err "the stage failed, see the message above."
    return 1
  }
  say ""
  case "${names[$n]}" in
    intent)    say "Check: is the audience a real description, not a category? Is reader_goal the reader's goal?" ;;
    structure) say "Check: every section carries a source. Challenge any you cannot find in the research." ;;
    targets)   say "Check the call to action. This is where a page promises something the business does not offer." ;;
    facts)     say "Check: every qualifier kept (most, from, up to), and read 'omitted' as closely as 'facts'." ;;
  esac
  say "Edit the file directly to change a value. A rerun resamples everything."
  say "To rebuild a stage and everything after it: bash scripts/brief_stages.sh $SLUG --redo <stage>"
}

action_brief() {
  local brief="$BRIEFS/$SLUG.json"
  local force=""
  if [[ -e "$brief" ]]; then
    jq . "$brief"
    say "A brief already exists. Replacing it discards any edit you made to it."
    read -r -p "Replace it? [y/N] " yn
    [[ "$yn" == [yY]* ]] || { say "kept"; return 0; }
    force="--force"
  fi
  bash "$ROOT/scripts/brief_stages.sh" "$SLUG" --merge ${force:+$force} || {
    err "the merge failed, see the message above."
    return 1
  }
  say ""
  say "word_count comes from the competitor median, not from the model."
  say "To use a different length, edit $brief now, before the outline."
}

action_outline() {
  need_router || return 1
  local out="$OUTPUTS/$SLUG"
  confirm_replace "$out/outline.md" "An outline" || { say "kept"; return 0; }
  mkdir -p "$out"
  local seed=1
  while true; do
    say "calling the model (temperature 0.3, seed $seed)..."
    bash "$ROOT/scripts/fill_prompt.sh" "$ROOT/prompts/outline.md" --brief "$BRIEFS/$SLUG.json" \
      > "$out/_outline_prompt.txt" \
    && bash "$ROOT/scripts/llm_call.sh" "$out/_outline_prompt.txt" 0.3 "$seed" > "$out/outline.md" || {
      err "the call failed, see the message above."
      return 1
    }
    cat "$out/outline.md"
    if run_check outline "$out/outline.md" "$BRIEFS/$SLUG.json"; then
      return 0
    fi
    (( seed >= 3 )) && {
      err "it failed at seeds 1, 2 and 3. Read $out/outline.md and fix it by hand, or revisit the brief."
      return 1
    }
    say "A failure here is usually body text where only headings belong, most often the CTA."
    read -r -p "Retry with seed $((seed + 1))? [Y/n] " yn
    [[ "$yn" == [nN]* ]] && return 1
    seed=$((seed + 1))
  done
}

action_draft() {
  need_router || return 1
  local out="$OUTPUTS/$SLUG" fresh=""
  if [[ -r "$out/draft.md" ]]; then
    say "A draft exists. Rerunning keeps every part that already passed its check."
    read -r -p "Redo every part from scratch instead? [y/N] " yn
    [[ "$yn" == [yY]* ]] && fresh="--fresh"
  fi
  say "one model call per part, then a fact check per part. This takes a minute or two."
  bash "$ROOT/scripts/draft_sections.sh" "$BRIEFS/$SLUG.json" ${fresh:+$fresh} || {
    err "the draft stopped, see the message above."
    local stuck
    stuck=$(find "$out/sections" -maxdepth 1 -name '*.ERROR.md' 2>/dev/null | head -1)
    [[ -n "$stuck" ]] && say "The part that failed twice is kept at: $stuck"
    return 1
  }
  run_check draft "$out/draft.md" "$out/outline.md" "$BRIEFS/$SLUG.json" draft
}

action_rewrite() {
  need_router || return 1
  local out="$OUTPUTS/$SLUG" fresh=""
  if [[ -r "$out/final.md" ]]; then
    say "A final article exists. Rerunning keeps every edit that is newer than its input."
    read -r -p "Redo every part from scratch instead? [y/N] " yn
    [[ "$yn" == [yY]* ]] && fresh="--fresh"
  fi
  say "editing each part for readability, then re-checking its facts..."
  bash "$ROOT/scripts/rewrite_sections.sh" "$BRIEFS/$SLUG.json" ${fresh:+$fresh} || {
    err "the rewrite stopped, see the message above."
    return 1
  }
  run_check draft "$out/final.md" "$out/outline.md" "$BRIEFS/$SLUG.json"
}

action_review() {
  local out="$OUTPUTS/$SLUG" rejected
  say ""
  say "${BOLD}Claims the fact checker flagged but could not safely fix.${RESET}"
  say "They are still in the article, and they are yours to judge:"
  rejected=$(jq -r '.issues[]? | select(.accepted == false) | "  [\(.kind)] \(.sentence)"' \
               "$out"/*/*.verify.json 2>/dev/null)
  if [[ -z "$rejected" ]]; then
    say "  none, every flagged sentence was either fixed or supported"
  else
    printf '%s\n' "$rejected"
  fi
  say ""
  say "${BOLD}Lengths${RESET}"
  printf '  brief target  %s words\n' "$(jq -r .word_count "$BRIEFS/$SLUG.json" 2>/dev/null)"
  [[ -r "$out/draft.md" ]] && printf '  draft         %s words\n' "$(wc -w < "$out/draft.md" | tr -d ' ')"
  [[ -r "$out/final.md" ]] && printf '  final         %s words\n' "$(wc -w < "$out/final.md" | tr -d ' ')"
  say ""
  say "${BOLD}Read it:${RESET} $out/final.md"
  say "Then add what no model can: first-hand detail, original data, a named author."
}

# Stages that need you to type or place something, so run_all stops before them,
# and stages you have to read, so run_all stops after them.
NEEDS_INPUT=" page collect "
STOP_AFTER=" brief_stages "

run_all() {
  local id idx=0 label ran=0
  for id in "${STAGE_IDS[@]}"; do
    label="${STAGE_LABELS[$idx]}"
    idx=$((idx + 1))
    stage_status "$id"
    [[ "$STATE" == "done" ]] && continue
    if [[ "$STATE" == "blocked" ]]; then
      warn "stopped: $label is blocked ($DETAIL)"
      return 1
    fi
    if [[ "$NEEDS_INPUT" == *" $id "* ]]; then
      say ""
      warn "stopped at $label, which needs you."
      say "Pick it from the menu when you are ready."
      return 0
    fi
    say ""
    say "${BOLD}--- $label${RESET}"
    case "$id" in
      keywords)     action_keywords ;;
      brief_stages) action_brief_stage ;;
      brief)        action_brief ;;
      outline)      action_outline ;;
      draft)        action_draft ;;
      rewrite)      action_rewrite ;;
      review)       action_review ;;
    esac || { err "stopped: $label did not finish."; return 1; }
    ran=$((ran + 1))
    if [[ "$STOP_AFTER" == *" $id "* ]]; then
      say ""
      warn "stopped after $label so you can read it. Choose a again to carry on."
      return 0
    fi
  done
  (( ran == 0 )) && say "nothing to do: every stage is done."
  return 0
}

# --- slug picking -----------------------------------------------------------

list_slugs() {
  [[ -d "$RESEARCH" ]] || return 0
  find "$RESEARCH" -mindepth 1 -maxdepth 1 -type d ! -name '_*' -printf '%f\n' 2>/dev/null | sort
}

valid_slug() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]; }

pick_slug() {
  local slugs choice i=1
  mapfile -t slugs < <(list_slugs)
  if (( ${#slugs[@]} > 0 )); then
    say ""
    say "Pages with research so far:"
    for s in "${slugs[@]}"; do printf '  %d  %s\n' "$i" "$s"; i=$((i + 1)); done
    say "  n  start a new page"
  else
    say "No pages yet."
  fi
  while true; do
    read -r -p "Choose a page (number), or type a new slug: " choice || return 1
    [[ -z "$choice" ]] && continue
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#slugs[@]} )); then
      SLUG="${slugs[$((choice - 1))]}"; return 0
    fi
    [[ "$choice" == "n" ]] && { read -r -p "New slug (lowercase, hyphens): " choice; }
    if valid_slug "$choice"; then SLUG="$choice"; return 0; fi
    err "a slug is lowercase letters, digits and hyphens, for example about-us"
  done
}

# --- main -------------------------------------------------------------------

SLUG="${1:-}"

if [[ ! -t 0 ]]; then
  # Not a terminal: print the state once and leave, rather than looping on EOF.
  if [[ -z "$SLUG" ]]; then
    echo "seo.sh needs a terminal, or a slug: seo.sh <slug>" >&2
    exit 2
  fi
  render_menu
  exit 0
fi

if [[ -z "$SLUG" ]]; then
  pick_slug || exit 0
elif ! valid_slug "$SLUG"; then
  err "not a valid slug: $SLUG"
  exit 2
fi

while true; do
  render_menu
  read -r -p "Choose: " choice || { say ""; exit 0; }
  case "$choice" in
    q|Q) exit 0 ;;
    s|S) pick_slug || exit 0 ;;
    a|A) run_all; read -r -p "Press enter for the menu. " _ ;;
    "")  ;;
    [1-9])
      idx=$((choice - 1))
      if (( idx >= ${#STAGE_IDS[@]} )); then err "no such option"; continue; fi
      id="${STAGE_IDS[$idx]}"
      stage_status "$id"
      if [[ "$STATE" == "blocked" ]]; then
        warn "${STAGE_LABELS[$idx]} is blocked: $DETAIL"
        continue
      fi
      case "$id" in
        page)         action_page ;;
        collect)      action_collect ;;
        keywords)     action_keywords ;;
        brief_stages) action_brief_stage ;;
        brief)        action_brief ;;
        outline)      action_outline ;;
        draft)        action_draft ;;
        rewrite)      action_rewrite ;;
        review)       action_review ;;
      esac
      read -r -p "Press enter for the menu. " _
      ;;
    *) err "no such option" ;;
  esac
done
