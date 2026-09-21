#!/usr/bin/env bash
# Deterministic checks on pipeline artifacts. One place for every rule the
# skills and README reference.
# Usage:
#   check.sh brief   <brief.json> [source.txt]
#   check.sh outline <outline.md> <brief.json>
#   check.sh section <part.md> <outline-block.md or -> <word-budget> <brief.json>
#   check.sh draft   <draft.md> <outline.md> <brief.json> [target-percent|draft]
#                    (defaults to 100; "draft" uses draft_factor, the aim of draft.md)
#   check.sh rewrite <new-part.md> <old-part.md> <brief.json>
#   check.sh research <research.json>
#   check.sh keywords <keywords.json> <research.json> [suggested.txt]
#                    (suggested.txt: keywords typed at the menu, one per line,
#                     grounding a term the research does not carry)
#   check.sh stage    <structure-stage.json> <research.json> <keywords.json>
# Prints "FAIL: ..." for problems that must be fixed or regenerated and
# "WARN: ..." for problems a human should look at. Exits 1 on any FAIL, else 0.

set -euo pipefail

MODE="${1:?mode required: brief|outline|section|draft|rewrite|research|keywords|stage}"; shift
FAILS=0
fail() { echo "FAIL: $*"; FAILS=$((FAILS + 1)); }
warn() { echo "WARN: $*"; }

# Numbers as written (4-6, 2.5, $2,500, 9.25), normalized: commas and
# trailing dots dropped so "$2,500." and "2500" compare equal.
# Ordered-list markers ("1. ") are dropped first: they are not claims.
numbers() { sed -E 's/^[[:space:]]*[0-9]+\.[[:space:]]//' | grep -oE '[0-9][0-9,.]*' | sed -E 's/,//g; s/\.+$//' | sort -u || true; }

source "$(dirname "${BASH_SOURCE[0]}")/lib_parts.sh"
absolutes() { grep -v '^#' "$1" | grep -oiE "$ABSOLUTE_SENTENCE" || true; }

brief_valid() {
  # The seven keys are required. The four research keys and content_type are
  # optional, so a brief written by hand or by /seo-ingest stays valid, and
  # anything else is a typo rather than a feature.
  jq -e '
    ((keys - ["cta","facts","keywords","target_audience","tone","topic","word_count",
              "search_intent","must_cover","questions","existing_page",
              "content_type"]) == [])
    and (["cta","facts","keywords","target_audience","tone","topic","word_count"] - keys == [])
    and (if has("search_intent") then (.search_intent | type == "object"
           and all(.type, .format, .angle; type == "string" and length > 0)) else true end)
    and (if has("content_type") then
           (.content_type as $c | ["review","roundup","guide"] | index($c) != null) else true end)
    and (if has("must_cover") then (.must_cover | type == "array"
           and all(.[]; type == "string" and length > 0)) else true end)
    and (if has("questions") then (.questions | type == "array"
           and all(.[]; type == "string" and length > 0)) else true end)
    and (if has("existing_page") then (.existing_page | type == "object"
           and (.url | type == "string" and length > 0)) else true end)
    and all(.topic, .target_audience, .tone, .cta; type == "string" and length > 0)
    and (.tone | IN("Professional","Authoritative","Conversational","Friendly","Technical"))
    and (.word_count | type == "number" and . == floor and . >= 1)
    and (.keywords | type == "array" and length >= 3 and length <= 6
         and all(.[]; type == "string" and length > 0))
    and (.facts | type == "array" and length <= 40
         and all(.[]; type == "string" and length > 0))' "$1" > /dev/null 2>&1
}

# Keywords holding a name written lowercase ("custom jewelry toronto"): a word
# the brief's prose only ever capitalizes. Pasting such a keyword verbatim
# produces "toronto" in running text.
proper_noun_keywords() {
  local prose caps lower k w
  prose=$(jq -r '[.topic, .target_audience, .cta, .facts[]] | join(" ")' "$1")
  caps=$(grep -oE '\b[A-Z][a-z]+\b' <<< "$prose" | sort -u || true)
  lower=$(grep -oE '\b[a-z]+\b' <<< "$prose" | sort -u || true)
  jq -r '.keywords[]' "$1" | while read -r k; do
    for w in $k; do
      if [[ "$w" != "${w^}" ]] && grep -qxF "${w^}" <<< "$caps" && ! grep -qxF "$w" <<< "$lower"; then
        echo "$k"; break
      fi
    done
  done
}

