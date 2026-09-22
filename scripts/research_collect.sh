#!/usr/bin/env bash
# Collect one page's research into research/<slug>/research.json.
#
# Usage: research_collect.sh <slug> [--fresh]
#
# Reads, all optional except page.json:
#   research/<slug>/page.json        written by /seo-research
#   research/<slug>/inputs/*.csv     keyword and query exports you download
#   research/<slug>/competitors.txt  one competitor URL per line, # comments ok
#   research/<slug>/site.txt         your own site URL, when the page is not live yet
# Writes research/<slug>/research.json, fetching each competitor page through
# scripts/fetch_page.sh so robots.txt, the per-host delay and the cache all apply.
#
# Env: RESEARCH_DIR (default research) relocates the whole tree, which is how
# verification runs stay out of the real one. MAX_KEYWORDS (default 150) caps how
# many keywords reach research.json, taken from the head of the volume sort,
# because a full keyword export is far larger than the model's context. 0 keeps
# every row.
#
# Exit codes: 1 usage, 2 missing page.json, 3 an export has no keyword column,
#             4 an export could not be parsed or merged (nothing is written).

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="${RESEARCH_DIR:-research}"

SLUG="${1:?usage: research_collect.sh <slug> [--fresh]}"
# --fresh ignores the HTML cache, so competitor pages are fetched again.
if [[ "${2:-}" == "--fresh" ]]; then export FETCH_CACHE_TTL=0; fi

