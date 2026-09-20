---
name: seo-research
description: Start a page's research folder by asking whether the page already exists and, when it does, snapshotting the live page (title, meta description, headings, word count) with scripts/fetch_page.sh. Phase 6 stage, the first step before keywords and the brief. Use when the user runs /seo-research <slug> or asks to research a page before writing it.
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
7. Close with: *"Next: add the Ahrefs and Search Console exports to
   `research/<slug>/inputs/`, then run `/seo-keywords <slug>`."* Say plainly that
   those later stages are not built yet if the user asks to run them.

## Failure handling

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

No competitor pages, no Ahrefs or Search Console exports, no keyword choice, and
no brief. Those are `/seo-keywords` and `/seo-brief`, which are not built yet.
Never fetch a search engine results page: the pipeline takes tool data from the
files the user exports, not by scraping.