case "$MODE" in
brief)
  BRIEF="${1:?brief required}"; SOURCE="${2:-}"
  if ! brief_valid "$BRIEF"; then
    fail "$BRIEF does not match the brief schema (the 7 required keys, optional search_intent/must_cover/questions/existing_page, tone enum, integer word_count, 3-6 keywords, <=40 facts)"
  else
    CTA=$(jq -r .cta "$BRIEF")
    grep -qiE '\b(below|above|click|form|button)\b' <<< "$CTA" \
      && warn "cta references on-page UI: $CTA"
    jq -r '.keywords[]' "$BRIEF" | while read -r k; do
      [[ "$k" == *" "* ]] || warn "single-word keyword: $k"
      grep -qiE '\b(faq|contact|about)$' <<< "$k" && warn "page-name keyword, check it has search demand: $k"
    done || true
    (( $(jq '.facts | length' "$BRIEF") == 0 )) && warn "facts is empty: the draft will have no business specifics"
    if [[ -n "$SOURCE" ]]; then
      SRC_NUMS=$(numbers < "$SOURCE")
      jq -r '.facts[]' "$BRIEF" | while read -r f; do
        for n in $(numbers <<< "$f"); do
          grep -qxF "$n" <<< "$SRC_NUMS" || warn "fact has a number not in the source ($n): $f"
        done
      done || true
    fi
  fi
  ;;

outline)
  OUTLINE="${1:?outline required}"; BRIEF="${2:?brief required}"
  (( $(grep -c '^# ' "$OUTLINE") == 1 )) || fail "expected exactly one '# ' H1"
  grep -qx '## FAQ' "$OUTLINE" || fail "missing '## FAQ'"
  grep -qx '## Conclusion' "$OUTLINE" || fail "missing '## Conclusion'"
  STRAY=$(grep -nvE '^(#{1,3} .+|_Intent: .+_|Keywords: .+|)$' "$OUTLINE" || true)
  [[ -z "$STRAY" ]] || fail "body text in outline (only headings, _Intent:_ and Keywords: lines allowed):"$'\n'"$(head -5 <<< "$STRAY")"
  H2=$(grep -c '^## ' "$OUTLINE" || true); INTENT=$(grep -c '^_Intent: ' "$OUTLINE" || true)
  (( H2 == INTENT )) || fail "$H2 H2 sections but $INTENT _Intent:_ lines"
  # Size rules mirror the table in prompts/outline.md.
  WC=$(jq .word_count "$BRIEF")
  if   (( WC <= 1000 )); then MIN=2 MAX=3 FMIN=3 FMAX=3
  elif (( WC <= 1800 )); then MIN=3 MAX=5 FMIN=4 FMAX=5
  else                        MIN=4 MAX=6 FMIN=4 FMAX=6; fi
  TOPIC_H2=$(grep '^## ' "$OUTLINE" | grep -cvxE '## (FAQ|Conclusion)' || true)
  (( TOPIC_H2 >= MIN && TOPIC_H2 <= MAX )) || warn "$TOPIC_H2 topic sections; $MIN-$MAX expected for $WC words"
  FAQ_Q=$(awk '/^## /{f=($0=="## FAQ")} f && /^### /' "$OUTLINE" | wc -l)
  (( FAQ_Q >= FMIN && FAQ_Q <= FMAX )) || warn "$FAQ_Q FAQ questions; $FMIN-$FMAX expected for $WC words"
  H3MAX=$(( WC <= 1000 ? 2 : WC <= 1800 ? 3 : 4 ))
  awk -v max="$H3MAX" '/^## /{if (h && n > max) print h " (" n " H3s)"; h=$0; n=0; if (h ~ /^## (FAQ|Conclusion)$/) h=""} /^### /{n++} END{if (h && n > max) print h " (" n " H3s)"}' "$OUTLINE" \
    | while read -r l; do warn "more than $H3MAX H3s for $WC words: $l"; done
  CONC_H3=$(awk '/^## /{f=($0=="## Conclusion")} f && /^### /' "$OUTLINE" | wc -l)
  (( CONC_H3 == 0 )) || warn "Conclusion has $CONC_H3 H3s; it should have none"
  proper_noun_keywords "$BRIEF" | while read -r k; do
    grep -E '^#{1,3} ' "$OUTLINE" | grep -qF "$k" && warn "keyword with a lowercased name pasted into a heading: $k"
  done || true
  ;;

