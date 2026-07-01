# Figma Design QA — Skill & Script Documentation

## What the Skill Does

The `figma-design-qa` skill performs automated **design quality assurance** — it compares a live website against its Figma design, section by section, and generates a full bug report scored as **pass / warning / severe**. It requires a Figma MCP connector, a live site URL, and a Figma page/frame URL.

The skill covers:
- Visual diffing: colors, fonts, font sizes, content/copy, container sizing
- Site-wide checks: page title, favicon, images, links, hover states, heading hierarchy
- Cross-browser responsive testing across 18 fixed breakpoints (desktop, iPad, mobile)
- PDF/HTML/CSV report generation (never just a chat summary)

---

## File Inventory

```
figma-design-qa/
  SKILL.md                         # Main workflow instructions
  DOCUMENTATION.md                 # This file
  references/
    checklist.md                   # QA parameter rules & severity thresholds
    breakpoints.md                 # Required responsive test viewport sizes
  scripts/
    qa-collect.sh                  # Live site data collector (agent-browser)
    qa-generate-report.js          # HTML + CSV + PDF report generator
```

---

## `SKILL.md` — Purpose

The main instruction file for the skill. It defines a 6-step workflow:

| Step | What Happens |
|------|-------------|
| **Step 0** | Preconditions — verify Figma MCP is connected, both URLs are supplied, `agent-browser` is installed |
| **Step 1** | Pull Figma design data via Figma MCP (node tree, dimensions, text, fonts, colors, spacing, images). Break the frame into logical sections top-to-bottom. Optionally create `sections-config.json` to override auto-detected section selectors. |
| **Step 2** | Run the `qa-collect.sh` script to gather all live site data (headings, images, links, sections, overflows, heading hierarchy, favicon, link transitions) and take responsive screenshots. |
| **Step 3** | Section-by-section manual comparison using the `references/checklist.md` rules against Figma data and screenshots. |
| **Step 4** | Review responsive results from the collected breakpoint data and screenshots (overflow, hidden sections, hamburger nav). |
| **Step 5** | Run `qa-generate-report.js` to produce `report.html`, `report.csv`, and optionally `report.pdf`. |

It also defines the output directory structure:
- `./figma-design-qa-reports/<YYYY-MM-DD_HH-MM>_<slug>/` — one folder per QA run
- Inside: `data/`, `screenshots/`, `report.html`, `report.csv`, `report.pdf`

---

## `scripts/qa-collect.sh` — Detailed Breakdown

This is a **bash script** that uses `agent-browser` (a headless browser CLI) to open the live site and collect all QA-relevant data. It requires the `agent-browser` npm package.

### Usage
```bash
bash qa-collect.sh "https://example.com" [output-directory]
```

### What It Does — Step by Step

#### 1. Setup & Session Management (lines 1-36)
- Derives a site slug from the URL hostname
- Creates a timestamped run folder and `screenshots/` + `data/` subdirectories
- Checks that `agent-browser` is installed; exits with help message if not
- Defines a helper `_eval_to_file()` that pipes JavaScript via stdin to `agent-browser eval` and writes output to file
- Creates a unique session name using `qa-collect-<unix-timestamp>`

#### 2. Page Open & Lazy Content Trigger (lines 39-63)
- Cleans any hung sessions (`agent-browser close --all`)
- Opens the site at **1920x1080** viewport
- Waits for `networkidle` (all network requests complete)
- Runs a **scroll-to-bottom** script that scrolls incrementally by `window.innerHeight` steps through the full `document.body.scrollHeight` to trigger lazy-loaded images, entrance animations, and dynamic content
- Waits 2s for animations to settle after scrolling

#### 3. Site-wide Data Collection (lines 65-230)
Injects a large JavaScript payload via `agent-browser eval --stdin` that collects:

