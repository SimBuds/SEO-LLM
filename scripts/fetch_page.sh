#!/usr/bin/env bash
# Fetch one web page politely and extract its SEO surface as JSON.
#
# Usage: fetch_page.sh <url> [out.json]      fetch, extract, print or write JSON
#        fetch_page.sh --absent [out.json]   record a page that does not exist yet
#
# Honors robots.txt for the requesting User-Agent, keeps a per-host delay, and
# caches raw HTML so a rerun does not hit the host again. Env overrides:
#   FETCH_UA         User-Agent (default SEO-LLM/1.0, no contact address)
#   FETCH_CACHE_DIR  cache location (default research/_cache)
#   FETCH_CACHE_TTL  seconds a cached page stays fresh (default 86400)
#   FETCH_DELAY      minimum seconds between requests to one host (default 2)
#   FETCH_TIMEOUT    per-request timeout in seconds (default 20)
#
# Exit codes: 1 usage, 2 cannot write, 3 robots.txt disallows the path,
#             4 HTTP error status, 5 response is not HTML, 7 host unreachable.

set -euo pipefail

UA="${FETCH_UA:-SEO-LLM/1.0}"
CACHE_DIR="${FETCH_CACHE_DIR:-research/_cache}"
CACHE_TTL="${FETCH_CACHE_TTL:-86400}"
MIN_DELAY="${FETCH_DELAY:-2}"
TIMEOUT="${FETCH_TIMEOUT:-20}"

usage() { echo "usage: fetch_page.sh <url> [out.json] | fetch_page.sh --absent [out.json]" >&2; exit 1; }

emit() { # emit <json> [out.json]
  if [[ -n "${2:-}" ]]; then
    mkdir -p "$(dirname "$2")" || { echo "cannot create $(dirname "$2")" >&2; exit 2; }
    printf '%s\n' "$1" > "$2" || { echo "cannot write $2" >&2; exit 2; }
    echo "wrote $2" >&2
  else
    printf '%s\n' "$1"
  fi
}

host_of() { sed -E 's#^[a-zA-Z]+://##; s#/.*##; s#.*@##' <<< "$1"; }
scheme_of() { sed -E 's#://.*##' <<< "$1"; }
path_of() { local p; p=$(sed -E 's#^[a-zA-Z]+://[^/]*##' <<< "$1"); printf '%s' "${p:-/}"; }

# Sleep out the remainder of this host's delay, then stamp it.
wait_turn() { # wait_turn <host> <delay>
  local stamp="$CACHE_DIR/.last-$1" now last wait
  now=$(date +%s)
  if [[ -f "$stamp" ]]; then
    last=$(cat "$stamp")
    wait=$(( $2 - (now - last) ))
    if (( wait > 0 )); then sleep "$wait"; fi
  fi
  date +%s > "$stamp"
}

# Fetch a URL into the cache, or reuse a fresh cached copy. Sets BODY_PATH,
# HTTP_CODE, CONTENT_TYPE and CACHED as globals: a command substitution would
# run this in a subshell and lose every one of them.
polite_get() { # polite_get <url> <delay>
  local url="$1" delay="$2" key meta age out
  key=$(printf '%s' "$url" | sha1sum | cut -c1-40)
  BODY_PATH="$CACHE_DIR/$key.body"
  meta="$CACHE_DIR/$key.meta"
  mkdir -p "$CACHE_DIR"
  if [[ -f "$BODY_PATH" && -f "$meta" ]]; then
    age=$(( $(date +%s) - $(stat -c %Y "$BODY_PATH") ))
    if (( age < CACHE_TTL )); then
      HTTP_CODE=$(cut -d' ' -f1 "$meta")
      CONTENT_TYPE=$(cut -d' ' -f2- "$meta")
      CACHED=1
      return 0
    fi
  fi
  wait_turn "$(host_of "$url")" "$delay"
  out=$(curl -sS -L --compressed -m "$TIMEOUT" -A "$UA" \
        -w '%{http_code} %{content_type}' -o "$BODY_PATH" "$url") || {
    echo "unreachable: $url" >&2; exit 7; }
  printf '%s\n' "$out" > "$meta"
  HTTP_CODE=$(cut -d' ' -f1 <<< "$out")
  CONTENT_TYPE=$(cut -d' ' -f2- <<< "$out")
  CACHED=0
}