section)
  # One drafted part from draft_sections.sh. BLOCK is its outline block, or
  # "-" for the intro, which must have no headings at all.
  PART="${1:?section file required}"; BLOCK="${2:?outline block or - required}"
  WORDS="${3:?word budget required}"; BRIEF="${4:?brief required}"
  [[ -s "$PART" ]] || fail "section is empty"
  if [[ "$BLOCK" == "-" ]]; then
    grep -qE '^#' "$PART" && fail "intro contains a heading"
  else
    diff <(grep -E '^#{1,6} ' "$BLOCK") <(grep -E '^#{1,6} ' "$PART") > /dev/null \
      || fail "headings differ from the outline block:"$'\n'"$(diff <(grep -E '^#{1,6} ' "$BLOCK") <(grep -E '^#{1,6} ' "$PART") | grep '^[<>]' | head -6)"
  fi
  grep -qE '^(_Intent: |Keywords: )' "$PART" && fail "outline guidance lines left in"
  grep -qE '^```' "$PART" && fail "code fence in section"
  GOT=$(grep -v '^#' "$PART" | wc -w)
  (( GOT >= WORDS * 60 / 100 && GOT <= WORDS * 125 / 100 )) || warn "$GOT words; budget $WORDS"
  if [[ "$BLOCK" != "-" ]] && head -1 "$BLOCK" | grep -qx '## Conclusion'; then
    grep -qF "$(jq -r .cta "$BRIEF")" "$PART" || fail "CTA missing from the conclusion"
  fi
  jq -r '.keywords[]' "$BRIEF" | while read -r k; do
    grep -qiF "**$k**" "$PART" && warn "keyword bolded: $k"
  done || true
  ;;

draft)
  DRAFT="${1:?draft required}"; OUTLINE="${2:?outline required}"; BRIEF="${3:?brief required}"
  diff <(grep -E '^#{1,2} ' "$OUTLINE") <(grep -E '^#{1,2} ' "$DRAFT") > /dev/null \
    || fail "H1/H2 headings differ from the outline"
  grep -qE '^(_Intent: |Keywords: )' "$DRAFT" && fail "outline guidance lines left in the draft"
  grep -qxF '```' "$DRAFT" && warn "draft contains a code fence"
  PCT="${4:-100}"; [[ "$PCT" == draft ]] && PCT=$(draft_factor "$(jq .word_count "$BRIEF")")
  WC=$(( $(jq .word_count "$BRIEF") * PCT / 100 )); WORDS=$(wc -w < "$DRAFT")
  LO=$((WC * 85 / 100)); HI=$((WC * 115 / 100))
  (( WORDS >= LO && WORDS <= HI )) || warn "$WORDS words; target $WC (accepted $LO-$HI)"
  CTA=$(jq -r .cta "$BRIEF")
  awk '/^## /{f=($0=="## Conclusion")} f' "$DRAFT" | grep -qF "$CTA" || warn "CTA not found verbatim in the Conclusion"
  jq -r '.keywords[]' "$BRIEF" | while read -r k; do
    N=$(grep -v '^#' "$DRAFT" | grep -oiF "$k" | wc -l || true)
    (( N <= 2 )) || warn "keyword used $N times in the body (max 2): $k"
    grep -qiF "**$k**" "$DRAFT" && warn "keyword bolded: $k"
  done || true
  proper_noun_keywords "$BRIEF" | while read -r k; do
    N=$(grep -oF "$k" "$DRAFT" | wc -l || true)
    (( N == 0 )) || warn "keyword with a lowercased name pasted verbatim $N times: $k"
  done || true
  ABS=$(absolutes "$DRAFT")
  if [[ -n "$ABS" ]]; then
    warn "absolute wording; check each against the facts:"$'\n'"$(sed 's/^ */  - /' <<< "$ABS" | head -12)"
  fi
  KNOWN=$( { jq -r '.facts[], .word_count' "$BRIEF"; cat "$OUTLINE"; } | numbers)
  UNKNOWN=$(numbers < "$DRAFT" | grep -vxF -f <(printf '%s\n' "$KNOWN") | paste -sd' ' || true)
  [[ -z "$UNKNOWN" ]] || warn "numbers in draft not found in facts or outline (check for invented specifics): $UNKNOWN"
  ;;

