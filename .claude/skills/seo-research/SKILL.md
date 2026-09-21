---
name: seo-research
description: Research a page before it is written. Asks whether the page already exists and snapshots it, then collects the keyword exports the user downloaded and the competitor pages they named into one research.json. Phases 6 and 7, the first stage of the pipeline. Use when the user runs /seo-research <slug> or asks to research a page before writing it.
---

# seo-research

Open `research/<slug>/` for a page and record whether that page is already live.
This is the first stage of the pipeline, ahead of `/seo-keywords` and
`/seo-brief`.

## Inputs

- `$1` the slug for this page, lowercase with hyphens (`briefs/<slug>.json` and
  `outputs/<slug>/` will share it). If missing, ask what to call the page.
- Optionally `$2`, the URL of the existing page, which skips the question below.

## Steps

1. Derive the slug: lowercase, hyphens, no punctuation, no extension. If the
   user passed a URL as `$1`, take the slug from the last path segment and say
   which slug you chose.
2. If `research/<slug>/page.json` already exists, show it and ask before
   replacing it. Stop unless the user confirms.
3. Unless a URL was given, ask: **"Does this page already exist? Give me the URL,
   or say no."** Do not guess, and do not search for the page.
4. No existing page: `bash scripts/fetch_page.sh --absent research/<slug>/page.json`.
5. A URL was given: `bash scripts/fetch_page.sh "<url>" research/<slug>/page.json`.
   The script honors `robots.txt`, keeps a per-host delay, caches the raw HTML
   under `research/_cache/`, and extracts the title, meta description, H1 to H3
   and word count.
6. Read the result back and report it:
   - New page: say the folder is open and nothing was fetched.
   - Existing page: the title with its character count, whether a meta
     description is present and its length, the heading outline, and the word
     count. Name anything off the SEO-GUIDE.md targets, which are a title of 50
     to 60 characters, a meta description of 150 to 160, and exactly one H1.
7. Ask for the research inputs, all optional:
   - **The Search Console Performance export** in `research/<slug>/inputs/`,
     which is this pipeline's first choice: measured impressions, clicks and
     positions for the user's own site. Any other CSV or TSV parses too, since
     columns are read by name. Tell the user to drop the files in and say when
     they are there.
   - **A third-party keyword export** in the same folder, when the page has no
     Search Console history. A brand new site, or a page on a topic the site has
     never appeared for, has no measured data to prefer, and estimated volume
     beats nothing. Ahrefs, Semrush and Keyword Planner exports all parse as
     they come: the volume and difficulty columns are read by name, and a
     tab-separated file saved under a `.csv` name is detected. Say plainly that
     the figures are modelled rather than measured, so they rank terms against
     each other and are not real traffic. If the user has neither export, carry
     on with the competitor pages alone.
   - **Competitors** in `research/<slug>/competitors.txt`, one URL per line,
     `#` comments allowed. SEO-GUIDE.md asks for the top 3 to 5 ranking pages
     for the target query. The user finds them in Google. Never fetch a search
     engine results page to find them yourself.
8. Collect: `bash scripts/research_collect.sh <slug>`. It merges the exports by
   keyword, fetches each competitor through `scripts/fetch_page.sh`, and writes
   `research/<slug>/research.json`. A competitor that cannot be fetched is
   recorded with its reason and does not stop the run. Add `--fresh` to ignore
   the HTML cache.
9. Check: `bash scripts/check.sh research research/<slug>/research.json`.
10. Report, reading the research file rather than the terminal summary:
   - how many keywords came from which export, and the highest-volume few
   - the competitor pages fetched, with their word counts and their H2 outlines,
     since those are the gaps the page has to cover
   - every WARN line, and any competitor that failed with its reason
11. Close with: *"Next: `/seo-keywords <slug>`."*

## Failure handling

`scripts/research_collect.sh` exits 2 when `page.json` is missing (run step 4 or
5 first) and 3 when an export has no keyword column, printing the columns it saw.
Show the user those columns and ask which one holds the keyword, rather than
editing their export.

`scripts/fetch_page.sh` exits with a specific code and prints the reason. Report
it, and do not retry with a different tool or fetch the page another way.

| Exit | Meaning | What to tell the user |
| --- | --- | --- |
| 1 | The URL is not `http://` or `https://` | Ask for a full URL |
| 2 | The output path cannot be written | Name the path |
| 3 | `robots.txt` disallows that path | The site forbids crawling it. Ask the user to paste the page's content instead |
| 4 | The server returned an error status | Show the status. A 404 usually means the page does not exist, so offer `--absent` |
| 5 | The response is not HTML | Name the content type, for example a PDF |
| 7 | The host is unreachable | Show the message and check the URL |

## Out of scope

No keyword choice and no brief: those are `/seo-keywords` and `/seo-brief`.
Never fetch a search engine results page, and never call a search or SEO-tool
API. Data enters this pipeline only as files the user exports, plus the
competitor pages they name.