| Data Collected | Description | Fields Per Entry |
|---|---|---|
| **page title** | `document.title` | — |
| **page URL** | `window.location.href` | — |
| **headings** | All `h1`–`h6` elements | `tag`, `text`, `fontSize` (computed), `color` (computed), `selector` (CSS), `xpath` |
| **images** | All `document.images` | `src`, `naturalWidth`, `naturalHeight`, `alt`, `visible` (boolean), `selector`, `xpath` |
| **links** | All `<a>` elements | `href`, `text`, `isEmpty` (no href), `isPlaceholder` (`href="#"`), `selector`, `xpath` |
| **favicon** | `link[rel~="icon"]` href | — |
| **heading inversion** | Checks `h1 > h2 > h3 > h4 > h5 > h6` font-size ordering | `tag`, `size`, `previousSize` (first violation found) |
| **broken images** | Images with `naturalWidth === 0 && naturalHeight === 0` | Filtered from images array |
| **link transition** | `transitionDuration` of first valid `<a>` | CSS value or `null` |
| **overflows** | Elements wider than `window.innerWidth` (excludes fixed/absolute/hidden-overflow) | `tag`, `class`, `width`, `innerWidth`, `selector`, `xpath`; capped at 50 |
| **sections** | Elements matching `section`, `[class*="section"]`, `[class*="hero"]`, `[class*="header"]`, `[class*="footer"]`, `[class*="testimonial"]`, `[class*="feature"]` — with height > 50px | `index`, `tag`, `class`, `top`, `height`, `width`, `textPreview`, `selector`, `xpath`, `label` |

**Key internal functions:**
- **`getSelector(el)`** — Builds a copy-pasteable CSS selector by walking up the DOM tree, using IDs when found, otherwise `tag.class` with `:nth-of-type()` for disambiguation. Stops at `<body>`.
- **`getXPath(el)`** — Builds an XPath expression by walking up and counting preceding siblings of the same tag.
- **`getSectionLabel(el)`** — Derives a human-readable section name from: first heading text → `aria-label` / `data-label` / `title` attribute → first 5 words of inner text → first class name.

Output is saved as `site-wide-raw.txt`. If the first character is `[` or `{` (valid JSON), it's copied to `site-wide.json`.

#### 4. Responsive Breakpoint Testing (lines 233-427)
Tests **18 fixed breakpoints** hardcoded in the script:

| Category | Resolutions |
|---|---|
| **Desktop** (11) | 1280x720, 1366x768, 1400x900, 1440x900, 1536x864, 1600x900, 1680x1050, 1792x1120, 1920x1080, 2048x1536, 2560x1440 |
| **iPad** (3) | 768x1024, 810x1180, 1024x1366 |
| **Mobile** (4) | 360x740, 412x915, 430x932, 375x740 |

For each breakpoint, the script:
1. Sets the viewport to that resolution
2. Waits 1.5s for responsive CSS to apply
3. Scrolls to bottom to trigger lazy content at this width
4. Waits another 1.5s
5. Takes a **full-page screenshot** → `screenshots/<WxH>.png`
6. Collects breakpoint-specific data:

| Data | Description |
|---|---|
| **viewport** | Target `width`, `height`, `category`, actual `innerWidth`, `innerHeight` |
| **overflows** | Elements wider than viewport + 2px with **section attribution** — each entry includes `sectionLabel` (parent section name found by walking up to nearest section container via `findParentSection()`) |
| **hiddenSections** | Elements matching section selectors that have `height === 0` (collapsed) — includes `label`, `elementSelector`, `xpath` |
| **hamburgerDetected** | (mobile only) Scans for hamburger buttons using 7 selectors: `button[class*="hamburger"]`, `button[class*="menu"]`, `[class*="hamburger"]`, `[class*="navbar-toggler"]`, `[aria-label*="menu"]`, `button:has(.bar)`, `[class*="toggle"]` |
| **hamburgerLinks** | (mobile only) If hamburger found, clicks it, waits 500ms, collects `innerText` of nav links from `nav a`, `[class*="menu"] a`, `[class*="nav"] a`, `.mobile-menu a` |

Overflows are deduplicated (by tag + class) and capped at 30. Output saved as `bp-<WxH>.json`.

#### 5. Cleanup (lines 429-438)
- Closes the browser session and all sessions
- Prints completion message with paths to data and screenshots

---

## `scripts/qa-generate-report.js` — Detailed Breakdown

This is a **Node.js script** (zero dependencies) that reads the collected JSON data and produces **`report.html`** and **`report.csv`**. Optionally attempts PDF conversion.

