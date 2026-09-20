#!/usr/bin/env bash
# Collect one page's research into research/<slug>/research.json.
#
# Usage: research_collect.sh <slug> [--fresh]
#
# Reads, all optional except page.json:
#   research/<slug>/page.json        written by /seo-research
#   research/<slug>/inputs/*.csv     keyword and query exports you download
#   research/<slug>/competitors.txt  one competitor URL per line, # comments ok
# Writes research/<slug>/research.json, fetching each competitor page through
# scripts/fetch_page.sh so robots.txt, the per-host delay and the cache all apply.
#
# Env: RESEARCH_DIR (default research) relocates the whole tree, which is how
# verification runs stay out of the real one.
#
# Exit codes: 1 usage, 2 missing page.json, 3 an export has no keyword column.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="${RESEARCH_DIR:-research}"

SLUG="${1:?usage: research_collect.sh <slug> [--fresh]}"
# --fresh ignores the HTML cache, so competitor pages are fetched again.
if [[ "${2:-}" == "--fresh" ]]; then export FETCH_CACHE_TTL=0; fi

DIR="$ROOT/$SLUG"
PAGE="$DIR/page.json"
OUT="$DIR/research.json"

[[ -r "$PAGE" ]] || { echo "no $PAGE: run /seo-research $SLUG first" >&2; exit 2; }

# A CSV row can quote fields that contain the delimiter, so this splits on the
# delimiter only outside quotes and doubles up escaped quotes. Fields keep no
# tabs, because tab is the output delimiter.
csv_to_tsv() { # csv_to_tsv <file> <delimiter>
  awk -v FS='' -v DELIM="$2" '
    {
      line = $0; sub(/\r$/, "", line)
      n = 0; field = ""; inq = 0
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (inq) {
          if (c == "\"") {
            if (substr(line, i + 1, 1) == "\"") { field = field "\""; i++ } else inq = 0
          } else field = field c
        } else if (c == "\"") inq = 1
        else if (c == DELIM) { out[++n] = field; field = "" }
        else field = field c
      }
      out[++n] = field
      for (i = 1; i <= n; i++) {
        gsub(/\t/, " ", out[i])
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", out[i])
        printf "%s%s", out[i], (i < n ? "\t" : "\n")
      }
      delete out
    }
  ' "$1"
}

# Map an export's own column names onto the names research.json uses. Unmapped
# columns become "" and are dropped, so an export may carry any extra columns.
canonical_header() { # canonical_header <tsv-header-line>
  awk -F'\t' '
    BEGIN { OFS = "\t" }
    {
      for (i = 1; i <= NF; i++) {
        h = tolower($i); gsub(/^[[:space:]]+|[[:space:]]+$/, "", h)
        if (h == "keyword" || h == "keywords" || h == "query" || h == "top queries") $i = "keyword"
        else if (h == "volume" || h == "search volume" || h == "global volume" || h == "avg. monthly searches") $i = "volume"
        else if (h == "difficulty" || h == "kd" || h == "keyword difficulty") $i = "difficulty"
        else if (h == "traffic potential" || h == "tp") $i = "traffic_potential"
        else if (h == "cpc") $i = "cpc"
        else if (h == "clicks") $i = "clicks"
        else if (h == "impressions") $i = "impressions"
        else if (h == "position" || h == "average position" || h == "avg. position") $i = "position"
        else if (h == "ctr") $i = "ctr"
        else if (h == "parent topic") $i = "parent_topic"
        else if (h == "intent" || h == "search intent") $i = "intent"
        else $i = ""
      }
      print
    }
  ' <<< "$1"
}