# How many keywords may reach research.json, head of the volume sort. 0 keeps all.
MAX_KEYWORDS="${MAX_KEYWORDS:-150}"

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
#
# Two of an export's columns can canonicalise to the same name, and the later one
# used to win. An Ahrefs SERP overview carries both "Keyword" and "Keywords",
# where the second is a count of the keywords a URL ranks for, so every keyword
# came through as a number ("91", "54", "488"). First occurrence wins now, and a
# later duplicate is dropped like any unmapped column. Found 2026-09-21 on a real
# export.
canonical_header() { # canonical_header <tsv-header-line>
  awk -F'\t' '
    BEGIN { OFS = "\t" }
    {
      delete seen
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
        if ($i != "") { if ($i in seen) $i = ""; else seen[$i] = 1 }
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
# The keyword list lives in a file, never in a jq argument. Linux caps a single
# argv string at 128 KB (MAX_ARG_STRLEN) whatever ARG_MAX reports, and a real
# Ahrefs export parses to several hundred KB, so --argjson died with "Argument
# list too long" on the exports this pipeline exists to read. Found 2026-09-21 on
# a 2782-row file.
KW_FILE=$(mktemp); ROWS_FILE=$(mktemp)
trap 'rm -f "$KW_FILE" "$ROWS_FILE" "$KW_FILE.new"' EXIT
echo '[]' > "$KW_FILE"
INPUT_FILES=()
if compgen -G "$DIR/inputs/*" > /dev/null; then
  for f in "$DIR"/inputs/*; do
    [[ -f "$f" ]] || continue
    case "${f,,}" in *.csv|*.tsv|*.txt) ;; *) continue ;; esac
    INPUT_FILES+=("$(basename "$f")")
    export_to_json "$f" > "$ROWS_FILE" \
      || { echo "ERROR: could not read the export $f, so nothing was written" >&2; exit 4; }
    # Merge by keyword: a later file fills gaps but never overwrites a value,
    # and every file that mentioned the keyword is listed in sources.
    jq -n --slurpfile a "$KW_FILE" --slurpfile b "$ROWS_FILE" '
      ($a[0] + $b[0])
      | group_by(.keyword | ascii_downcase)
      | map((map(.sources) | add | unique) as $srcs
            | reduce .[] as $r ({}; $r + with_entries(select(.value != null)))
            | .sources = $srcs)' > "$KW_FILE.new" \
      || { echo "ERROR: could not merge the export $f into the keyword list, so nothing was written" >&2; exit 4; }
    mv "$KW_FILE.new" "$KW_FILE"
  done
fi
jq 'sort_by([(.volume // 0), (.clicks // 0)]) | reverse' "$KW_FILE" > "$KW_FILE.new"
mv "$KW_FILE.new" "$KW_FILE"

# A full Ahrefs "matching terms" export is thousands of rows, and the whole list
# would not fit the keyword prompt's context. Keep the head of the volume sort,
# and record what was cut so the reader of research.json knows the list is not
# the whole file. MAX_KEYWORDS=0 keeps everything, for a run that only wants the
# data on disk.
KEYWORDS_TOTAL=$(jq 'length' "$KW_FILE")
KEYWORDS_CUTOFF=null
if (( MAX_KEYWORDS > 0 && KEYWORDS_TOTAL > MAX_KEYWORDS )); then
  KEYWORDS_CUTOFF=$(jq -c --argjson n "$MAX_KEYWORDS" '
    {by: "volume", kept: $n, dropped: (length - $n), min_volume: (.[$n - 1].volume // 0)}' "$KW_FILE")
  jq --argjson n "$MAX_KEYWORDS" '.[0:$n]' "$KW_FILE" > "$KW_FILE.new"
  mv "$KW_FILE.new" "$KW_FILE"
  echo "keywords: kept the top $MAX_KEYWORDS of $KEYWORDS_TOTAL by volume (MAX_KEYWORDS=0 keeps all)" >&2
fi

# --- competitor pages ------------------------------------------------------
# Navigation and site furniture is not a subtopic. These headings reach the brief
# stage's grounding haystack, so an invented section can trace to "Help" and pass
# the check that exists to stop exactly that. Measured on a live run: 6 of 16
# collected headings were furniture, 4 of them from one retail page. The match is
# whole-string and case insensitive, so a real heading that merely contains one of
# these words ("How to help your cat drink") is kept.
FURNITURE='^(about|about us|help|support|services|stores|store locator|menu|search|
skip to|skip to content|keyboard shortcuts|share this|share|follow us|follow via email|
newsletter|sign up|subscribe|categories|archives|tags|related posts|you may also like|
recent posts|comments?|[0-9]+ comments?|one comment|leave a reply|leave a comment|
privacy policy|terms of service|contact|contact us|cart|account|my account|
footer|navigation|breadcrumb|quick links|customer service|shipping|returns)$'
FURNITURE=$(tr -d '\n' <<< "$FURNITURE")
DROPPED_HEADINGS=0

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
      before=$(jq '[.headings[]?] | length' <<< "$page")
      page=$(jq --arg f "$FURNITURE" '
        .headings = [.headings[]? | select((.text | ascii_downcase
                     | gsub("^\\s+|\\s+$"; "") | test($f)) | not)]' <<< "$page")
      after=$(jq '[.headings[]?] | length' <<< "$page")
      DROPPED_HEADINGS=$(( DROPPED_HEADINGS + before - after ))
      COMPETITORS=$(jq --argjson p "$page" '. + [$p + {fetched: true}]' <<< "$COMPETITORS")
    fi
    rm -f "$err"
  done < "$URLS_FILE"
fi

# --- your own pages, from the sitemap --------------------------------------
# The inventory is per site, not per page, so it is fetched once and reused.
# Its job here is the cannibalization check: which of your pages already target
# this query, and which ones could link to the new page.
SITE_PAGES='null'
SITE_URL=""
if jq -e '.exists' "$PAGE" > /dev/null 2>&1; then
  SITE_URL=$(jq -r '.url' "$PAGE")
elif [[ -r "$DIR/site.txt" ]]; then
  SITE_URL=$(head -1 "$DIR/site.txt" | tr -d '[:space:]')
fi

if [[ -n "$SITE_URL" ]]; then
  HOST=$(sed -E 's#^[a-zA-Z]+://##; s#/.*##; s#.*@##' <<< "$SITE_URL")
  INVENTORY="$ROOT/_sitemaps/$HOST.txt"
  if [[ ! -r "$INVENTORY" ]]; then
    echo "fetching the sitemap for $HOST (once per site)..." >&2
    bash "$HERE/fetch_sitemap.sh" "$SITE_URL" "$INVENTORY" || \
      echo "WARN: no sitemap inventory for $HOST, so the cannibalization check is skipped" >&2
  fi
  if [[ -r "$INVENTORY" ]]; then
    # A page "already targets" a keyword when every word of four letters or more
    # in that keyword appears in the URL's own path.
    SITE_PAGES=$(jq -R -s --slurpfile kwf "$KW_FILE" --arg host "$HOST" '
      split("\n") | map(select(length > 0)) as $urls
      | {
          host: $host,
          total: ($urls | length),
          matching: [
            $kwf[0][] as $k
            | ($k.keyword | ascii_downcase | [scan("[a-z0-9]{4,}")]) as $words
            | select($words | length > 0)
            | $urls[]
            | . as $u
            | ($u | ascii_downcase | sub("^https?://[^/]*"; "")) as $path
            | select($words | all(. as $w | $path | test($w)))
            | {keyword: $k.keyword, url: $u}
          ]
        }' "$INVENTORY")
  fi
fi

# --- assemble --------------------------------------------------------------
jq -n \
  --arg slug "$SLUG" \
  --argjson page "$(cat "$PAGE")" \
  --slurpfile keywords "$KW_FILE" \
  --argjson keywords_total "$KEYWORDS_TOTAL" \
  --argjson keywords_cutoff "$KEYWORDS_CUTOFF" \
  --argjson competitors "$COMPETITORS" \
  --argjson site_pages "$SITE_PAGES" \
  --argjson headings_dropped "$DROPPED_HEADINGS" \
  --arg inputs "${INPUT_FILES[*]:-}" '
  {
    slug: $slug,
    collected_at: (now | todate),
    existing_page: $page,
    inputs: ($inputs | split(" ") | map(select(length > 0))),
    keywords: $keywords[0],
    keywords_total: $keywords_total,
    keywords_cutoff: $keywords_cutoff,
    competitors: $competitors,
    competitor_word_counts: ($competitors | map(select(.fetched and .word_count != null) | .word_count)),
    headings_dropped: $headings_dropped,
    site_pages: $site_pages
  }' > "$OUT"

echo "wrote $OUT" >&2
jq -r '"keywords: \(.keywords | length), competitors fetched: \(.competitors | map(select(.fetched)) | length)/\(.competitors | length), exports: \(.inputs | length)"' "$OUT" >&2