### Usage
```bash
node qa-generate-report.js <collection-directory>
```

### What It Does — Step by Step

#### 1. Data Loading (lines 1-27)
- Reads input directory from `process.argv[2]`
- Loads `data/site-wide.json` (site-wide collected data)
- Loads all `data/bp-*.json` files (breakpoint data), sorted alphabetically
- Loads optional `data/sections-config.json` (manual section override)
- Uses `loadJSON()` helper that returns `null` on parse failure

#### 2. Section Resolution (lines 29-42)
- If `sections-config.json` exists, uses its sections as the canonical list, enriching each with position/dimension data from the matching auto-detected section (matched by selector, then by label substring, then by index)
- Otherwise, falls back to auto-detected sections from `site-wide.json`
- Each section gets: `index`, `label`, `tag`, `class`, `top`, `height`, `width`, `selector`, `xpath`

#### 3. Row Building & Verdict Counting (lines 44-71)
- `h(str)` — HTML-escapes a string for safe rendering
- `csv(str)` — CSV-escapes a string (double-quotes inner quotes)
- `verdictClass(v)` — Maps verdict to CSS class (`verdict-pass`, `verdict-warning`, `verdict-severe`)
- `verdictIcon(v)` — Maps verdict to HTML entity (checkmark, warning sign, cross)
- `makeRow(section, param, expected, found, verdict, note, selector)` — Creates a row object and auto-increments the verdict counter
- Three data structures hold rows: `siteWideRows[]`, `sectionRows{label: []}`, `responsiveRows{key: []}`

#### 4. Site-wide Checks (lines 81-144)

| Check | Logic | Fallback |
|---|---|---|
| **Page title** | Reads `siteWide.title`, marks as pass with note to "Check against Figma" | `(not found)` |
| **Favicon** | Checks if `siteWide.favicon` is non-empty → pass; empty → severe | Shows URL or "Missing" |
| **Broken images** | Iterates `siteWide.brokenImages[]`, each is severe with `0x0 natural dimensions` note and `selector` | If none, one pass row with image count |
| **H1 count** | Exactly 1 → pass with text preview + selector; else severe listing all H1 texts | |
| **Heading hierarchy** | If `headingInversion` exists → severe with tag/size/previousSize + selector; else pass | |
| **Empty headings** | Each heading with no text is a warning with selector | If none, one pass row |
| **Empty links** | Each `<a>` with no href is severe with text preview + selector | |
| **Placeholder links** | Each `<a>` with `href="#"` is warning with text preview + selector | |
| **All links OK** | If no empty/placeholder links, one pass row with total link count | |
| **Link transitions** | `0s` or `null` → warning "No visible transition"; otherwise pass showing the duration | |

#### 5. Per-section Metadata (lines 146-151)
- Each section gets one pass row showing its bounds (`tag`, `class`, `top`, `height`, `width`) with selector

#### 6. Responsive Checks (lines 153-211)

For each breakpoint:

| Check | Severity Logic |
|---|---|
| **Overflow** | Filters out intentional overflows (class contains `swiper`, `owl`, `carousel`, `marquee`). Remaining unintentional overflows are grouped by `sectionLabel` and each is marked **severe**. If only intentional overflows remain, one **pass** row with note "Swiper/carousel detected". If zero overflows, one **pass** row. |
| **Hidden sections** | Each section with `height === 0` is marked **severe**, attributed to its `label`, with `selector` and `elementSelector` |
| **Hamburger nav** | (mobile only) If detected → **pass** listing links found. If not detected → **warning** "No visible hamburger button found" |

#### 7. HTML Report Generation (lines 213-330)
Builds a self-contained HTML document with:

- **Summary box**: pass/warning/severe counts, total checks, sections, breakpoints
- **Jump navigation**: anchor links to every section, site-wide table, responsive tables, screenshots
- **Per-section tables**: one `<table>` per section with columns: Section, Parameter, Expected, Found, Verdict, Note, Selector
- **Site-wide checks table**: same format with Selector column
- **Responsive tables**: grouped by "Section / category" key; each row has the Selector column
- **Screenshots gallery**: all breakpoint PNGs displayed with lazy-loaded `<img>` wrapped in clickable `<a>` links
- CSS styling: system-ui font, sticky table headers, color-coded verdicts (green pass, amber warning, red severe), alternating row stripes, max-width 1400px layout, flex-wrap screenshot grid

