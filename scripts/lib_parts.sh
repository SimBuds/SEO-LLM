#!/usr/bin/env bash
# Shared helpers for draft_sections.sh, rewrite_sections.sh, and check.sh.
# Source it; it defines functions and constants only.
# verify_part expects ROOT, BRIEF, and VERIFY_MODEL to be set by the caller.

# Sentences with absolute wording, used by the verifier hints and the checks.
# A sentence starts at a line start or after whitespace, never mid-word, and a
# dot with no space after it is part of a word ("example.com", ".org"), not a
# sentence end. Without both, "required example.com in all samples." matched as
# the phantom sentence "com in all samples." (found in the 2026-09-20 QA run).
ABSOLUTE_SENTENCE='(^|[[:space:]])([^.!?]|\.[^[:space:]])*\b(all|every|always|never|guarantee[sd]?|any circumstances|complete control|entirely|without compromise)\b([^.!?]|\.[^[:space:]])*[.!?]'

# Numbers as written (4-6, 2.5, $2,500, 9.25), normalized: commas and
# trailing dots dropped so "$2,500." and "2500" compare equal.
# Ordered-list markers ("1. ") are dropped first: they are not claims.
numbers() { sed -E 's/^[[:space:]]*[0-9]+\.[[:space:]]//' | grep -oE '[0-9][0-9,.]*' | sed -E 's/,//g; s/\.+$//' | sort -u || true; }

# draft_factor <word_count>: how far above word_count the draft aims, in
# percent. A lower factor for short pages was tried and left a thin-facts
# 1000-word page 28% short, so one factor applies to every length and an
# overshoot only warns. DRAFT_FACTOR overrides it.
#
# 135 was set from an assumed 20-35% cut by the rewrite and its re-verification.
# Two measured runs cut 13% and 17.5%, so the article landed 39% over its target
# on 2026-09-21 (2000 asked, 2790 delivered). 120 is the factor that lands on
# target at the cut actually observed: 2000 * 1.20 = 2400, less 17.5% is 1980.
# Re-measure after any prompt change that affects how much filler the draft
# writes, because that is what the rewrite removes.
draft_factor() {
  echo "${DRAFT_FACTOR:-120}"
}

# restore_headings <heading-source> <part>: headings are fixed, but the model
# rewords them (often stuffing keywords in). When the part has the same number
# of headings at the same levels, put the source's wording back. Anything else
# is left for check.sh to fail.
restore_headings() {
  local src=$1 part=$2
  [[ "$(grep -oE '^#{1,6} ' "$src")" == "$(grep -oE '^#{1,6} ' "$part")" ]] || return 0
  awk 'NR == FNR { if ($0 ~ /^#{1,6} /) h[++n] = $0; next }
       /^#{1,6} / { print h[++i]; next } { print }' "$src" "$part" > "$part.tmp"
  mv "$part.tmp" "$part"
}

# unbold <part>: the prompts never ask for bold, but the model bolds keyword
# phrases anyway. Strip bold from every non-heading line. The file is only
# rewritten when there is bold to strip: sed -i writes a new file even when
# nothing matches, and the new mtime made a resumed rewrite re-edit every part
# after one was redrafted (2026-09-22).
unbold() {
  grep -qE '^[^#].*\*\*[^*]+\*\*' "$1" || return 0
  sed -i -E '/^#/!s/\*\*([^*]+)\*\*/\1/g' "$1"
}

# clean_outline <outline>: an outline is headings plus, directly under each H2,
# one _Intent: line and one Keywords: line. The model puts those lines under the
# H1 or under H3s, and sometimes writes a paragraph under a heading, and
# check.sh outline rightly FAILs on both. Three prompt wordings were measured
# against this in Phases 24 and 25 and each traded one failure for another, so
# the repair is deterministic: keep headings, blank lines and the two guidance
# slots under an H2, drop the rest, and say what was dropped. Returns 0 always;
# whether the result is a valid outline stays check.sh's decision.
# An H3 under the Conclusion is dropped as well: check.sh already says the
# Conclusion should have none, prompts/conclusion.md does not write one, and the
# drafter then fails the part twice on "headings differ from the outline block"
# and stops the whole run. Seen 2026-09-22 on "### Measure Your Space and Observe
# Your Cat".
clean_outline() {
  local f=$1 removed
  removed=$(awk '
    /^## / { concl = ($0 ~ /^## Conclusion[[:space:]]*$/); slot = 2; next }
    /^#{1,6} / {
      if (concl && $0 ~ /^### /) { printf "  %d: %s\n", FNR, substr($0, 1, 90); next }
      slot = 0; next
    }
    /^[[:space:]]*$/ { next }
    /^(_Intent:|Keywords:)/ { if (slot > 0) { slot--; next } }
    { printf "  %d: %s\n", FNR, substr($0, 1, 90) }
  ' "$f")
  [[ -z "$removed" ]] && return 0
  awk '
    /^## / { concl = ($0 ~ /^## Conclusion[[:space:]]*$/); slot = 2; print; next }
    /^#{1,6} / {
      if (concl && $0 ~ /^### /) { next }
      slot = 0; print; next
    }
    /^[[:space:]]*$/ { print; next }
    /^(_Intent:|Keywords:)/ { if (slot > 0) { slot--; print } ; next }
    { next }
  ' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
  echo "outline repair removed $(grep -c . <<< "$removed") line(s) that do not belong in an outline:" >&2
  printf '%s\n' "$removed" >&2
}

# verify_part <name> <part> <dir> <heading-source or ""> <check command...>
# A second call lists sentences the facts do not support (prompts/verify.md,
# schema-constrained) with a replacement for each. Replacements are applied as
# literal string swaps; the report is kept as <dir>/<name>.verify.json and the
# text before verification as <dir>/<name>.unverified.md. If the verified part
# fails the check command, the unverified text is restored. Does nothing when
# the report already exists.
verify_part() {
  local name=$1 out=$2 dir=$3 headsrc=$4; shift 4
  local report="$dir/$name.verify.json" prompt="$dir/$name.verify.prompt.txt"
  local orig="$dir/$name.unverified.md"
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
  # Tidy the seams a swap leaves behind. The punctuation rule only closes a gap
  # when the punctuation ends a word: without the trailing context it deleted the
  # space before every dotted token, turning "the .example domain" into
  # "the.example domain" (found in the 2026-09-20 QA run).
  ' "$report" | sed -E 's/ {2,}/ /g; s/ +([.,;:])([[:space:]]|$)/\1\2/g; s/^ +//' > "$out"
  if [[ -n "$headsrc" ]]; then restore_headings "$headsrc" "$out"; fi
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
