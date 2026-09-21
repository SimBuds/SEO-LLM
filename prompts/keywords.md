You are an SEO strategist choosing what one page should target, using only the research below.

# What this page is for
{{PAGE_PURPOSE}}

# Research
{{RESEARCH}}

# Task
Output **only** a JSON object with exactly these keys:

```
{
  "primary_keyword": "<the one term this page targets>",
  "secondary_keywords": ["<2 to 6 supporting terms>"],
  "intent": {
    "type": "<blog post | landing page | product page | category page | tool | video>",
    "format": "<how-to guide | listicle | comparison | ultimate guide | calculator or template | informational page>",
    "angle": "<the hook the ranking pages share, in a few words>"
  },
  "business_potential": {
    "score": <0 to 3>,
    "reason": "<why that score>"
  },
  "questions": ["<questions the ranking pages answer, most common first>"],
  "must_cover": ["<subtopics the ranking pages all cover>"],
  "rationale": "<why this keyword over the alternatives in the research>"
}
```

# Rules

1. **Every keyword you return must appear in the research above**, in the keyword
   list or in a competitor's title or headings. Copy it character for character.
   Never invent a keyword, never merge two into a new phrase, and never reword one.
2. **Pick the primary keyword on demand and fit.** The research carries one of
   two kinds of demand data, and which one it is decides how you argue the
   choice. Work out which case applies before you write `rationale`.

   **Case A, the research has measured data**, meaning at least one keyword
   carries impressions or clicks. Prefer a term that really produced
   impressions for this site, especially one already ranking just off the first
   page, where a better page moves it. A term with fewer impressions wins when
   it matches what this page is for, or when the pages ranking for it are
   weaker. State that trade-off in `rationale`. This data is measured, so never
   call it estimated and never call it volume.

   **Case B, no keyword carries impressions or clicks**, so the
   research holds estimated third-party data instead. Prefer a term with more
   estimated volume, and prefer an easier one when the difficulty separates two
   terms that otherwise fit equally. Call this demand estimated rather than
   measured, treat it as a ranking of terms against each other rather than as
   real traffic, and let the competitor pages settle a close call.

   **Case C, the research carries no demand data of either kind.** Choose on fit
   with what the page is for and on what the competitor pages show, and say so.

   In every case, describe the data in words only, as rule 3 requires ("the most
   impressions", "the highest estimated volume", "easier to rank for"), and
   never write the numbers themselves.
3. **Do not repeat any number from the research.** The impressions, positions and
   any other figures are already recorded. Refer to them in words ("the query
   with the most impressions", "already close to the first page"), not as
   figures. Never compare two numbers you were not given.
4. **Read the intent from the competitor pages**, not from the keyword. Their
   shared type, format and angle is what the searcher expects, and a page in the
   wrong format does not rank.
5. **Score business potential** on this scale: 3 the product is essential to the
   answer, 2 the product helps but alternatives exist, 1 the product can only be
   mentioned in passing, 0 the product cannot be mentioned naturally.
6. **`questions` come from the competitor headings**, especially ones phrased as
   questions. Return an empty list rather than inventing any.
7. **`must_cover` are subtopics several competitors share.** These become the
   page's sections, so name them as topics, not as sentences.
8. Copy every key name character for character, and output no prose outside the
   JSON object.