#### 8. CSV Generation (lines 337-344)
- Header: `Section,Parameter,Expected,Found,Verdict,Note,Selector`
- One row per finding, all strings CSV-escaped
- Writes to `report.csv` — importable into Jira, Google Sheets, or Excel

#### 9. PDF Generation (lines 346-373)
Attempts PDF conversion using the first available tool on PATH, in priority order:

1. `agent-browser` — opens HTML file, then `agent-browser pdf` to export
2. `chromium` — headless `--print-to-pdf`
3. `google-chrome` — headless `--print-to-pdf`
4. `wkhtmltopdf` — direct HTML-to-PDF
5. `weasyprint` — direct HTML-to-PDF

If none found, skips PDF and tells the user to deliver `report.html` + `report.csv`.

---

## `references/checklist.md` — Severity Rules Reference

The source of truth for what constitutes pass/warning/severe. Used in Steps 3 and 4 of the workflow.

| Parameter | Pass | Warning | Severe |
|---|---|---|---|
| **Color** | Exact or imperceptible match | Different shade/tone, same hue family | Wrong color entirely (brand blue vs gray; accessibility broken) |
| **Fonts** | Exact match (typeface + weight) | — | Any mismatch in font family (highly visible miss) |
| **Font size** | Exact match | Within ±10% of Figma | Beyond ±10% |
| **Content/copy** | Exact match | — | Any deviation (intentionally strict); any placeholder/dummy text |
| **Container sizing** | Matching dimensions | — | Meaningful mismatch (not sub-pixel rounding) |
| **Page title** | Matches Figma | — | Mismatch |
| **Favicon** | Present & loads | — | Missing or 404 |
| **Images** | All render | — | Any broken image |
| **Links** | Valid href | Placeholder (`#`) | Empty or missing href |
| **Hover states** | Present & matches spec | Duration/easing mismatched | Missing entirely |
| **Heading hierarchy** | One `<h1>`, logical nesting, descending sizes | — | Wrong H1 count; level skipping; size inversion; inconsistent sizes within a level |
| **Mobile nav** | Hamburger opens with same links as desktop | — | Broken or link mismatch |
| **Responsive** | — | Visually tight (not breaking) | Content cut off/unreadable; sections invisible; layout breaks usability |

---

## `references/breakpoints.md` — Test Breakpoints Reference

Defines 18 mandatory breakpoints that `qa-collect.sh` tests:

| Category | Resolutions |
|---|---|
| **Desktop** (11) | 1280×720, 1366×768, 1400×900, 1440×900, 1536×864, 1600×900, 1680×1050, 1792×1120, 1920×1080, 2048×1536, 2560×1440 |
| **iPad** (3) | 768×1024, 810×1180, 1024×1366 |
| **Mobile** (4) | 360×740, 412×915, 430×932, 375×740 |

At each size the skill checks:
- Text/content overflow from font sizes
- All sections/content visible (nothing clipped or hidden)
- Spacing between sections looks intentional
- Mobile-only: hamburger opens and contains same links as desktop nav

---

## Data Flow Summary

```
User provides: live site URL + Figma URL
         │
         ▼
  [Figma MCP] ──► Figma design data (node tree, dimensions, colors, fonts, text)
         │
         ▼
  [qa-collect.sh] ──► data/site-wide.json       (headings, images, links, sections, overflows, favicon, etc.)
                   ──► data/bp-<WxH>.json × 18  (per-breakpoint overflows, hidden sections, hamburger)
                   ──► screenshots/<WxH>.png × 18 (full-page screenshots)
         │
         ▼
  Manual comparison (Step 3) using checklist.md + screenshots
         │
         ▼
  [qa-generate-report.js] ──► report.html  (section tables, site-wide checks, responsive, screenshots)
                          ──► report.csv   (Jira/Excel-ready)
                          ──► report.pdf   (if PDF engine available)
```
