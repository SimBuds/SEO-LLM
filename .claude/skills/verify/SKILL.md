---
name: verify
description: How to verify a change to this pipeline at its real surface, the ./seo menu and the scripts it drives, in an isolated scratch tree.
---

# Verifying SEO-LLM

The surface is `./seo` (a terminal menu) and the scripts it runs. Drive the menu,
not the functions: every user-facing path goes through it.

## Setup

```bash
curl -s localhost:8080/models | jq -r '.data[] | "\(.id): \(.status.value)"'   # router must serve qwen
V=$(mktemp -d); mkdir -p "$V"/{research,briefs,outputs}
export RESEARCH_DIR=$V/research BRIEFS_DIR=$V/briefs OUTPUTS_DIR=$V/outputs
```

`RESEARCH_DIR`, `BRIEFS_DIR` and `OUTPUTS_DIR` isolate everything the menu writes,
**except the fetch cache**, which `fetch_page.sh` keeps at `research/_cache` in the
repo unless `FETCH_CACHE_DIR` is set too. Set it if the run must not touch the repo.

## Driving the menu

The menu needs a terminal. Pipe answers into it through `script`:

```bash
printf '3\n<purpose>\n<type>\n\nq\n' | script -qec "./seo <slug>" /dev/null 2>&1 \
  | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/(B//g'
```

- Menu keys: `1`-`9` stages, `a` run all, `s` switch page, `p` redo one drafted part,
  `e` change a recorded answer, `n` accept flagged numbers, `q` quit.
- Every stage ends at "Press enter for the menu." so each stage needs one extra `\n`.
- Replacing an existing artifact asks `[y/N]`; a new slug does not, so the answer
  sequence differs between a fresh page and a rerun. Count the prompts first.
- Piped without a terminal, `./seo <slug>` prints the stage table once and exits,
  which is the cheapest way to read state (and the only way to see `stale`).

## Flows worth driving

- `./seo` with no slug: live question, slug, site URL, export paths (give one bad
  path), competitor URLs, then `2` to collect.
- `3` keyword stage: type, suggestions, then `s` at the confirmation to swap.
- `4` brief stages (one press runs all four), `5` merge with a bad word count first.
- `6`, `7`, `8`, `9`; then `p`, `n`, and `e`, including `e` with an invalid value.
- Stale marker: `touch` the brief, then read the table piped.

## Gotchas

- Model stages take minutes; background long runs and poll the log.
- A redone part is compared by md5 of `sections/0*.md`; compare hash plus name, not
  a `sed 's#.*/##'` of the md5 line, which eats the hash.
- `check.sh` modes are documented user commands and a fair surface for a rule change.