rewrite)
  # An edited part against its input: the edit may reword, never restructure
  # or add claims.
  NEW="${1:?rewritten part required}"; OLD="${2:?original part required}"; BRIEF="${3:?brief required}"
  [[ -s "$NEW" ]] || fail "rewrite is empty"
  diff <(grep '^#' "$OLD") <(grep '^#' "$NEW") > /dev/null || fail "headings changed"
  grep -qE '^(_Intent: |Keywords: )' "$NEW" && fail "outline guidance lines in rewrite"
  grep -qE '^```' "$NEW" && fail "code fence in rewrite"
  OW=$(grep -v '^#' "$OLD" | wc -w); NW=$(grep -v '^#' "$NEW" | wc -w)
  # Cutting filler legitimately shortens a part, so the floor is low; growth
  # is capped because added words are where new claims come from.
  (( NW * 100 >= OW * 50 && NW * 100 <= OW * 120 )) || fail "length changed from $OW to $NW words (50-120% allowed)"
  ADDED=$(comm -13 <( { cat "$OLD"; jq -r '.facts[]' "$BRIEF"; } | numbers) <(numbers < "$NEW") | paste -sd' ')
  [[ -z "$ADDED" ]] || fail "new numbers not in the input or the facts: $ADDED"
  OA=$(absolutes "$OLD" | grep -c . || true); NA=$(absolutes "$NEW" | grep -c . || true)
  (( NA <= OA )) || fail "absolute-wording sentences grew from $OA to $NA:"$'\n'"$(absolutes "$NEW" | head -4)"
  CTA=$(jq -r .cta "$BRIEF")
  if grep -qF "$CTA" "$OLD" && ! grep -qF "$CTA" "$NEW"; then fail "CTA sentence dropped or changed"; fi
  if ! grep -qF "$CTA" "$OLD" && grep -qF "$CTA" "$NEW"; then fail "CTA added to a part that did not have it"; fi
  grep -qE '\*\*' "$NEW" && warn "bold in rewrite"
  ;;

research)
  # The collected research a page is planned from. Structure is a FAIL, thin
  # research is a WARN: a topic with no tool data is a real case, and the
  # keyword stage has to be told, not stopped.
  RESEARCH="${1:?research.json required}"
  jq -e '
    (.slug | type == "string" and length > 0)
    and (.existing_page | type == "object" and has("exists"))
    and (.keywords | type == "array")
    and (.competitors | type == "array")
    and (.inputs | type == "array")
    and all(.keywords[]; .keyword | type == "string" and length > 0)
    and all(.competitors[]; has("url") and has("fetched"))' "$RESEARCH" > /dev/null 2>&1 \
    || fail "research.json does not match the expected shape"
  # The warnings below all read fields the shape check just validated.
  (( FAILS == 0 )) || exit 1

  KW=$(jq '.keywords | length' "$RESEARCH")
  (( KW > 0 )) || warn "no keywords: add an export to inputs/ (Search Console Performance is the first choice, a third-party export works when the page has no Search Console history), or expect the keyword stage to work from competitor pages alone"
  # Search Console data is what this pipeline prefers: measured impressions and
  # clicks for the user's own site. A page with no Search Console history has
  # none to prefer, so an estimated export is the accepted fallback and is
  # reported as estimated rather than as missing. A volume column of zeroes is an
  # export artifact, not a finding, so it does not count.
  #
  # Position is deliberately NOT evidence of measured data, though Search Console
  # reports it. An Ahrefs SERP overview also has a "Position" column, meaning the
  # rank of somebody else's result, and reading that as the user's own position
  # made this check go silent on a file with no first-party data in it at all.
  # Impressions and clicks have no such collision. Found 2026-09-21 on a real export.
  WITH_QUERY_DATA=$(jq '[.keywords[] | select(.impressions != null or .clicks != null)] | length' "$RESEARCH")
  WITH_ESTIMATE=$(jq '[.keywords[] | select(((.volume // 0) > 0) or (.difficulty != null))] | length' "$RESEARCH")
  if (( KW > 0 && WITH_QUERY_DATA == 0 )); then
    if (( WITH_ESTIMATE > 0 )); then
      warn "no keyword carries impressions or clicks, so this is estimated third-party data rather than measured: compare the figures against each other, not as real traffic, and let the competitor pages settle a close call"
    else
      warn "no keyword carries impressions, clicks or a volume: the choice rests on the competitor pages"
    fi
  fi
  OK=$(jq '[.competitors[] | select(.fetched)] | length' "$RESEARCH")
  TOTAL=$(jq '.competitors | length' "$RESEARCH")
  (( TOTAL > 0 )) || warn "no competitor pages: add URLs to competitors.txt for intent and gap analysis"
  (( OK == TOTAL )) || warn "$((TOTAL - OK)) of $TOTAL competitor pages could not be fetched:"$'\n'"$(jq -r '.competitors[] | select(.fetched | not) | "  " + .url + ": " + (.error // "unknown")' "$RESEARCH")"
  (( TOTAL == 0 || OK >= 3 )) || warn "only $OK fetched: SEO-GUIDE.md asks for the top 3 to 5 competitor pages"
  if jq -e '.existing_page.exists' "$RESEARCH" > /dev/null; then
    jq -e '.existing_page.title | length > 0' "$RESEARCH" > /dev/null || warn "the existing page has no title tag"
    jq -e '.existing_page.meta_description | length > 0' "$RESEARCH" > /dev/null || warn "the existing page has no meta description"
  fi
  # Your own pages that already target one of these queries. Two pages chasing
  # one query split their signals, so this is a decision to make before writing,
  # not after (see SEO-GUIDE.md, keyword mapping and cannibalization).
  OWN=$(jq -r '(.site_pages.matching // []) | length' "$RESEARCH")
  if (( OWN > 0 )); then
    warn "$OWN of your own pages already target a researched query, so consider updating one instead of adding another:"$'\n'"$(jq -r '.site_pages.matching[] | "  \(.keyword): \(.url)"' "$RESEARCH" | head -5)"
  fi
  ;;

