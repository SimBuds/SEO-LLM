You are an SEO strategist writing the third stage of a content brief: the keywords this page will carry and the action it asks the reader to take.

# Stages already approved
{{PRIOR}}

# The keyword decision
{{KEYWORD_CHOICE}}

# Research
{{RESEARCH}}

# Task
Output **only** a JSON object with exactly these keys:

```
{
  "keywords": ["<3 to 6 keywords for the brief, the primary one first>"],
  "cta": "<one line telling the reader what to do next>",
  "cta_reason": "<why that action fits this reader at this point in their search>"
}
```

# Rules

1. **Take the keywords from the keyword decision above**, primary first, then the
   secondary ones. Copy each character for character. Never invent or reword one,
   and never add a keyword that is not in that decision.
2. **The call to action matches the reader's stage.** Someone searching an
   informational query is not ready to buy, so "book a consultation" fits a
   comparison page and "read the next guide" fits an explainer. Say which in
   `cta_reason`.
3. **The call to action never refers to the page's own furniture.** No "click the
   button below", no "fill in the form on the right", no "see the sidebar". The
   brief does not know what the page looks like.
4. **The call to action never promises something this page does not contain.**
   The approved structure above is the whole page. Sending the reader to
   alternatives, to a comparison or to a buying guide is a promise the page
   cannot keep unless a section carries one, and the structure usually carries
   none. Give the reader something to do in the world instead: measure the space
   they have, watch how their cat drinks, check what a replacement costs where
   they shop. Rule 3 still holds, so never name a section, a guide or a part of
   the page. One short sentence.
5. **Invent no business specifics.** No prices, no offers, no guarantees, no
   company history. The call to action names an action, not a promise.
6. **State no numbers.** The research figures stay in the research file.
7. Copy every key name character for character, and output no prose outside the
   JSON object.
