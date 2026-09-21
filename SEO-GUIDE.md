# Comprehensive SEO Master Guide: From Fundamentals to Execution

The conceptual reference behind this repository's pipeline, covering the
baseline and the intermediate practice. No script parses it, but three of its
targets are enforced in code by `scripts/check.sh`: a title of **50 to 60
characters**, a meta description of **150 to 160**, and the **top 3-5 ranking
pages** as competitors. Changing them here means changing them there.

**On currency.** The structural advice (intent, crawling, linking, measurement)
is stable. Anything naming a product, a rich result's eligibility or a named
ranking system dates quickly and should be checked against Google Search Central
and the Search Quality Rater Guidelines. The fastest-expiring claims are marked
**[verify]**.

---

## Table of Contents
1. [SEO 101: Search Engine Optimization Fundamentals](#1-seo-101-search-engine-optimization-fundamentals)
2. [Module 0: Measurement and Tooling Setup](#2-module-0-measurement-and-tooling-setup)
3. [Module 1: Keyword Research and Search Intent](#3-module-1-keyword-research-and-search-intent)
4. [Module 2: On-Page SEO & Content Optimization](#4-module-2-on-page-seo--content-optimization)
5. [Module 3: Link Building & Off-Page SEO Strategies](#5-module-3-link-building--off-page-seo-strategies)
6. [Module 4: Technical SEO, Auditing, and Site Maintenance](#6-module-4-technical-seo-auditing-and-site-maintenance)
7. [Module 5: Local SEO](#7-module-5-local-seo)
8. [Module 6: Measuring and Iterating](#8-module-6-measuring-and-iterating)
9. [SEO Execution Checklist & Operational Workflow](#9-seo-execution-checklist--operational-workflow)
10. [Appendix: Glossary of Terms](#10-appendix-glossary-of-terms)

---

## 1. SEO 101: Search Engine Optimization Fundamentals

### What is Search Engine Optimization?

SEO is the work of making pages rank in organic (unpaid) results, to earn
intent-driven traffic continuously. Search engines do not search the live web:
they crawl it, store copies in an **index**, and answer a query from that index.
SEO is structuring your site so the engine recognizes your page as the best
answer to a specific query.

---

### Organic Search vs. Paid & Alternative Channels

| Traffic Channel | Cost Structure | Sustainability | Intent Level | Reach & Scalability |
| :--- | :--- | :--- | :--- | :--- |
| **Organic SEO** | Free traffic per click, upfront labor investment | High (compounds over time) | Active search intent | Billions of global users |
| **Paid Ads (PPC)** | Pay-per-click, ongoing ad budget required | Zero traffic once budget stops | High commercial intent | Scalable based on budget |
| **Social Media** | Organic reach decays rapidly | Spiky, short shelf-life | Passive browsing | Broad but low intent |
| **Email Marketing** | Platform fee, low per-message cost | Requires existing subscriber list | High engagement | Limited to opted-in users |

Three advantages follow from that table. Rankings **compound**, where paid
traffic stops the day the budget does. Search demand is **stable** month to
month, where social and email spike and decay. And search reaches people at the
**moment they are looking**, which no other channel does at that scale.

---

### How Search Engines Work: Crawling, Indexing, and Ranking

```
[ Web Spiders / Crawlers ] ---> [ Indexing Engine ] ---> [ Ranking Algorithm ]
   Discovers new & updated         Parses HTML, content,     Evaluates 200+ signals
   pages via links & sitemaps       structure, & metadata     to rank pages on SERPs
```

1. **Crawling:** bots such as Googlebot follow links and sitemaps to discover pages and their assets.
2. **Indexing:** the page is parsed and stored, unless it fails quality checks or a directive blocks it.
3. **Ranking:** for each query the algorithm weighs hundreds of signals, including relevance, links, speed, intent match and experience.

**Crawled is not indexed, and indexed is not ranked.** Three gates, and a page
can pass one and fail the next. Search Console reports them separately, so when
traffic is missing, find out which gate the page is stuck behind before changing
anything.

---

### The Four Types of Search Intent

Naming a query's goal decides what kind of page can rank. No amount of
optimization makes the wrong page type win.

| Intent | The searcher wants | Typical query | What ranks |
| :--- | :--- | :--- | :--- |
| **Informational** | To learn something | "what is a canonical tag" | Guides, explainers, videos |
| **Navigational** | To reach a known destination | "moz login" | The brand's own page |
| **Commercial** | To compare before deciding | "best crm for small business" | Reviews, comparisons, listicles |
| **Transactional** | To act now | "buy standing desk online" | Product and category pages |

Intent is read off the live results page, not guessed from the wording. If the
results for a query you read as transactional are all tutorials, the tutorials
are right and you are wrong.

---

### Anatomy of a SERP and Its Features

A results page is not ten blue links. Features share the space and change how
much traffic position one is worth.

* **Featured snippet:** an answer extracted above the results, taken from a page already ranking on page one.
* **People Also Ask (PAA):** related questions, and the cheapest source of real FAQ questions you will find.
* **Local pack:** three map listings for local queries, won through Google Business Profile rather than page content (Module 5).
* **Image pack, video carousel, top stories:** media results that push organic links down.
* **Knowledge panel:** an entity summary for brands, people and places.
* **Sitelinks:** sub-links under a brand's own result, generated by Google.
* **AI-generated answers:** a synthesized answer above the results, with links out. **[verify]** Coverage and link behaviour are changing quickly.

**Zero-click searches** end on the results page because a feature answered them.
So a high-volume question can deliver far less traffic than its volume suggests,
and appearing inside the feature beats the rank below it.

---

### White Hat, Black Hat, and the User-First Test

Working inside published guidelines is **white hat**. Working against them is
**black hat**, and the downside is a manual action, algorithmic suppression, or
being **de-indexed** entirely.

**The user-first test:** *would I do this if search engines did not exist?* A
tactic that only makes sense as a signal to a crawler is the tactic to drop.

Practices that cross the line:

* **Cloaking:** showing engines different content from human visitors. The clearest violation there is.
* **Sneaky redirects:** sending the crawler one way and the human another.
* **Hidden text and links:** white on white, zero-size fonts, off-screen positioning.
* **Doorway pages:** near-identical pages per keyword or city funnelling to one destination.
* **Link schemes:** buying or exchanging links, private blog networks, bulk reciprocal linking.
* **Scaled content abuse:** generating pages mainly to manipulate rankings. This is the policy that matters when a model writes your drafts, and it turns on purpose and quality, not on whether a machine was involved.
* **Site reputation abuse:** hosting third-party content on a trusted domain to borrow its ranking strength. **[verify]**

The grey area is real. Guest posting, digital PR and partnerships sit on a
spectrum, and the line is whether a link is editorially earned or paid for. When
it is paid, mark it `rel="sponsored"` and keep it rather than hiding it.

---

## 2. Module 0: Measurement and Tooling Setup

Do this before strategy. Without a baseline you cannot tell a win from noise.

### Analytics

* **Install analytics before publishing anything new.** GA4 is the default. Matomo, Plausible and Fathom collect less and are easier to justify under consent rules, at some cost in integration.
* **Confirm it records** a session, a page view and a conversion, by triggering one and finding it. A tag firing on half your templates is worse than none, because the numbers look real.
* **Define conversions first.** Decide what a valuable session is (a form, a call, a booking, a purchase) and record it as an event, or reporting collapses into vanity metrics.

### Google Search Console

The most important account in SEO, and what this pipeline is built around. It is
Google reporting what happened, not a vendor modelling what might have.

* **Queries with impressions, clicks, CTR and average position**, measured, for your pages.
* **Index coverage**, page by page, with the reason for each exclusion.
* **URL inspection:** what Google last fetched, how it rendered, which canonical it chose.
* **Core Web Vitals field data** and the structured data it recognized.

Verify the property, submit the sitemap, and export the Performance report as
CSV. That export is this pipeline's keyword input.

**Why measured first.** Third-party suites sell search volume, keyword
difficulty and traffic potential. Those are models built from panels and
extrapolation, they disagree with each other, and they are wrong in ways you
cannot audit. Measured data wins every time it exists.

**What to do when it does not.** Search Console only describes queries you
already appear for, so a brand new site, or an established one moving into a
topic it has never ranked for, has nothing measured to read. Estimated data is
the accepted fallback there, because ranking ten candidate terms against each
other is still better than guessing. Two rules keep it honest. Read the figures
as relative positions rather than as traffic you will receive, since the
absolute numbers are the part that is most wrong. And let the pages that
already rank settle a close call, because those are observed fact and the
volume figure is not.

### Bing Webmaster Tools

Covers Bing and several AI answer products drawing on its index, with the same
kind of first-party data plus **IndexNow**, which pushes changed URLs instead of
waiting for a crawl.

### Your Sitemap

`sitemap.xml` is the list of URLs you are asking engines to index, and your
cheapest inventory of your own pages.

* **Find it** at `domain.com/sitemap.xml`, or from the `Sitemap:` line in `robots.txt`, which wins when they disagree.
* **A sitemap index** is a sitemap of sitemaps, normal on larger sites. Follow its children for the full list.
* **Use it as an inventory:** which of your pages already target this topic (the cannibalization check), and which should link to the new one.
* **Keep it honest.** URLs that 404, redirect or carry `noindex` do not belong in it, and a page missing from it is one you never really asked to have indexed.

### Baseline Site Crawl

Crawl your own site before changing anything, with Screaming Frog, Sitebulb or
equivalent. These read your site directly, so the output is fact. Look for
broken links and redirect chains, duplicate or missing titles and descriptions,
orphan pages, accidental `noindex` tags and `robots.txt` blocks, and thin or
near-duplicate pages. Keep that first crawl: it is the only before-picture you
will ever have.

### Tracking Position Over Time

Search Console's average position, filtered by query and page, is free measured
rank history. Compare periods rather than reading one number, since position
averages over every impression in the range. Dedicated rank trackers add daily
granularity and competitor comparison, which help at scale and are not required.

---

## 3. Module 1: Keyword Research and Search Intent

### Start From What You Already Rank For

The Performance report is the best keyword tool you own, because every row is a
query that really produced impressions. Read it in four passes:

```
Position 5 to 20, decent impressions  ──> striking distance: small gains, fast
High impressions, low click rate      ──> a title and description problem, not a ranking one
Query with no page of its own         ──> a content gap you can fill deliberately
Several of your pages, one query      ──> cannibalization, fix before writing more
```

* **Striking distance** holds the cheapest wins. A page at position 8 needs depth and internal links, not a new article.
* **Impressions without clicks** mean you are visible and unconvincing, which is a title and description job, and it pays off in days not months.
* **A query with no page** is the case for writing something new, with the demand already proven.
* **Queries you do not recognize** show the language real people use, which is rarely your language.

With no history yet, the inputs are the pages ranking now, the questions
customers ask you, and the People Also Ask box.

---

### The Business Potential Framework

Grade candidate topics 0 to 3, so you do not rank for traffic that never
converts:

* **3, essential:** your product is indispensable to the solution.
* **2, helpful:** it helps significantly, but alternatives exist.
* **1, marginal:** it can only be mentioned in passing.
* **0, irrelevant:** you cannot mention it without sounding spammy.

---

### Reading the Results Page

Search the query and read what Google already rewards. The results page is the
brief, and a page in the wrong shape will not rank however good it is. Four
questions:

1. **What kind of page ranks?** Blog posts, product pages, categories, tools, videos, forums. If the results are tools, an article will not displace them.
2. **What shape is the writing?** Steps, a ranked list, a comparison, a definition, a template.
3. **How deep do they go?** Read the subheadings of the top 3-5 ranking pages. Their shared subtopics are your minimum, and what none covers is your opening.
4. **What angle do they take?** Beginner or expert, free or premium, fastest or most thorough, updated this year.

Note the features around the results too: a snippet, a PAA box, a local pack or
an AI answer each change what first position is worth, and PAA is free question
research.

---

### Can You Realistically Rank

Vendors sell a difficulty score built from backlink counts that cannot see your
site. Judge it directly:

* **Who holds page one?** National publishers are a different proposition from thin affiliate posts.
* **How good is it really?** Read it. Outdated facts, missing subtopics, no first-hand experience and padding are openings.
* **How old is it?** An unmaintained top result on a moving topic is beatable.
* **What do you have that they lack?** Own data, photographs, practitioner experience, a tool, a clearer explanation. Without one, nothing will change.
* **What does Search Console say?** Already on page two means you are closer than any score suggests.

A query you cannot win this year is one to build towards with supporting pages,
not to spend your best writing on today.

---

### Keyword Mapping and Cannibalization

**Map one primary keyword to one URL**, across the whole site, in one document.
Without it, two pages chase the same query, Google picks one (often not yours),
and the click signals and links split between them.

Find it by filtering Search Console's Performance report to a query and seeing
which of your URLs take impressions, or with `site:yourdomain.com "phrase"`.
Fix it, in order of preference:

1. **Consolidate.** Merge the weaker page into the stronger and 301 the old URL.
2. **Differentiate.** Rewrite each around a genuinely different intent, titles and headings included.
3. **Canonicalize.** When both must exist, point the secondary's canonical at the primary.
4. **Re-link.** Make internal anchors for that phrase point at the page you want to win.

---

### Topic Clusters and Topical Authority

Engines judge whether a site covers a subject, not whether a page mentions it.

```
                       [ Pillar page: broad topic ]
                        /          |           \
                       v           v            v
            [ Cluster page ]  [ Cluster page ]  [ Cluster page ]
              narrow query      narrow query      narrow query
                       \___________|____________/
                     every cluster links up to the pillar,
                     the pillar links down to every cluster
```

The **pillar** targets the head term and links to each detail page. **Clusters**
each take one long-tail query in depth and link back with descriptive anchors.
Coverage beats volume: answering every reasonable question in a subject,
including low-volume ones, is what lets the pillar compete.

---

## 4. Module 2: On-Page SEO & Content Optimization

### Satisfying Search Intent and Topical Depth

* **Competitor gap analysis:** study the H2s and H3s of the top 3-5 ranking pages for core topics, questions and entities.
* **Answer real questions** from PAA and from customer conversations.
* **No keyword stuffing.** Write for readers, and cover entities, synonyms and context rather than repeating a phrase.

---

### E-E-A-T: Experience, Expertise, Authoritativeness, Trust

E-E-A-T comes from Google's Search Quality Rater Guidelines. It is not a score
in the algorithm, and there is no number to raise. It describes what the ranking
systems are built to reward, which makes it the best checklist for judging your
own content.

* **Experience:** has the author done the thing? First-hand detail, original photographs, real numbers and what went wrong cannot be faked by a summary of other pages.
* **Expertise:** depth, correct terminology, accurate edge cases.
* **Authoritativeness:** recognition by others in the field, through citations, mentions and links.
* **Trust:** the anchor for the rest. Accurate information, transparent ownership, working contact details, honest pricing.

**YMYL** pages, covering health, finance, safety, legal or civic matters, are
held higher, because being wrong on them harms people.

What actually moves it: a real named author with credentials on the page,
sources linked for checkable claims, an honest last-updated date, contact
details and clear ownership, original material (your data, photographs, tests),
and fixing the pages that are wrong rather than burying them.

This is the hardest part to automate and where a generated draft is weakest. A
model can structure a topic correctly. It cannot supply first-hand experience.

---

### Helpful Content and AI-Generated Content

Google's stated position is that it rewards helpful, reliable, people-first
content, and does not care how it was produced. Automation is not the problem.
Using automation to produce content **primarily to manipulate rankings** is.
**[verify]** The wording and system names here change more often than the
substance.

Ask honestly before publishing: does it give original information or analysis?
Is it complete? Does it go beyond the obvious? If it draws on other sources,
does it add value rather than copying? Would the reader be satisfied, or go back
to search for something better?

**When a model drafts your pages**, this pipeline's own position:

* Every business specific comes from a source you control and keeps its qualifier. "Most orders ship in three days" is not "orders ship in three days".
* No invented statistics, dates, prices or citations.
* A person adds the experience layer.
* Publish fewer pages, better. Scaled thin pages are exactly what the spam policies target.
* Review before publishing, because the draft is a draft.

---

### Strategic HTML Tag Optimization

```
<html>
  <head>
    <title>Primary Keyword - Engaging Hook | Brand</title>
    <meta name="description" content="Concise summary incorporating target keywords and a compelling call-to-action within 150-160 characters.">
  </head>
  <body>
    <h1>H1: Core Title / Main Keyword Topic</h1>
    <h2>H2: Primary Section Header</h2>
    <h3>H3: Supporting Subtopic / Sub-header</h3>
  </body>
</html>
```

1. **Title tag:** primary keyword near the front, **50 and 60 characters** to avoid truncation, and a reason to click (a bracket, a year, a value proposition).
2. **URL slug:** short, lowercase, hyphenated, keyword included, stop words removed (`domain.com/seo-guide`).
3. **Headings:** exactly **one H1** matching or supporting the title, H2s for major sections carrying secondary keywords naturally, H3s nested beneath them.
4. **Meta description:** an ad-like summary of **150 and 160 characters**, with the keyword (Google bolds matches) and a clear call to action.
5. **Images:** descriptive filenames (`keyword-research-matrix.png`, not `IMG_0042.png`), informative alt text, and modern compressed formats.

**On rewrites.** Google often replaces your title or description with text it
thinks fits the query better. That is not a failure and not a reason to stuff
the tag. Treat it as a signal that page and query are less aligned than you
assumed.

---

### Structured Data (Schema Markup)

Machine-readable markup, normally JSON-LD, telling an engine what the content
**is** rather than leaving it to inference. It does not raise rankings. It makes
a page eligible for rich results, which change how the listing looks.

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "How to Audit Internal Links",
  "author": {"@type": "Person", "name": "Jane Doe"},
  "datePublished": "2026-03-04",
  "dateModified": "2026-09-01"
}
</script>
```

| Type | Use it on | Typical rich result |
| :--- | :--- | :--- |
| `Article` / `BlogPosting` | Editorial pages | Headline, date, author in some surfaces |
| `Product` with `Offer` | Product pages | Price, availability, review stars |
| `LocalBusiness` | Contact and location pages | Hours, address, phone in local results |
| `Organization` | Home page | Knowledge panel and entity reconciliation |
| `BreadcrumbList` | Any nested page | Breadcrumb path instead of the raw URL |
| `FAQPage` | Real question and answer pairs | **[verify]** Eligibility narrowed sharply in 2023, so treat the rich result as unlikely and the markup as clarity for machines |
| `HowTo` | Step-by-step instructions | **[verify]** Deprecated as a rich result, same caveat |
| `VideoObject` | Pages with embedded video | Thumbnail and key moments |

Mark up only what a human can see on the page, since describing absent content
is a spam violation. Keep it accurate as the page changes, because stale prices
and hours are worse than none. Validate with the Rich Results Test and the
Schema Markup Validator, then watch the Search Console enhancement reports.

---

### Formatting for Featured Snippets and Answer Surfaces

You cannot force a snippet, but the pages that win them share a shape. Ask the
question as a heading, phrased the way people search it. Answer immediately
below in 40 to 60 words, complete and self-contained, then expand. Match format
to question: a process gets a numbered list, a comparison a small table, a
definition a paragraph. Keep one idea per block. The same shape is what makes a
page quotable inside AI-generated answers. **[verify]**

---

### Internal Linking Architecture

```
                      [ Hub Page / Core Pillar ]
                              /   |   \
                             /    |    \
                            v     v     v
                     [Sub-1] <--> [Sub-2] <--> [Sub-3]
                     (Spoke)      (Spoke)      (Spoke)
```

Internal links do three jobs: they define the relationship between hubs and
supporting pages, they pass authority from your link-rich pages to deep ones,
and their anchor text tells engines what the destination is about.

Auditing them:

* **Click depth.** Pages that matter should sit within three clicks of the home page.
* **Orphans.** A page with no internal links looks unimportant and may never be found.
* **Anchor variety.** Vary wording naturally. Identical exact-match anchors site-wide read as automated.
* **Link from strength to need.** Your pages with the most external links have authority to pass. Spend it deliberately.

---

### User Experience (UX) & Content Design

Short paragraphs of two or three sentences, bulleted lists, callouts and real
diagrams. Legible type (16px and up) with generous line height. No screen-
blocking popups, intrusive interstitials or layout shifts.

---

### Content Maintenance: Refresh, Consolidate, Prune

Published content decays as facts age and competitors publish better pages.

* **Refresh** a page still serving its query but falling behind: update facts and dates, cover subtopics the current top results added, replace dead links, and change the last-updated date only when something really changed.
* **Consolidate** several pages competing for one intent into the best one, redirecting the rest.
* **Prune** pages serving nobody. Remove and return 410, or redirect where a genuinely relevant target exists. Redirecting everything to the home page reads as a soft 404.
* **Work the decay list quarterly.** In Search Console, compare the last 3 months against the previous year and sort by lost clicks. That list usually beats writing a new article.

---

## 5. Module 3: Link Building & Off-Page SEO Strategies

Backlinks remain a top ranking signal, acting as votes of confidence.

### Key Backlink Quality Evaluation Factors

```
                  [ Backlink Quality Triangle ]
                             /\
                            /  \
                           /    \
                          /------\
                         /Relevance\
                        /-----------\
                       /   Domain    \
                      /   Authority   \
                     /-----------------\
                    / Placement & Context \
                   /-----------------------\
```

1. **Topical relevance:** a link from a related site is worth far more than one from an unrelated one.
2. **Domain and page authority:** sites with legitimate link profiles pass more.
3. **Editorial placement:** contextual links in body text beat footer, sidebar and author-bio links.
4. **Anchor variety:** a natural profile mixes brand anchors (*"Northside Studio"*), exact-match keywords (*"SEO course"*), partial matches and naked URLs (*"northside.example"*). Excessive exact-match manipulation triggers penalties.
5. **Link attributes:** ordinary links pass PageRank. `rel="nofollow"`, `rel="sponsored"` and `rel="ugc"` tell engines not to, though they still drive referral traffic.

### High-Impact Tactics

* **Guest posting:** pitch authoritative publications with topics that fill a gap on their site, and link to a genuinely useful resource rather than a sales page.
* **Skyscraper:** find content with many backlinks, publish something clearly better, and tell everyone linking to the original.
* **Broken link building:** find 404s on resource pages, and offer your equivalent as the replacement.
* **Resource pages:** find curated lists with `keyword + inurl:resources`, and submit your definitive guide or free tool.
* **Unlinked mentions and digital PR:** monitor mentions of your brand, and ask for a link where one is missing.

### What Not to Do

Do not buy links, exchange them at scale, or rent placements on a private blog
network. Do not chase volume: a hundred directory links move nothing, and one
relevant editorial link can. Ignore vendor "toxicity" scores, which are not
Google metrics. **Disavow rarely**, only with a manual action or known bought
links, since Google ignores most junk automatically and a careless disavow
removes links that were helping.

---

## 6. Module 4: Technical SEO, Auditing, and Site Maintenance

### Technical Infrastructure & Indexability

```
[ Web Crawler ] ──> Check Robots.txt ──> Read XML Sitemap ──> Crawl HTML ──> Evaluate Canonical Tag ──> Index Page
```

1. **`robots.txt`** tells crawlers which paths they may fetch, which keeps crawl budget off internal search, staging and admin areas.
2. **XML sitemaps** list the canonical URLs you want indexed, submitted in Search Console and referenced from `robots.txt`.
3. **Canonical tags** declare the primary URL among duplicates, for example pointing `page.html?utm_source=fb` at `page.html`.

---

### Blocking Crawling Is Not Blocking Indexing

The most expensive mistake in technical SEO, so it gets its own section.

* **`robots.txt` disallow** stops a fetch, not an indexing. A disallowed URL can still appear in results, without a description, if other pages link to it.
* **`noindex`** keeps a URL out of the index, but only if the crawler is **allowed to fetch the page and see it**.
* **The trap:** disallowing *and* adding `noindex` means the `noindex` is never read. To remove a page, allow crawling and serve `noindex`, then block later once it has dropped out.

| Goal | Use |
| :--- | :--- |
| Keep a page out of results | `noindex`, crawlable |
| Save crawl budget on worthless URLs | `robots.txt` disallow |
| Consolidate duplicates | `rel="canonical"` |
| Remove permanently | 410 Gone, or 404 |
| Move permanently | 301 redirect |

---

### Status Codes and Redirects

| Code | Meaning | SEO effect |
| :--- | :--- | :--- |
| 200 | OK | Indexable as normal |
| 301 | Moved permanently | Consolidates signals to the target, the default for a move |
| 302 / 307 | Moved temporarily | Signals stay with the original URL |
| 404 | Not found | Drops from the index over time |
| 410 | Gone | Same, processed faster, for deliberate removal |
| 5xx | Server error | Crawling slows if it persists, and pages can drop out |

Point an old URL at the closest equivalent, never at the home page by default.
Keep chains to one hop, and update internal links to the final destination
rather than relying on the redirect forever. A redirect to an irrelevant page is
treated as a **soft 404**.

---

### Rendering, JavaScript and Mobile

Googlebot crawls the HTML first and renders JavaScript in a later pass, so
content that only exists after client-side rendering is indexed late or not at
all. Server-side rendering or static generation of the critical content is the
safe route. Test what the crawler sees with URL Inspection's rendered HTML, not
what your browser shows. Links must be real `<a href>` elements: a `<div>` with
a click handler passes nothing. **Mobile-first indexing** means the mobile
rendering is the indexed one, so content, headings, structured data and links
that exist only on desktop effectively do not exist. **[verify]**

---

### Crawl Budget, Pagination and Faceted Navigation

Crawl budget matters on large sites and is mostly irrelevant below tens of
thousands of URLs. Where it matters, it is wasted by **faceted navigation**
generating near-infinite filter combinations, by session and tracking
parameters duplicating every page, and by infinite calendars, internal search
results and print duplicates. Decide which facets are indexable and
canonicalize or disallow the rest.

**Pagination:** `rel="next"` and `rel="prev"` are no longer used by Google. Give
each page a self-referential canonical, make every item reachable, and link the
sequence with real links. A fast "view all" page is often the better answer.

---

### International and Multi-Language Sites

`hreflang` tells engines which version serves which audience. Every version must
reference every other version including itself, codes are language then optional
region (`en`, `en-ca`, `fr-ca`), and `x-default` catches the rest. Translated
pages are not duplicate content, but poor machine translation is treated as thin.

---

### Page Speed & Web Vitals Optimization

* **Core Web Vitals:** **LCP** for load speed, **INP** for responsiveness, **CLS** for visual stability.
* **Images:** WebP or AVIF, responsive `srcset`, lazy-loading below the fold.
* **Caching and CDNs:** browser caching policies, and a CDN to serve assets closer to users.
* **Minify and defer:** shrink CSS, JS and HTML, and defer non-essential scripts so content renders first.

**Field data beats lab data.** PageSpeed Insights shows a simulated score and
real-user field data from the Chrome UX Report. The field data is what the Core
Web Vitals assessment uses, so a perfect lab score with failing field data means
your users are on slower devices than your test.

---

### Common Technical SEO Errors

```
+--------------------------+-----------------------------------------------------------+
| Issue Type               | Description & Remediation Strategy                        |
+--------------------------+-----------------------------------------------------------+
| Broken Links (404s)      | Links pointing to missing pages; repair internal links    |
|                          | or set 301 redirects to relevant live URLs.               |
+--------------------------+-----------------------------------------------------------+
| Redirect Chains (301s)   | Multi-hop redirects (A -> B -> C); update links to point  |
|                          | directly to final destination C.                          |
+--------------------------+-----------------------------------------------------------+
| Orphan Pages             | Live indexable pages lacking internal incoming links;     |
|                          | integrate into navigation or hub-and-spoke structures.    |
+--------------------------+-----------------------------------------------------------+
| Duplicate Content        | Identical content accessible across multiple URLs; set    |
|                          | proper rel="canonical" tags or 301 redirects.             |
+--------------------------+-----------------------------------------------------------+
| Non-HTTPS Warnings       | Insecure HTTP pages; enforce site-wide SSL certificates   |
|                          | with strict HTTP-to-HTTPS 301 redirect rules.             |
+--------------------------+-----------------------------------------------------------+
```

---

## 7. Module 5: Local SEO

Local SEO serves queries with geographic intent, stated ("plumber in Hamilton")
or implied ("plumber near me"), and it runs on different signals from classic
organic ranking.

### The Local Pack

It takes most of the clicks for these queries, and three factors drive it:
**relevance** (the right primary category and accurate services), **distance**
(not negotiable), and **prominence** (reviews, links, citations and offline
reputation).

### Google Business Profile

The highest-leverage asset in local SEO. Choose the most specific primary
category, complete every field including holiday hours and real photographs,
keep the service area honest, and answer the Q&A before someone else does. Treat
**reviews** as both a ranking factor and the thing that converts: ask routinely,
reply to all, never buy them.

### NAP Consistency and Citations

**NAP** is Name, Address, Phone, formatted identically everywhere, which lets
engines reconcile mentions into one business. Mismatched suites, abbreviations
and old numbers split that entity. Audit the major and industry-specific
directories.

### On-Site Local Signals

A page per location with genuinely different content, an embedded map, a local
number and `LocalBusiness` markup. NAP in crawlable text, not an image. Location
pages linked from navigation. And no near-identical page per city where you have
no presence, which is a doorway pattern.

---

## 8. Module 6: Measuring and Iterating

### The KPIs That Matter

| KPI | Source | What it tells you |
| :--- | :--- | :--- |
| **Organic sessions** | Analytics | Total demand captured |
| **Impressions and average position** | Search Console | Visibility, ahead of clicks |
| **Click-through rate by query** | Search Console | Whether your title earns the click you already rank for |
| **Ranking keyword count** | Search Console | Breadth, the leading indicator of topical authority |
| **Conversions from organic** | Analytics | The only metric the business cares about |
| **Referring domains** | Backlink tool | Off-page growth |
| **Indexed against submitted** | Search Console | Whether pages are even eligible |
| **Core Web Vitals pass rate** | Search Console | Experience floor |

Impressions and keyword counts move first, so they are the early signal.
Conversions move last and justify the work. Page views with no conversion
defined are vanity.

### The Search Console Reports to Live In

* **Performance:** queries, pages, countries, devices. Compare periods, and filter by page to see what an article really ranks for.
* **Page indexing:** which URLs are indexed and why the rest are not. "Discovered, currently not indexed" usually means quality or crawl priority, not a bug.
* **URL Inspection:** last fetch, rendering, and the canonical Google chose, which is where it tells you it disagreed with yours.
* **Enhancements and Core Web Vitals:** structured data errors and field performance at scale.

### SEO as an Experiment

1. **State the hypothesis** first: "a direct 50-word answer under each question heading will raise CTR on these 12 pages."
2. **Change one variable.** Rewriting titles and restructuring at once teaches you nothing about either.
3. **Keep a control group** of comparable pages, so a core update or seasonality does not read as your win.
4. **Give it weeks, not days.** Days of data are noise.
5. **Record it,** win or lose, with dates. That log is what explains a traffic shift six months later.
6. **Roll out or roll back,** then take the next variable.

### Reading a Traffic Drop

Work the gates in order, because the fix differs at each:

1. **Tracking?** Check for a broken tag or a consent banner change first.
2. **Indexing?** Page indexing report, then URL Inspection on affected pages.
3. **Ranking?** Compare positions period over period. Positions held but clicks fell means the results page changed around you.
4. **Demand?** Seasonality looks exactly like a penalty in a traffic chart. Check whether impressions fell with position steady.
5. **Site-wide or one section?** Site-wide on a core-update date is a quality signal. A section drop is usually technical.
6. **Manual actions** appear in Search Console under Security and Manual Actions, the only place a penalty is stated outright.

---

## 9. SEO Execution Checklist & Operational Workflow

### Phase 0: Measurement Baseline
- [ ] Install analytics and verify a session, a page view and a conversion event all record.
- [ ] Define what counts as a conversion, and record it as an event.
- [ ] Verify the site in **Google Search Console** and **Bing Webmaster Tools**.
- [ ] Run and archive a baseline crawl of your own site.
- [ ] Record starting positions for the keywords you intend to move.

### Phase 1: Technical Hygiene
- [ ] Export the Search Console Performance report, the keyword input for everything below.
- [ ] Create and submit a clean XML sitemap, and keep its URL list as your page inventory.
- [ ] Verify `robots.txt` is not blocking critical assets.
- [ ] Enforce HTTPS site-wide.
- [ ] Resolve 404s, redirect chains and orphan pages from the crawl.
- [ ] Confirm no page carries both a `robots.txt` disallow and a `noindex`.
- [ ] Confirm the mobile rendering carries the same content, links and structured data as desktop.

### Phase 2: Keyword Strategy & Content
- [ ] List audience pain points and core topics.
- [ ] Read the Search Console export in four passes: striking distance, impressions without clicks, queries with no page, cannibalization.
- [ ] Evaluate **Business Potential (0-3)** for each candidate.
- [ ] Read the live results page: page type, shape, depth, angle.
- [ ] Classify the intent type and confirm your page type matches.
- [ ] Map one primary keyword to one URL, checking for cannibalization.
- [ ] Outline against the subtopics and questions the ranking pages cover.
- [ ] Draft long-form, scannable content that covers the topic completely.
- [ ] Add the experience layer a model cannot: first-hand detail, original data, a named author.

### Phase 3: On-Page
- [ ] Place the primary keyword naturally in the title, H1, slug and meta description.
- [ ] Structure with hierarchical H2s and H3s.
- [ ] Compress images and write descriptive alt text.
- [ ] Add 3-5 internal links with descriptive anchor text.
- [ ] Add a direct 40 to 60 word answer beneath each question heading.
- [ ] Add and validate structured data for the page type.
- [ ] Verify every factual claim, and remove any statistic without a traceable source.

### Phase 4: Off-Page & Promotion
- [ ] Identify the most-linked resources in your niche.
- [ ] Run broken-link outreach, guest posts or skyscraper campaigns.
- [ ] Audit unlinked brand mentions and request links.
- [ ] Promote new content through your own channels for initial engagement.
- [ ] For local businesses, complete the Google Business Profile and fix NAP inconsistencies.

### Phase 5: Monitoring & Iteration
- [ ] Review Search Console monthly: clicks, impressions, average position.
- [ ] Refresh older content to keep it accurate and competitive.
- [ ] Keep automated crawls running to catch regressions.
- [ ] Work the content decay list quarterly, refreshing, consolidating or pruning.
- [ ] Keep a dated log of significant changes.
- [ ] Change one variable at a time against a control group, and record the result either way.

---

## 10. Appendix: Glossary of Terms

**Algorithm update** A change to how results are ranked. Core updates are broad and periodic, and recovery comes from improving the site rather than undoing one thing.

**Anchor text** The visible, clickable words of a link, telling engines what the destination is about.

**Backlink** A link from another site to yours.

**Black hat** Tactics that violate guidelines to manipulate rankings, risking suppression or de-indexing.

**Canonical tag** `rel="canonical"`, naming the preferred URL among duplicates.

**Cannibalization** Two or more of your pages competing for one query, splitting their signals.

**Citation** A mention of a business's name, address and phone on another site, with or without a link. Central to local SEO.

**Click depth** The number of clicks from the home page to a given page.

**Cloaking** Showing engines different content from human visitors. A guideline violation.

**Crawl budget** How many URLs an engine will fetch from a site in a period. Relevant mainly to very large sites.

**Crawling** Discovery, where bots follow links to find pages.

**De-indexed** Removed from the index entirely, so the page or site cannot appear at all.

**DoFollow** An ordinary link that passes authority. Not a real attribute, just the absence of `nofollow`.

**Domain Authority / Domain Rating** Third-party scores estimating a domain's strength. Vendor models, not Google metrics, and not used by this pipeline.

**E-E-A-T** Experience, Expertise, Authoritativeness, Trust. The quality framework from Google's rater guidelines.

**Featured snippet** An answer extracted onto the results page above the organic listings.

**Hreflang** Annotations declaring which language and region version serves which audience.

**Index** The database of pages an engine has stored and can return.

**Indexing** Storing and organizing a crawled page so it can be returned for queries.

**Intent** The goal behind a query, as distinct from its wording.

**JSON-LD** The JavaScript-based format Google prefers for structured data.

**KPI** Key Performance Indicator, a metric chosen in advance to judge success.

**Keyword Difficulty (KD)** A third-party estimate of ranking difficulty, based mostly on competitors' backlinks. You will meet the term elsewhere. This guide judges the question by reading the results page instead.

**Local pack** The three-result map block shown for local queries.

**Long-tail keyword** A longer, more specific, lower-volume query. Usually easier to rank for and higher converting.

**NAP** Name, Address, Phone. Consistency across the web is a core local signal.

**NoFollow** `rel="nofollow"`, a hint not to pass authority. `sponsored` and `ugc` are the paid and user-generated variants.

**Noindex** A directive keeping a page out of the index. The page must stay crawlable for it to be seen.

**Orphan page** A page with no internal links pointing to it.

**PageRank** Google's original link-based authority algorithm, still the concept behind how link equity flows.

**People Also Ask (PAA)** The expandable related-question block on a results page.

**Pillar and cluster** A broad overview page supported by, and interlinked with, narrower pages on the same subject.

**Query** The exact words typed into the search bar, as opposed to the intent behind them.

**Rich result** A listing enhanced by structured data, such as review stars or breadcrumbs.

**Schema markup** Structured data vocabulary from schema.org that labels what content means.

**SERP** Search Engine Results Page.

**SERP features** Non-standard results sharing the page with organic listings: snippets, PAA, local packs, image packs, video carousels, knowledge panels, AI answers.

**Sitemap** An XML file listing the URLs you are asking engines to index. Also your cheapest inventory of your own pages.

**Soft 404** A page returning success while showing "not found" content, or a redirect to an irrelevant page. Treated as an error.

**Structured data** Machine-readable markup describing a page's content. See schema markup.

**Topical authority** A site's perceived depth across a subject, as opposed to the strength of one page.

**Traffic Potential (TP)** A third-party estimate of the total traffic the top-ranking page earns across every keyword it ranks for. Modelled, not measured, so this guide uses Search Console impressions instead.

**White hat** Tactics that comply with guidelines and prioritize the user.

**YMYL** "Your Money or Your Life", topics where inaccuracy causes real harm, held to a higher bar.

**Zero-click search** A search resolved on the results page, with no click through to any site.