stage)
  # A structure stage against the research it claims to come from. This is the
  # grounding check: a section whose `source` names evidence that is not really
  # in research.json or keywords.json is invented, however plausible it reads.
  # Before this mode existed, `source` held a bare category ("must_cover") that
  # matched everything and therefore verified nothing.
  STAGE="${1:?structure stage json required}"; RESEARCH="${2:?research.json required}"; KEYWORDS="${3:?keywords.json required}"
  jq -e '(.sections | type == "array" and length > 0)
    and all(.sections[]; (.heading | type == "string" and length > 0)
                     and (.purpose | type == "string" and length > 0)
                     and (.source  | type == "string" and length > 0))' \
    "$STAGE" > /dev/null 2>&1 || fail "$STAGE is not a structure stage with sections"
  (( FAILS == 0 )) || exit 1

  # Same haystack the keywords mode uses, widened with the keyword stage's own
  # must_cover and questions, because those are where a must_cover source comes
  # from.
  HAYSTACK=$( { jq -r '
      [ (.keywords[]? | .keyword, .parent_topic),
        (.competitors[]? | .title, (.headings[]? | .text)),
        .existing_page.title, (.existing_page.headings[]? | .text) ]
      | map(select(. != null)) | join(" | ")' "$RESEARCH"
    jq -r '[ (.must_cover[]?), (.questions[]?), .primary_keyword, (.secondary_keywords[]?) ]
      | map(select(. != null)) | join(" | ")' "$KEYWORDS"; } | tr '\n' ' ' | tr '[:upper:]' '[:lower:]')

  while IFS= read -r src; do
    [[ -n "$src" ]] || continue
    kind=${src%%:*}
    kind=$(tr '[:upper:]' '[:lower:]' <<< "${kind}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    # "page purpose" traces to purpose.txt rather than to the research, so it
    # carries no evidence and is accepted as written.
    [[ "$kind" == "page purpose" ]] && continue
    case "$kind" in
      must_cover|"competitor heading") ;;
      *) fail "source names an unknown kind (expected must_cover, competitor heading or page purpose): $src"; continue ;;
    esac
    if [[ "$src" != *:* ]]; then
      fail "source names a kind but no evidence, so it cannot be traced: $src"
      continue
    fi
    evidence=$(sed -E 's/^[^:]*:[[:space:]]*//' <<< "$src" | sed -E 's/[[:space:]]+$//')
    if [[ -z "$evidence" ]]; then
      fail "source names a kind but no evidence, so it cannot be traced: $src"
    elif ! grep -qiF "$evidence" <<< "$HAYSTACK"; then
      fail "section source is not in the research, so the section is invented or reworded: $src"
    fi
  done < <(jq -r '.sections[].source' "$STAGE")

  # "page purpose" is the one source that carries no evidence, so a stage that
  # leans on it is mostly ungrounded even when every traceable source checks out.
  # A review spine legitimately uses it for the verdict and the testing section,
  # so this is a warning about proportion rather than a failure.
  SECTIONS=$(jq '.sections | length' "$STAGE")
  PURPOSED=$(jq '[.sections[] | select(.source | ascii_downcase | . == "page purpose")] | length' "$STAGE")
  if (( SECTIONS > 0 && PURPOSED * 2 > SECTIONS )); then
    warn "$PURPOSED of $SECTIONS sections trace only to the page purpose, not to the research, so most of this structure is ungrounded"
  fi

  (( $(jq '.faq_questions | length' "$STAGE") > 0 )) || warn "no faq_questions: the FAQ section will have nothing to answer, so check whether the research really holds none"
  ;;

keywords)
  # The keyword choice against the research it came from. Every term must be
  # grounded in the research file, because an invented keyword sends the whole
  # article at a query nobody searched.
  KEYWORDS="${1:?keywords.json required}"; RESEARCH="${2:?research.json required}"
  SUGGESTED="${3:-}"
  [[ -z "$SUGGESTED" || -r "$SUGGESTED" ]] || { echo "not readable: $SUGGESTED" >&2; exit 2; }
  jq -e '
    (.primary_keyword | type == "string" and length > 0)
    and (.secondary_keywords | type == "array" and length >= 2 and length <= 6
         and all(.[]; type == "string" and length > 0))
    and (.intent | type == "object" and has("type") and has("format") and has("angle"))
    and (.business_potential.score | type == "number" and . >= 0 and . <= 3)
    and (.questions | type == "array") and (.must_cover | type == "array")' \
    "$KEYWORDS" > /dev/null 2>&1 || fail "keywords.json does not match the expected shape"
  (( FAILS == 0 )) || exit 1

  # The research as one lowercase haystack: the keyword table, the competitor
  # titles and headings, and the existing page. A keyword the model reworded
  # will not be found here, which is the point.
  HAYSTACK=$(jq -r '
    [ (.keywords[]? | .keyword, .parent_topic),
      (.competitors[]? | .title, (.headings[]? | .text)),
      .existing_page.title, (.existing_page.headings[]? | .text) ]
    | map(select(. != null)) | join(" | ") | ascii_downcase' "$RESEARCH")
  # Keywords typed at the menu are a second source, so a term the person asked
  # for is grounded rather than reported as invented. A term in neither still is.
  GROUND="the research"
  if [[ -n "$SUGGESTED" ]]; then
    HAYSTACK="$HAYSTACK | $(tr '[:upper:]' '[:lower:]' < "$SUGGESTED" | paste -sd'|')"
    GROUND="the research or the suggested keywords"
  fi
  while read -r kw; do
    [[ -n "$kw" ]] || continue
    grep -qiF "$kw" <<< "$HAYSTACK" || fail "keyword not found in $GROUND: $kw"
  done < <(jq -r '.primary_keyword, .secondary_keywords[]' "$KEYWORDS")

  PRIMARY=$(jq -r '.primary_keyword' "$KEYWORDS")
  jq -e --arg p "$PRIMARY" 'all(.secondary_keywords[]; . != $p)' "$KEYWORDS" > /dev/null \
    || fail "the primary keyword is repeated in secondary_keywords"

  # Numbers the model restated instead of describing.
  RNUM=$(jq -r '[.keywords[]? | .volume, .difficulty, .traffic_potential, .clicks, .impressions, .position] | map(select(. != null)) | .[]' "$RESEARCH" | sort -u || true)
  if [[ -n "$RNUM" ]]; then
    ECHOED=$(jq -r '.rationale, .business_potential.reason, (.must_cover[]?), (.questions[]?)' "$KEYWORDS" |
             numbers | grep -xF -f <(printf '%s\n' "$RNUM") | paste -sd' ' || true)
    [[ -z "$ECHOED" ]] || warn "research figures repeated in the reasoning (they belong in research.json only): $ECHOED"
  fi

  (( $(jq '.questions | length' "$KEYWORDS") > 0 )) || warn "no questions: the FAQ section will have nothing to answer"
  (( $(jq '.must_cover | length' "$KEYWORDS") >= 2 )) || warn "fewer than 2 must_cover subtopics: the outline will be thin"
  if jq -e '.existing_page.exists' "$RESEARCH" > /dev/null; then
    TITLE=$(jq -r '.existing_page.title // ""' "$RESEARCH")
    grep -qiF "$PRIMARY" <<< "$TITLE" || warn "the live page's title does not contain the chosen primary keyword, so this is a retarget: $TITLE"
  fi
  ;;

*) echo "unknown mode: $MODE" >&2; exit 2 ;;
esac

(( FAILS == 0 ))
