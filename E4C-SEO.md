# Everything4Cats SEO operating guide

> One maintained reference for planning, creating, publishing, and improving
> search-led content on `everything4cats.ca`.

| Field | Value |
|---|---|
| Source set | Moz's *Beginner's Guide to SEO*, introduction through glossary |
| Source review | 2026-08-12 |
| Project fit | WordPress affiliate reviews and cat-care articles |
| Status | Operating reference; no keyword targets have been approved yet |

## How to use this guide

This document is the project's source of truth for **SEO practice**. Start with
the workflow, use the page checklist before publishing, and use the measurement
loop after publishing. `PLAN.md` still owns product scope and durable project
decisions; `IMPLEMENT.md` still owns work in flight.

This is an original synthesis, not a stored copy of Moz's articles. It retains
the useful principles, removes product promotion and repetition, and translates
the material into decisions for Everything4Cats. Search interfaces, reports,
and ranking systems change; verify a tool's current behaviour before acting on
old screenshots or UI instructions.

## Decisions made while consolidating the sources

- The submitted “Quick Start” label pointed to the Chapter 1 URL. The source map
  below uses Moz's actual Quick Start URL and keeps Chapter 1 as a separate page.
- One operating guide is more useful than ten scraped page copies. Source order
  is preserved in the chapter reference, while repeated advice is consolidated
  into one workflow.
- Tool-specific sales material and obsolete examples are excluded. For example,
  the source still discusses running Universal Analytics beside GA4; this
  project uses GA4 only, and Complianz must gate it on consent.
- Local-business tactics are out of scope. Everything4Cats is a content and
  affiliate site, not a storefront or service-area business.
- Numeric thresholds are diagnostics, not laws. Search volume, title length,
  word count, authority scores, and position are interpreted in context.

## Source map

Each canonical source appears once here. The labels `S0`–`S9` are used in the
chapter reference later in this document.