# Read robots.txt for this host and decide. Sets CRAWL_DELAY.
robots_allows() { # robots_allows <url> -> 0 allowed, 1 disallowed
  local url="$1" robots path
  robots="$(scheme_of "$url")://$(host_of "$url")/robots.txt"
  path=$(path_of "$url")
  CRAWL_DELAY="$MIN_DELAY"
  polite_get "$robots" "$MIN_DELAY"
  # A missing or server-error robots.txt is treated as allow-all, which is what
  # the standard says. Only a 200 carries rules.
  [[ "$HTTP_CODE" == "200" ]] || return 0
  local verdict
  verdict=$(awk -v path="$path" '
    function norm(s) { sub(/\r$/, "", s); return s }
    BEGIN { IGNORECASE = 1; star = 0; best_len = -1; best = "allow"; delay = "" }
    {
      line = norm($0); sub(/#.*/, "", line)
      if (line ~ /^[[:space:]]*$/) next
      split(line, kv, ":")
      key = tolower(kv[1]); gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      value = substr(line, index(line, ":") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (key == "user-agent") { star = (value == "*"); next }
      if (!star) next
      if (key == "crawl-delay") { delay = value; next }
      if (key != "disallow" && key != "allow") next
      if (key == "disallow" && value == "") next          # empty disallow allows all
      if (substr(path, 1, length(value)) == value) {       # prefix match
        # Longest matching rule wins, and allow wins a tie.
        if (length(value) > best_len || (length(value) == best_len && key == "allow")) {
          best_len = length(value); best = key
        }
      }
    }
    END { print best "\t" delay }
  ' "$BODY_PATH")
  local rule delay
  rule=${verdict%%$'\t'*}
  delay=${verdict#*$'\t'}
  if [[ -n "$delay" ]] && awk -v d="$delay" -v m="$MIN_DELAY" 'BEGIN { exit !(d+0 > m+0) }'; then
    CRAWL_DELAY=${delay%.*}
  fi
  [[ "$rule" == "allow" ]]
}

# Flatten HTML to one line so the tag patterns below are not defeated by
# newlines inside a tag.
flatten() { tr '\n\r\t' '   ' < "$1"; }

# Every extractor below returns an empty string when the element is absent: a
# page with no meta description or no H1 is ordinary, not an error, and under
# `set -o pipefail` an unmatched grep would otherwise end the run.
tag_text() { # tag_text <flat-html> <regex for the whole element>
  { grep -oiE "$2" <<< "$1" | sed -n '1p' |
    sed -E 's/<[^>]*>//g' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; } || true
}

[[ $# -ge 1 ]] || usage

if [[ "$1" == "--absent" ]]; then
  emit "$(jq -n '{exists: false, checked_at: (now | todate)}')" "${2:-}"
  exit 0
fi

URL="$1"; OUT="${2:-}"
[[ "$URL" =~ ^https?:// ]] || { echo "url must start with http:// or https://: $URL" >&2; usage; }

HTTP_CODE=""; CONTENT_TYPE=""; CACHED=0; CRAWL_DELAY="$MIN_DELAY"; BODY_PATH=""
robots_allows "$URL" || { echo "robots.txt disallows $URL for $UA" >&2; exit 3; }

polite_get "$URL" "$CRAWL_DELAY"
if (( CACHED == 1 )); then echo "cache hit: $URL" >&2; fi

case "$HTTP_CODE" in
  2*) ;;
  *) echo "HTTP $HTTP_CODE for $URL" >&2; exit 4 ;;
esac
case "$CONTENT_TYPE" in
  *html*) ;;
  *) echo "not HTML ($CONTENT_TYPE): $URL" >&2; exit 5 ;;
esac

FLAT=$(flatten "$BODY_PATH")
TITLE=$(tag_text "$FLAT" '<title[^>]*>[^<]*</title>')
DESC=$({ grep -oiE '<meta[^>]+name[[:space:]]*=[[:space:]]*"?description"?[^>]*>' <<< "$FLAT" | sed -n '1p' |
       grep -oiE 'content[[:space:]]*=[[:space:]]*("[^"]*"|'"'"'[^'"'"']*'"'"')' | sed -n '1p' |
       sed -E 's/^[^=]*=[[:space:]]*.//; s/.$//'; } || true)
HEADINGS=$({ grep -oiE '<h[1-3][^>]*>[^<]*(<[^/][^>]*>[^<]*)*</h[1-3]>' <<< "$FLAT" |
  sed -E 's#^<(h[1-3])[^>]*>#\1\t#I; s#</h[1-3]>$##I; s#<[^>]*>##g; s# +# #g; s#\t #\t#; s# $##' |
  grep -vE $'^h[1-3]\t*$'; } || true)
# Body text for the word count: drop script and style blocks, then all tags.
WORDS=$({ sed -E 's#<script[^>]*>[^<]*(<[^/][^>]*>[^<]*)*</script>##gI; s#<style[^>]*>[^<]*</style>##gI; s#<[^>]*># #g' <<< "$FLAT" |
  tr -s ' ' '\n' | grep -c '[A-Za-z0-9]'; } || true)

JSON=$(jq -n \
  --arg url "$URL" --arg title "$TITLE" --arg desc "$DESC" \
  --arg headings "$HEADINGS" --argjson words "${WORDS:-0}" \
  --arg status "$HTTP_CODE" '
  {
    exists: true,
    url: $url,
    fetched_at: (now | todate),
    status: ($status | tonumber),
    title: $title,
    meta_description: $desc,
    word_count: $words,
    headings: ($headings | split("\n") | map(select(length > 0) | split("\t"))
               | map(select(length == 2) | {level: .[0] | ascii_downcase, text: .[1]}))
  }')
emit "$JSON" "$OUT"
