#!/usr/bin/env bash
# Build an inventory of a site's own pages from its sitemap.
#
# Usage: fetch_sitemap.sh <site-url-or-host> [out.txt]
#
# Finds the sitemap the way a crawler does: the Sitemap: lines in robots.txt
# first, because those are authoritative, then /sitemap.xml as a fallback.
# Follows a sitemap index one level down, and writes one URL per line, sorted
# and deduplicated. The default output is research/_sitemaps/<host>.txt, which
# is fetched once per site rather than once per page.
#
# Every request goes through scripts/fetch_page.sh --raw, so robots.txt, the
# per-host delay and the cache all apply here too.
#
# Env: RESEARCH_DIR (default research), plus everything fetch_page.sh reads.
#
# Exit codes: 1 usage, 2 cannot write, 4 no sitemap found, 5 the sitemap is
#             compressed or is not XML.

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
RESEARCH="${RESEARCH_DIR:-$ROOT/research}"
MAX_CHILDREN="${SITEMAP_MAX_CHILDREN:-10}"

SITE="${1:?usage: fetch_sitemap.sh <site-url-or-host> [out.txt]}"
[[ "$SITE" =~ ^https?:// ]] || SITE="https://$SITE"
HOST=$(sed -E 's#^[a-zA-Z]+://##; s#/.*##; s#.*@##' <<< "$SITE")
BASE=$(sed -E 's#^([a-zA-Z]+://[^/]*).*#\1#' <<< "$SITE")
OUT="${2:-$RESEARCH/_sitemaps/$HOST.txt}"

raw() { bash "$HERE/fetch_page.sh" --raw "$1" 2>/dev/null; }

# <loc> elements, one per line. Sitemaps are machine-written XML, so this stays
# a text extraction rather than a parser, but it does cope with several <loc>
# elements on one line.
locs() { tr '>' '>\n' <<< "$1" | grep -oiE '<loc[^>]*>[^<]+' | sed -E 's/^<loc[^>]*>//' | sed -E 's/[[:space:]]+//g'; }

is_gzip() { [[ "$(head -c2 <<< "$1")" == $'\x1f\x8b' ]]; }

# --- find the sitemap -------------------------------------------------------
declare -a CANDIDATES=()
ROBOTS=$(raw "$BASE/robots.txt")
if [[ -n "$ROBOTS" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && CANDIDATES+=("$line")
  done < <(grep -iE '^[[:space:]]*sitemap[[:space:]]*:' <<< "$ROBOTS" |
           sed -E 's/^[^:]*:[[:space:]]*//' | tr -d '\r' | sed -E 's/[[:space:]]+$//')
fi
if (( ${#CANDIDATES[@]} == 0 )); then
  echo "no Sitemap: line in robots.txt, trying $BASE/sitemap.xml" >&2
  CANDIDATES+=("$BASE/sitemap.xml")
fi

# --- read them, following an index one level down ---------------------------
URLS=""
INDEXES=0
for sm in "${CANDIDATES[@]}"; do
  body=$(raw "$sm")
  if [[ -z "$body" ]]; then
    echo "could not read $sm" >&2
    continue
  fi
  if is_gzip "$body"; then
    echo "compressed sitemap, which this script does not unpack: $sm" >&2
    echo "Save it yourself with: curl -s '$sm' | gunzip > $OUT" >&2
    exit 5
  fi
  found=$(locs "$body")
  if [[ -z "$found" ]]; then
    echo "no <loc> entries in $sm, so it is not a sitemap" >&2
    continue
  fi
  # A sitemap index lists sitemaps rather than pages. Follow its children, but
  # only one level and only so many, because a large site can list hundreds.
  if grep -qiE '<sitemapindex' <<< "$body"; then
    INDEXES=$((INDEXES + 1))
    echo "sitemap index with $(wc -l <<< "$found") children: $sm" >&2
    n=0
    while IFS= read -r child; do
      (( n >= MAX_CHILDREN )) && { echo "stopping after $MAX_CHILDREN children, raise SITEMAP_MAX_CHILDREN for the rest" >&2; break; }
      n=$((n + 1))
      cbody=$(raw "$child")
      if [[ -z "$cbody" ]]; then echo "  could not read $child" >&2; continue; fi
      if is_gzip "$cbody"; then echo "  compressed child skipped: $child" >&2; continue; fi
      URLS+=$'\n'$(locs "$cbody")
    done <<< "$found"
  else
    URLS+=$'\n'"$found"
  fi
done

URLS=$(grep -E '^https?://' <<< "$URLS" | sort -u)
if [[ -z "$URLS" ]]; then
  echo "no sitemap found for $HOST" >&2
  exit 4
fi

mkdir -p "$(dirname "$OUT")" || { echo "cannot create $(dirname "$OUT")" >&2; exit 2; }
printf '%s\n' "$URLS" > "$OUT" || { echo "cannot write $OUT" >&2; exit 2; }
echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') URLs$( (( INDEXES > 0 )) && echo ", from a sitemap index" ))" >&2