| ID | Moz source | What it contributes |
|---|---|---|
| S0 | [Guide introduction](https://moz.com/beginners-guide-to-seo) | Priority order and learning framework |
| S1 | [Quick Start Guide](https://moz.com/beginners-guide-to-seo/quick-start-guide) | Baseline setup and first-pass checklist |
| S2 | [SEO 101](https://moz.com/beginners-guide-to-seo/why-search-engine-marketing-is-necessary) | Purpose, ethics, intent, and goals |
| S3 | [How search engines operate](https://moz.com/beginners-guide-to-seo/how-search-engines-operate) | Crawling, indexing, and ranking |
| S4 | [Keyword research](https://moz.com/beginners-guide-to-seo/keyword-research) | Demand, intent, competition, and prioritization |
| S5 | [On-page SEO](https://moz.com/beginners-guide-to-seo/on-page-seo) | Content, metadata, links, images, and URLs |
| S6 | [Technical SEO](https://moz.com/beginners-guide-to-seo/technical-seo) | Rendering, canonicals, schema, mobile, and speed |
| S7 | [Growing popularity and links](https://moz.com/beginners-guide-to-seo/growing-popularity-and-links) | Authority, link earning, outreach, and trust |
| S8 | [Measuring and tracking success](https://moz.com/beginners-guide-to-seo/measuring-and-tracking-success) | KPIs, audits, prioritization, and iteration |
| S9 | [SEO glossary](https://moz.com/beginners-guide-to-seo/seo-glossary) | Shared vocabulary |

## The operating model

SEO connects a real audience need to a page that search engines can discover,
understand, and confidently present. Ranking and traffic are intermediate
signals. The useful outcome is a qualified reader who trusts the answer and
takes an appropriate next action.

### Priority stack

Work in numeric order. A higher layer cannot compensate for a failed lower
layer.

| Order | Requirement | Pass condition |
|---:|---|---|
| 1 | Crawl access | Important URLs can be reached through normal HTML links |
| 2 | Index eligibility | The canonical URL returns `200` and is not blocked or `noindex` |
| 3 | Useful answer | The page resolves the searcher's actual task with original value |
| 4 | Intent alignment | Topic, page type, and format match the result landscape |
| 5 | Clear experience | The page is readable, accessible, mobile-friendly, and fast |
| 6 | Earned confidence | First-hand evidence, citations, bylines, and relevant links support trust |
| 7 | Search presentation | Title, description, URL, imagery, and valid schema describe the page |
| 8 | Learning loop | Outcomes and diagnostics are measured, then the page is improved |

### Everything4Cats guardrails

- **Use before reviewing.** Reviews must contain observations that could only
  come from owning and using the product: setup, measurements, photographs,
  failure modes, cleaning, durability, and which cats or homes it suits.
- **Treat health carefully.** Illness, medication, and diet are adjacent to
  high-stakes health content. Use credible sources and an explicit veterinarian
  posture; do not turn product experience into medical advice.
- **Disclose monetization structurally.** The compliance plugin places the
  disclosure and applies `rel="sponsored nofollow"` to direct links whose
  rendered host matches a configured monetized domain. Editorial citations
  remain ordinary citations. A ThirstyAffiliates cloaked URL may render as an
  internal host, so the integration must be proven with a real link before use.
- **Keep one schema owner.** `e4c-compliance` emits Article JSON-LD. Rank Math's
  competing rich-snippet/schema module stays off. Do not publish self-serving
  `aggregateRating` markup on affiliate comparisons.
- **Do not publish fragile prices.** A price that becomes stale damages both
  trust and affiliate-program compliance. Prefer durable value comparisons
  unless current-price handling is explicitly approved.
- **Research both sides of the border.** The `.ca` domain is Canadian, while the
  intended audience also includes Americans. Compare language, demand,
  availability, and product names by country instead of assuming one market.
- **Earn, never manufacture, authority.** No bought links, mass exchanges,
  fake reviews, undisclosed placements, spun pages, or doorway pages.

## End-to-end SEO workflow

### 1. Define the outcome

Give every proposed page one primary job before researching keywords.

| Page type | Primary reader outcome | Useful project outcome |
|---|---|---|
| Product review | Decide whether the product fits this cat and household | Qualified affiliate click after the programme is joined |
| Comparison | Choose among credible alternatives by use case | Click to the best-fit review or merchant |
| Informational guide | Complete a task or understand a non-medical problem | Newsletter signup or useful onward visit |
| Category hub | Find the right guide, comparison, or review | Deeper navigation without an orphaned page |

Record one primary KPI and any supporting signals. “Rank first” and “get more
traffic” are not end goals; they matter only when the resulting visits help the
reader and the business.

### 2. Establish the baseline

Before changing an existing page, record the comparison period and capture:

- Google Search Console queries, impressions, clicks, click-through rate, and
  average position for the page;
- organic entrances and the page's intended outcome once consent-gated GA4 is
  available;
- index status, canonical URL, response code, mobile render, and sitemap state;
- referring domains and internal links pointing to the page; and
- the current title, description, publish/update date, and major content gaps.

For a new page, the baseline is the current result page: dominant intent,
formats, SERP features, competitors, freshness, depth, and missing value.
Search Console is the primary operational dataset; Bing Webmaster Tools can be
added after launch as a secondary diagnostic, not as a way to buy or guarantee
visibility.

### 3. Discover demand

Start with audience problems, not a phrase the publisher wants to rank for.
For each topic, ask who is searching, what they need, when the need occurs, how
they describe it, why they care, and whether language or products differ by
country.

Build candidates from:

- the recurring-needs categories in `PLAN.md`: toys, litter, food, furniture,
  storage, and related household problems;
- queries and pages already receiving impressions in Search Console;
- real customer language in communities, retailer questions, support material,
  and conversations—used as research, never copied;
- related searches, question features, autocomplete, trend data, and keyword
  tools; and
- gaps and recurring formats among actual search competitors.

For each candidate record: topic, query cluster, intent, country, seasonality,
estimated demand, competitiveness, current ranking URL, proposed page type,
business value, evidence available, health risk, and status. Volume is an
estimate, not a promise; a specific low-volume query with strong fit can be more
valuable than a broad popular query with ambiguous intent.

### 4. Determine intent and format

Inspect the live results rather than inferring intent from the words alone.
Result types reveal whether people expect a quick answer, images, a list, a
comparison, a product page, a video, or something else.

| Intent | Meaning | Everything4Cats example | Likely page |
|---|---|---|---|
| Informational | Learn or solve a problem | “how to reduce litter tracking” | Practical guide |
| Commercial investigation | Compare before choosing | “covered vs open litter box” | Evidence-led comparison |
| Transactional | Take a purchase action | “buy stainless steel litter box” | Merchant result; support with a relevant review |
| Navigational | Reach a known site or brand | “Everything4Cats litter reviews” | Brand or category page |
| Local | Find something nearby | “cat shelter near me” | Out of scope unless the project adds a real local offering |

Do not force a review into a result set that clearly rewards tutorials, or write
a long guide when the task needs a short comparison table. A mixed result set
signals ambiguous intent; narrow the topic or explicitly serve the useful
sub-intents.

### 5. Map one intent cluster to one URL

Group synonyms and close variants that seek the same answer. Create one strong
page for the cluster rather than thin pages for every wording. Before approving
a new URL:

1. Search the site for an existing page that serves the intent.
2. Refresh or expand that page when it can satisfy the cluster.
3. Create a new page only when the reader needs a materially different answer
   or format.
4. Assign a stable, lowercase, hyphenated, descriptive slug.
5. Choose the hub and related pages that will link to it with natural anchors.

This prevents duplicate value, keyword cannibalization, orphan pages, and
unnecessary redirects.

### 6. Write the brief before the draft

Use this compact brief:

```markdown
Page goal:
Audience and country:
Primary intent:
Query cluster and important questions:
Recommended page type and format:
Existing URL to reuse, or proposed slug:
Unique first-hand evidence and assets:
Competitor gaps this page will close:
Required sections and answer near the top:
Health, legal, price, or affiliate constraints:
Internal links in / internal links out:
Primary reader action and KPI:
Owner, publish date, and review date:
```

### 7. Create an answer worth choosing

- Put the direct answer or recommendation early, then supply the evidence.
- Organize headings around reader decisions, not a quota of keywords.
- Show the test method, dates, conditions, photographs, measurements, tradeoffs,
  and limitations. State who should **not** buy the product.
- Cover the meaningful questions in the cluster without padding to a word count.
- Add value missing from current results; do not rephrase their consensus and
  call it original.
- Keep important wording in rendered HTML, not only inside images or scripts.
- Cite claims to relevant, trustworthy primary sources. Affiliate merchants are
  sources for specifications, not independent proof of quality.
- Use descriptive alt text for informative images and empty alt text for purely
  decorative images. Do not stuff keywords into either.
- Display the author and meaningful update date. Refresh because facts or
  recommendations changed, not merely to manufacture a newer timestamp.

### 8. Complete the on-page pass

| Element | Rule |
|---|---|
| Title tag | Unique, accurate, compelling, and front-loaded with the topic when natural; clarity beats a rigid character count |
| H1 | One clear page topic; it may differ from the title tag when that improves reading |
| Introduction | Confirm the problem and deliver useful direction without a long preamble |
| Headings | A logical outline that lets readers scan to the answer they need |
| Keywords | Primary phrase, variants, and related concepts used naturally; never repetition for its own sake |
| Meta description | Unique reason to click and an honest preview; Google may generate a different snippet |
| URL | Stable, readable, HTTPS, lowercase, hyphenated, and free of unnecessary dates or parameters |
| Internal links | Relevant destinations with descriptive, varied anchor text; update old links at the source after a move |
| External citations | Relevant evidence from sources the article is willing to endorse |
| Images | Original where possible, compressed, correctly sized, responsive, and accessible |
| Breadcrumbs | Reflect the real hierarchy and link back to useful parents; add matching structured data only when implemented accurately |
| Favicon | Recognizable at small sizes and consistent with the brand; a presentation aid, not a ranking tactic |
| Tables/lists | Used when comparison or ordered steps genuinely help, not to chase a result feature |
| Disclosure | Visible before an affiliate action; structural plugin output verified in the rendered page |

### 9. Complete the technical pass

The canonical page must:

- return `200` over HTTPS without a redirect chain;
- be reachable through ordinary HTML navigation or contextual links;
- render the same essential content and links on mobile and desktop;
- carry the intended robots directive and a self-referencing canonical unless a
  different canonical is deliberately required;
- appear in the XML sitemap only when it is canonical and intended for indexing;
- produce no blocked critical CSS, JavaScript, image, or font resources;
- load without layout-breaking overflow at wide, narrow, and intermediate
  widths, and perform acceptably under measured mobile conditions;
- emit one valid, visible-content-matching Article schema graph with the correct
  public byline and dates; and
- when monetized, render a real affiliate link whose disclosure,
  `rel="sponsored nofollow"`, tracking, and final merchant destination are all
  observed rather than inferred from plugin settings.

Use Search Console's URL inspection and rendered output to check what Google can
retrieve. A browser screenshot alone does not prove crawlability or indexability.
Structured data makes content easier to classify and may enable enhanced search
features; it does not guarantee them or repair weak content.
Do not add `hreflang` merely because the site uses a `.ca` domain and serves
readers in more than one country; it is needed only if separate URLs provide
deliberately localized language or regional versions.

#### Control selection

| Need | Correct control | Important distinction |
|---|---|---|
| Keep private content private | Authentication | `robots.txt` is public and is not access control |
| Prevent indexing but allow access | `noindex` directive | The crawler must fetch the page to see it |
| Reduce duplicate URLs | Canonical plus consistent internal links | A canonical is a preference signal, not a redirect |
| Permanently move a page | Relevant `301`, then update source links | Avoid chains and irrelevant destinations |
| Temporarily move a page | `302` or equivalent temporary redirect | Keep the original URL as the intended long-term location |
| Remove a gone page | Honest `404`/`410`, or relevant replacement | Do not redirect every removed page to the home page |
| Aid discovery | Clean navigation and XML sitemap | A sitemap does not replace internal links |
| Limit crawler paths | Carefully scoped `robots.txt` | Blocking crawl can hide canonical or `noindex` instructions |

### 10. Build authority by being referable

The strongest links are editorial choices from relevant, credible pages whose
audiences would benefit even if search engines did not exist. A healthy profile
grows over time, spans multiple relevant domains, uses varied natural anchors,
and can include both followed and qualified links.

Link-worthy Everything4Cats assets include original product testing, comparison
methodologies, durability or cleaning data, original photography, calculators,
checklists, and well-sourced reference guides. Promote them through concise,
personal outreach to pet publications, shelters, cat organizations, relevant
creators, and partners for whom the resource is genuinely useful. Unlinked
mentions and outdated resource pages can be reasonable outreach opportunities.

Reject paid followed links, undisclosed product-for-link arrangements, mass
guest posting, automated directory submissions, comment spam, private link
networks, exact-anchor campaigns, fake reviews, and large reciprocal schemes.
Social sharing can create awareness and indirectly lead to editorial links, but
a share is not itself a backlink.

### 11. Measure, diagnose, and improve

Use a ladder of metrics so diagnostics never replace the business outcome.

| Level | Measures | Question answered |
|---|---|---|
| Outcome | Qualified affiliate clicks, newsletter signups, or another declared conversion | Did search activity help the project? |
| Search performance | Organic conversions, clicks, impressions, CTR, landing-page sessions | Did the right searchers choose the page? |
| Visibility | Query/page position and relevant SERP features | Where and how is the page appearing? |
| Authority | Relevant referring domains, earned mentions, referral visits | Is external confidence growing? |
| Technical health | Indexed canonical pages, crawl errors, response codes, mobile performance | Can the system reliably retrieve and serve it? |

Interpret engagement by page purpose. A short visit can mean an immediate answer
or a failed page; a long visit can mean interest or confusion. Rankings,
third-party authority scores, raw backlink totals, word count, and bounce-like
metrics are supporting evidence, never success by themselves.

#### Review cadence

- **After publishing:** inspect the live URL, rendered content, canonical,
  schema, internal links, index eligibility, and analytics event once.
- **Weekly during launch:** review Search Console coverage and unexpected
  technical failures; avoid rewriting a page in response to ordinary daily
  ranking movement.
- **Monthly:** compare equivalent periods for queries, pages, CTR, organic
  outcomes, new/lost relevant links, and content opportunities.
- **Quarterly:** audit topic coverage, cannibalization, stale claims, broken
  links, slow templates, declining pages, and pages with no distinct value.
- **After a material change:** annotate the date, hypothesis, affected URL, and
  baseline; change one major variable when practical so the result is legible.

#### Diagnostic sequence

1. **No discovery or indexation:** check status, robots, `noindex`, canonical,
   internal links, sitemap, rendering, and Search Console evidence.
2. **Impressions but few clicks:** compare intent, result format, title,
   description, brand trust, and SERP features.
3. **Clicks but weak engagement:** check answer placement, speed, mobile layout,
   readability, evidence, and whether the page delivers the promised format.
4. **Engagement but no outcome:** check product fit, disclosure placement,
   calls to action, link function, and whether the requested next step is fair.
5. **Decline after prior success:** check technical changes, intent shifts,
   stronger competing pages, outdated facts, lost links, seasonality, and
   measurement changes before editing.

Prioritize by impact on the declared goal, number/value of affected pages,
confidence in the diagnosis, effort, reversibility, and urgency. Fix broad crawl
or index failures before polishing a single description.

## Everything4Cats launch baseline

This table is a dated integration snapshot, not a substitute for current state
in `IMPLEMENT.md`.

| As of 2026-08-12 | SEO consequence |
|---|---|
| Search Console domain property is DNS-verified | Keep the TXT record; no theme-dependent verification is needed |
| `blog_public` is `0` | The site intentionally remains outside normal indexing until launch |
| Rank Math owns sitemaps | Do not add a second sitemap owner |
| `e4c-compliance` owns Article schema | Keep Rank Math's competing schema module off |
| Complianz will own the GA4 tag | Analytics must remain consent-gated; Site Kit stays inactive |
| Affiliate-domain list is empty | No affiliate disclosure/tagging appears until a programme is actually configured |
| Theme and real content have not landed | Do not use the default pages or appearance as an SEO baseline |
| `/xmlrpc.php` deliberately returns `403` | Do not misclassify that expected refusal as a crawl defect |

### Launch SEO gate

- Delete WordPress fixtures and confirm every public page has a deliberate job.
- Fix the public display name and author slug before Article schema is exposed.
- Complete the Rank Math and Complianz configuration without creating duplicate
  schema, sitemap, verification, or analytics owners.
- Test titles, descriptions, canonicals, internal links, mobile rendering,
  response codes, Article schema, and affiliate disclosure on rendered pages.
- With the real affiliate configuration, test a direct or cloaked link end to
  end: disclosure before action, `rel="sponsored nofollow"`, one working tracking
  redirect, and the correct merchant destination. An internal cloaked host does
  not automatically match the compliance plugin's external-domain list.
- Confirm the intended canonical host is `https://everything4cats.ca`, with
  other host/protocol variants redirecting directly to it.
- Confirm the sitemap contains only canonical, index-worthy URLs.
- Follow the approved launch phase for state changes. The final indexing action
  is changing `blog_public` from `0` to `1`; on the same day, confirm the sitemap
  is served and submit it in Search Console.
- After the site is live, activate and verify the planned page cache without
  masking stale markup or breaking consent, schema, or logged-out rendering.

## Per-page publishing checklist

### Strategy and evidence

- [ ] One audience, country scope, intent, page type, and primary outcome named
- [ ] Existing-site and cannibalization check completed
- [ ] Live result landscape inspected; required format understood
- [ ] Unique first-hand evidence/assets identified and actually present
- [ ] Health, price, affiliate, and sourcing risks resolved

### Content and presentation

- [ ] Direct answer appears early and matches the title's promise
- [ ] Tradeoffs, limitations, and poor-fit cases are explicit
- [ ] Headings form a useful outline; no keyword stuffing or padded sections
- [ ] Title, H1, description, slug, byline, and dates are accurate and unique
- [ ] Images are licensed/original, compressed, dimensioned, and appropriately alt-tagged
- [ ] Internal links connect the page to a hub and relevant next steps
- [ ] Editorial claims use credible citations; a rendered monetized link proves
      disclosure, `sponsored nofollow`, tracking, and destination behaviour

### Technical and measurement

- [ ] Live canonical URL returns `200` over HTTPS with intended index directive
- [ ] Canonical, sitemap state, robots rules, and redirects agree
- [ ] Mobile and desktop render the same essential content and links
- [ ] No narrow or intermediate-width overflow; key interactions work
- [ ] One correct Article schema graph matches visible content
- [ ] Primary outcome and supporting search metrics can be measured lawfully
- [ ] Publish date, baseline, owner, and review date are recorded

## Chapter reference

### S0 — Introduction

- **Core idea:** SEO is layered; discovery and a useful answer come before
  polish or advanced search features.
- **Practice:** learn enough to execute, observe results, and improve rather
  than treating the guide as theory.
- **Failure mode:** optimizing titles, schema, or links for pages that cannot be
  crawled or do not deserve to rank.
- **Everything4Cats:** establish a small, trustworthy review system before
  expanding engineering or chasing broad cat keywords.

### S1 — Quick Start

- **Core idea:** collect first-party data, inspect indexation, choose focused
  queries, improve search presentation, publish useful content, link it into the
  site, then earn external attention.
- **Practice:** set a baseline in Search Console and analytics, crawl the site,
  inspect representative URLs, and fix foundational failures first.
- **Failure mode:** assuming a good-looking browser page is indexable, or
  treating registration and sitemap submission as traffic-generating tactics.
- **Everything4Cats:** most setup is intentionally deferred until the real theme
  and content exist; launch controls in this document override generic timing.

### S2 — SEO 101

- **Core idea:** SEO serves people through organic search by matching their goal
  and giving crawlers an understandable version of the answer.
- **Practice:** choose a measurable business outcome, follow search-engine
  quality guidance, and analyze the live SERP for intent and format.
- **Failure mode:** traffic as an end goal, thin affiliate pages, cloaking,
  doorway pages, keyword stuffing, or deceptive tactics.
- **Everything4Cats:** trust and qualified actions matter more than raw visits;
  reviews without use evidence fail both the reader and the business model.

### S3 — Crawling, indexing, and ranking

- **Core idea:** discovery, storage eligibility, and result ordering are
  different stages with different failure modes.
- **Practice:** provide HTML link paths, consistent directives, clean statuses,
  canonical URLs, useful 404s, direct redirects, and an index-worthy sitemap.
- **Failure mode:** using `robots.txt` as privacy, blocking a page whose
  `noindex` or canonical must be read, orphaning pages, or mixing directives.
- **Everything4Cats:** the intentional `blog_public=0` state blocks launch
  visibility; it is a feature until all public pages are ready.

### S4 — Keyword research

- **Core idea:** research is audience research expressed through search demand,
  intent, format, timing, location, and competition.
- **Practice:** expand seed topics, study existing impressions and competitors,
  group variants by intent, and prioritize attainable, valuable specificity.
- **Failure mode:** targeting what the publisher calls a product rather than
  what readers seek, equating volume with value, or creating a page per phrase.
- **Everything4Cats:** favor concrete recurring problems and commercial
  comparisons where first-hand product evidence creates a defensible advantage.

### S5 — On-page SEO

- **Core idea:** turn a query cluster into a uniquely useful, readable page and
  describe it clearly through headings, metadata, links, images, and URLs.
- **Practice:** inspect current winners, identify missing value, write for task
  completion, and use natural language in every visible and machine-read field.
- **Failure mode:** duplicate/thin variants, copied material, hidden text,
  keyword quotas, inaccessible images, formulaic anchors, and unstable URLs.
- **Everything4Cats:** original testing and photography are the differentiator;
  a rewritten merchant description is not a review.

### S6 — Technical SEO

- **Core idea:** HTML delivery, rendering, structured meaning, mobile parity,
  and performance determine whether the useful page reaches people and bots.
- **Practice:** keep critical content server-rendered or reliably renderable,
  use accurate canonicals and schema, serve responsive images, and measure speed.
- **Failure mode:** duplicate schema owners, invisible script-loaded essentials,
  inaccurate markup, blocked resources, or mobile/desktop content divergence.
- **Everything4Cats:** WordPress supplies the base HTML; the theme must preserve
  Article markup, consent behaviour, responsive media, and logged-out speed.

### S7 — Links and authority

- **Core idea:** relevant editorial links, brand awareness, first-hand
  experience, and consistent trust signals help establish authority.
- **Practice:** create genuinely referable assets, promote them personally,
  cultivate relevant relationships, and measure qualified referrals as well as
  unique linking domains.
- **Failure mode:** buying ranking credit, mass exchanges, spam outreach,
  irrelevant directories, exact-anchor manipulation, or fake sentiment.
- **Everything4Cats:** product evidence and useful cat-owner resources are the
  link strategy; affiliate relationships are disclosed commercial links, not
  manufactured editorial votes.

### S8 — Measurement and execution

- **Core idea:** begin with one primary outcome, monitor supporting diagnostics,
  prioritize high-impact work, and iterate from observed evidence.
- **Practice:** segment organic performance, compare equivalent periods, audit
  crawl/index/content/link health, and annotate meaningful changes.
- **Failure mode:** vanity dashboards, interpreting every bounce or position
  movement as quality, changing several variables, or polishing low-impact pages
  while a site-wide failure remains.
- **Everything4Cats:** the first meaningful dataset begins after real content,
  consent-gated analytics, and the launch flip—not from the default install.

### S9 — Glossary

Moz's full glossary is a learning aid. The working vocabulary below is the
smaller set needed to operate this project.

## Working glossary

| Term | Operational meaning |
|---|---|
| 301 / 302 | Permanent / temporary redirect; use according to the intended duration |
| 4xx / 5xx | Client-side request failure / server-side response failure |
| Alt text | Text alternative describing an informative image for accessibility and context |
| Anchor text | Clickable words of a link; keep them descriptive and natural |
| Backlink | Link from another domain to this site |
| Canonical | Declared preferred URL among duplicate or near-duplicate versions |
| Commercial investigation | Search intent focused on comparing options before acting |
| Conversion | Completion of the page's declared useful action |
| Crawl | A search bot's retrieval and discovery of URLs and resources |
| CTR | Clicks divided by impressions for the same result set |
| E-E-A-T | Experience, expertise, authoritativeness, and trustworthiness as quality concepts |
| Index | Search engine's stored set of eligible content |
| Internal link | Link between two pages on `everything4cats.ca` |
| Keyword cannibalization | Multiple site pages competing to serve substantially the same intent |
| Keyword difficulty | Tool estimate of competitive effort, useful only as a relative input |
| KPI | Measure tied to an agreed objective, not merely an available metric |
| Link equity | Descriptive model for ranking value that links may pass |
| Long-tail query | Specific, usually lower-demand phrase with comparatively clear intent |
| Meta description | Suggested search snippet summary; not a direct ranking factor or guaranteed display |
| `noindex` | Directive requesting that a retrieved resource not enter search results |
| `nofollow` | Link qualification indicating ordinary ranking credit should not be expected |
| Organic | Search visibility or traffic not purchased as advertising |
| Orphan page | URL with no normal internal link path from the site |
| Query | Words or other input submitted to a search engine |
| Ranking | Ordering eligible results for a particular query and context |
| Referring domain | Distinct external domain containing at least one backlink |
| Robots meta | Page-level crawl/index instructions embedded in HTML |
| `robots.txt` | Public, host-level crawler guidance; neither privacy nor guaranteed de-indexing |
| Schema / structured data | Machine-readable labels describing visible page entities and attributes |
| Search intent | Task the searcher is trying to complete |
| Search volume | Estimated searches for a query over a stated place and period |
| Seed keyword | Starting topic used to discover related demand and language |
| SERP | Search engine results page |
| SERP feature | Non-standard result treatment such as a snippet, image block, or question module |
| Sitemap | Machine-readable list aiding discovery of canonical, index-worthy URLs |
| `sponsored` | Link relationship marking advertising, sponsorship, or compensated placement |
| Title tag | HTML page title commonly used as an input to the search result headline |
| URL slug | Human-readable final path segment identifying a page |

## Maintenance rule

Update this file when a durable SEO practice or project SEO constraint changes.
Record experiments with a date, hypothesis, baseline, result, and affected URL;
do not turn one observation into a universal rule. Re-check the source set and
current search-engine documentation before relying on a UI path, a named report,
a numeric threshold, or a claim about a ranking system.