# One export file to a JSON array of keyword rows.
export_to_json() { # export_to_json <file>
  local file="$1" first delim tsv header
  first=$(head -1 "$file" | sed 's/^\xef\xbb\xbf//')   # drop a UTF-8 byte order mark
  # Sniff the delimiter: Ahrefs exports tab-separated files under a .csv name.
  if [[ $(tr -cd '\t' <<< "$first" | wc -c) -gt $(tr -cd ',' <<< "$first" | wc -c) ]]; then
    delim=$'\t'
  else
    delim=','
  fi
  tsv=$(sed '1s/^\xef\xbb\xbf//' "$file" | csv_to_tsv /dev/stdin "$delim")
  header=$(canonical_header "$(head -1 <<< "$tsv")")
  if ! grep -q $'\(^\|\t\)keyword\(\t\|$\)' <<< "$header"; then
    echo "no keyword column in $file" >&2
    echo "  columns seen: $(head -1 <<< "$tsv" | tr '\t' '|')" >&2
    echo "  expected one of: keyword, keywords, query, top queries" >&2
    exit 3
  fi
  { printf '%s\n' "$header"; tail -n +2 <<< "$tsv"; } | jq -R -s --arg src "$(basename "$file")" '
    split("\n") | map(select(length > 0))
    | (.[0] | split("\t")) as $h
    | .[1:]
    | map(split("\t")
          | to_entries
          | map(select($h[.key] != "" and .value != ""))
          | map({key: $h[.key], value: .value})
          | from_entries)
    | map(select(.keyword != null and .keyword != ""))
    | map(with_entries(
        if .key == "keyword" or .key == "parent_topic" or .key == "intent" then .
        else .value |= (gsub("[,$%\\s]"; "") | if . == "" then null else (tonumber? // null) end)
        end))
    | map(. + {sources: [$src]})'
}

# --- keyword exports -------------------------------------------------------
KEYWORDS='[]'
INPUT_FILES=()
if compgen -G "$DIR/inputs/*" > /dev/null; then
  for f in "$DIR"/inputs/*; do
    [[ -f "$f" ]] || continue
    case "${f,,}" in *.csv|*.tsv|*.txt) ;; *) continue ;; esac
    INPUT_FILES+=("$(basename "$f")")
    rows=$(export_to_json "$f")
    # Merge by keyword: a later file fills gaps but never overwrites a value,
    # and every file that mentioned the keyword is listed in sources.
    KEYWORDS=$(jq -n --argjson a "$KEYWORDS" --argjson b "$rows" '
      ($a + $b)
      | group_by(.keyword | ascii_downcase)
      | map((map(.sources) | add | unique) as $srcs
            | reduce .[] as $r ({}; $r + with_entries(select(.value != null)))
            | .sources = $srcs)')
  done
fi
KEYWORDS=$(jq 'sort_by([(.volume // 0), (.clicks // 0)]) | reverse' <<< "$KEYWORDS")

# --- competitor pages ------------------------------------------------------
COMPETITORS='[]'
URLS_FILE="$DIR/competitors.txt"
if [[ -r "$URLS_FILE" ]]; then
  while IFS= read -r url; do
    url="${url%%#*}"; url="$(tr -d '[:space:]' <<< "$url")"
    [[ -n "$url" ]] || continue
    err=$(mktemp)
    page=$(bash "$HERE/fetch_page.sh" "$url" 2> "$err") && rc=0 || rc=$?
    if (( rc != 0 )); then
      # One unreachable or disallowed competitor must not end the collection,
      # and the fetcher's own reason is what gets reported.
      reason=$(tail -1 "$err")
      echo "WARN: could not fetch $url (exit $rc): $reason" >&2
      COMPETITORS=$(jq --arg u "$url" --arg r "$reason" --argjson c "$rc" \
        '. + [{url: $u, fetched: false, error: $r, exit: $c}]' <<< "$COMPETITORS")
    else
      COMPETITORS=$(jq --argjson p "$page" '. + [$p + {fetched: true}]' <<< "$COMPETITORS")
    fi
    rm -f "$err"
  done < "$URLS_FILE"
fi

# --- assemble --------------------------------------------------------------
jq -n \
  --arg slug "$SLUG" \
  --argjson page "$(cat "$PAGE")" \
  --argjson keywords "$KEYWORDS" \
  --argjson competitors "$COMPETITORS" \
  --arg inputs "${INPUT_FILES[*]:-}" '
  {
    slug: $slug,
    collected_at: (now | todate),
    existing_page: $page,
    inputs: ($inputs | split(" ") | map(select(length > 0))),
    keywords: $keywords,
    competitors: $competitors,
    competitor_word_counts: ($competitors | map(select(.fetched and .word_count != null) | .word_count))
  }' > "$OUT"

echo "wrote $OUT" >&2
jq -r '"keywords: \(.keywords | length), competitors fetched: \(.competitors | map(select(.fetched)) | length)/\(.competitors | length), exports: \(.inputs | length)"' "$OUT" >&2
