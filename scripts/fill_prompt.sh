#!/usr/bin/env bash
# Fill a prompt template's {{PLACEHOLDERS}}.
# Usage: fill_prompt.sh <template> [--brief brief.json] [--outline outline.md] [--source source.txt]
#   --brief    fills TOPIC, BRIEF, AUDIENCE, TONE, WORD_COUNT, KEYWORDS, CTA, FACTS
#   --outline  fills OUTLINE
#   --source   fills SOURCE_TEXT: runs of spaces squeezed, cut at SOURCE_MAX chars
#              with a visible truncation marker
#   --set NAME=value       fills NAME with a literal value
#   --set-file NAME=path   fills NAME with a file's contents
# Prints the filled prompt to stdout. Exits 1 if any {{PLACEHOLDER}} is left
# unfilled, so a template/input mismatch fails here instead of reaching the model.

set -euo pipefail

SOURCE_MAX=24000

TEMPLATE="${1:?template required}"; shift
BRIEF="" OUTLINE="" SOURCE="" EXTRA="{}"
while (( $# )); do
  case "$1" in
    --brief)   BRIEF="${2:?--brief needs a file}"; shift 2 ;;
    --outline) OUTLINE="${2:?--outline needs a file}"; shift 2 ;;
    --source)  SOURCE="${2:?--source needs a file}"; shift 2 ;;
    --set)
      [[ "${2:-}" == *=* ]] || { echo "--set needs NAME=value" >&2; exit 2; }
      EXTRA=$(jq -c --arg k "${2%%=*}" --arg v "${2#*=}" '. + {($k): $v}' <<< "$EXTRA"); shift 2 ;;
    --set-file)
      [[ "${2:-}" == *=* ]] || { echo "--set-file needs NAME=path" >&2; exit 2; }
      [[ -r "${2#*=}" ]] || { echo "not readable: ${2#*=}" >&2; exit 2; }
      EXTRA=$(jq -c --arg k "${2%%=*}" --rawfile v "${2#*=}" '. + {($k): ($v | rtrimstr("\n"))}' <<< "$EXTRA"); shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

for f in "$TEMPLATE" ${BRIEF:+"$BRIEF"} ${OUTLINE:+"$OUTLINE"} ${SOURCE:+"$SOURCE"}; do
  [[ -r "$f" ]] || { echo "not readable: $f" >&2; exit 2; }
done

BRIEF_JSON='null'
[[ -n "$BRIEF" ]] && BRIEF_JSON=$(jq -c . "$BRIEF")
OUTLINE_TEXT=""
[[ -n "$OUTLINE" ]] && OUTLINE_TEXT=$(cat "$OUTLINE")
SOURCE_TEXT=""
if [[ -n "$SOURCE" ]]; then
  SOURCE_TEXT=$(sed -E 's/[[:space:]]+$//; s/ {2,}/ /g' "$SOURCE" | cat -s)
  if (( ${#SOURCE_TEXT} > SOURCE_MAX )); then
    SOURCE_TEXT="${SOURCE_TEXT:0:SOURCE_MAX}"$'\n\n[... source truncated for ingest ...]\n'
    echo "source truncated to $SOURCE_MAX characters" >&2
  fi
fi

# split/join instead of gsub: values are literal text, never regex.
FILLED=$(jq -nrj --rawfile t "$TEMPLATE" --argjson b "$BRIEF_JSON" \
  --arg outline "$OUTLINE_TEXT" --arg source "$SOURCE_TEXT" \
  --arg has_outline "${OUTLINE:+1}" --arg has_source "${SOURCE:+1}" --argjson extra "$EXTRA" '
  (if $b == null then {} else {
      TOPIC: $b.topic,
      BRIEF: $b.topic,
      AUDIENCE: $b.target_audience,
      TONE: $b.tone,
      WORD_COUNT: ($b.word_count | tostring),
      KEYWORDS: ($b.keywords | join(", ")),
      CTA: $b.cta,
      FACTS: (($b.facts // []) | if length == 0 then "(none provided)" else map("- " + .) | join("\n") end)
    } end)
  + (if $has_outline == "1" then {OUTLINE: $outline} else {} end)
  + (if $has_source == "1" then {SOURCE_TEXT: $source} else {} end)
  + $extra
  | reduce to_entries[] as $e ($t; split("{{" + $e.key + "}}") | join($e.value))
')

# Check the template, not the filled text: source documents may contain {{…}}.
LEFT=$(grep -oE '\{\{[A-Z_]+\}\}' "$TEMPLATE" | sort -u | while read -r p; do
  case "$p" in
    "{{OUTLINE}}") [[ -n "$OUTLINE" ]] || echo "$p" ;;
    "{{SOURCE_TEXT}}") [[ -n "$SOURCE" ]] || echo "$p" ;;
    "{{TOPIC}}"|"{{BRIEF}}"|"{{AUDIENCE}}"|"{{TONE}}"|"{{WORD_COUNT}}"|"{{KEYWORDS}}"|"{{CTA}}"|"{{FACTS}}")
      [[ -n "$BRIEF" ]] || echo "$p" ;;
    *) jq -e --arg k "${p:2:${#p}-4}" 'has($k)' <<< "$EXTRA" > /dev/null || echo "$p" ;;
  esac
done | paste -sd' ')
if [[ -n "$LEFT" ]]; then
  echo "unfilled placeholders in $TEMPLATE: $LEFT" >&2
  exit 1
fi

printf '%s\n' "$FILLED"
