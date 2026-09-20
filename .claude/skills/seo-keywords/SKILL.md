---
name: seo-keywords
description: Choose what one page should target from its collected research: the primary and secondary keywords, the search intent (type, format, angle), a business-potential score, and the questions and subtopics the ranking pages cover. Phase 8 stage, between /seo-research and the brief. Use when the user runs /seo-keywords <slug> or asks which keyword a page should target.
---

# seo-keywords

Turn `research/<slug>/research.json` into `research/<slug>/keywords.json`: the
one decision every later stage is built on.

## Inputs

- `$1` the slug. If missing, ask which page.
- The page's purpose in one line. Take it from the user's earlier description if
  they gave one, otherwise ask: **"In one line, what is this page for and who is
  it for?"** Do not invent it from the slug.

## Preconditions

1. The router serves `qwen`: `curl -s localhost:8080/models | jq -er '.data[] | select(.id=="qwen") | .id'` prints `qwen`. If not, stop and say the router is not serving it.
2. `research/<slug>/research.json` exists. If not, stop and say to run `/seo-research <slug>` first.
3. If `research/<slug>/keywords.json` already exists, show it and ask before replacing it.

## Steps

1. Run `bash scripts/check.sh research research/<slug>/research.json` and read the
   WARN lines. Thin research is allowed, but say what is thin before spending a
   call on it, because the choice is only as good as its input.
2. Fill and call, as one chained command so an unfilled placeholder cannot reach
   the model:
   ```bash
   bash scripts/fill_prompt.sh prompts/keywords.md \
     --set-file RESEARCH=research/<slug>/research.json \
     --set PAGE_PURPOSE="<the one-line purpose>" \
     > research/<slug>/_keywords_prompt.txt \
   && bash scripts/llm_call.sh research/<slug>/_keywords_prompt.txt 0.2 1 \
        prompts/keywords.schema.json > research/<slug>/keywords.json
   ```
   The schema argument constrains the reply, so nothing needs stripping.
3. Check: `bash scripts/check.sh keywords research/<slug>/keywords.json research/<slug>/research.json`.
4. On a FAIL, retry once with seed 2. A second failure means the research does
   not support a confident choice: show the FAIL lines and the research WARNs,
   and ask the user to pick the primary keyword rather than retrying again.
5. Report:
   - the primary keyword and why it won over the alternatives, in the model's own
     rationale
   - the secondary keywords
   - the intent read: type, format and angle, and whether the existing page (when
     there is one) matches that format
   - the business-potential score with its reason
   - the questions and the must-cover subtopics, which become the FAQ and the
     sections
   - every WARN line
6. Close with: *"Review `research/<slug>/keywords.json`, then run `/seo-brief
   <slug>`."* If the user asks to run it, say that stage is not built yet.

## Failure handling

- `check.sh keywords` FAILs when a keyword is absent from the research file. That
  means the model reworded or invented it, and the fix is a retry, never editing
  the research to match.
- A WARN about repeated figures means the reasoning restated volumes or
  difficulties. They belong in `research.json` alone. Mention it, and do not edit
  the numbers out by hand.
- Do not fix the choice silently. Propose the edit and let the user decide.

## Out of scope

No brief, no outline, no metadata. The word-count target is not set here: it comes
from the competitor word counts at the brief stage. Never search the web for
keywords, and never call an Ahrefs or Google API. The only inputs are the research
file and the user's one-line purpose.
