---
name: figma-design-qa
description: Use this skill whenever the user wants to QA, test, audit, or compare a live website against its Figma design — e.g. "check if the site matches Figma", "QA this page against the design", "find design bugs", or "test responsiveness against Figma". Requires a connected Figma MCP and a live site URL plus a Figma page/frame URL. Performs section-by-section visual diffing (colors, fonts, font sizes, content/copy, container sizing, page title, favicon, images, links, hover states, heading hierarchy) and cross-browser responsive testing across a fixed set of desktop/tablet/mobile breakpoints, reporting every finding as pass, warning, or severe and producing a final section-by-section PDF report (never just a chat summary). Always use this skill for any "design QA", "pixel-perfect check", "Figma vs live site" or "responsive testing" request — do not attempt this kind of comparison without it.
---

# Figma Design QA

Compares a live website against its Figma design, section by section, and produces a bug report scored on a three-level scale: **pass / warning / severe**.

## Working directory — all paths are project-relative

Every file this skill reads or writes MUST be relative to the current working directory (the project root you are in — `cwd` / `pwd`). Never write to or read from absolute paths outside the project (no `/mnt/...`, no `~/...`, no `/tmp/...` unless the user explicitly asks).

- **Output root:** `./figma-design-qa-reports/` (created if missing), relative to cwd.
- **Per-run folder:** `./figma-design-qa-reports/<YYYY-MM-DD_HH-MM>_<slug>/` — one folder per QA run. All screenshots, intermediate notes, the HTML source, and the final PDF live here.
- **Reference files** (`references/checklist.md`, `references/breakpoints.md`) are read relative to this skill's own folder — do not change those.
- **Scripts** (`scripts/qa-collect.sh`, `scripts/qa-generate-report.js`) are used to automate collection and reporting — always use these scripts instead of DevTools MCP or manual AI evaluation for live-site data gathering and report generation.
- When you need a slug for the run folder, derive it from the live site's hostname (e.g. `example.com`).
- Before writing, run `mkdir -p ./figma-design-qa-reports/<run-folder>` so all subsequent paths resolve.

## Scripts overview

Two scripts automate the heavy lifting. **Do not** use DevTools MCP or manual `evaluate_script` calls for what these scripts handle.

### `scripts/qa-collect.sh`

Opens the live site via `agent-browser`, collects all site-wide data, tests every responsive breakpoint from `references/breakpoints.md`, takes full-page screenshots, and detects hamburger nav + overflow issues. Saves everything into the per-run data directory.

Every captured element includes a **copy-pasteable CSS selector** (`selector` field) and **XPath** (`xpath` field) so developers can immediately locate the element in DevTools. Sections include a human-readable `label` derived from their heading text or aria-label. Breakpoint overflow findings include a `sectionLabel` field attributing each overflow to its parent section.

**Usage:** `bash <skill-dir>/scripts/qa-collect.sh <site-url> [output-directory]`

- `<skill-dir>` is the absolute path to this skill's folder (resolve it at runtime with `dirname $(readlink -f $0)` or by finding `.agents/skills/figma-design-qa/` relative to cwd).
- `[output-directory]` defaults to `./figma-design-qa-reports/<timestamp>_<slug>/`.

### `scripts/qa-generate-report.js`

Reads collected data from the per-run folder and generates:

- **`report.html`** — per-section tables (one table per detected section), site-wide checks table, responsive tables with section attribution, a **Selector column** on every row for copy-paste into DevTools, summary box with pass/warning/severe counts, and jump navigation.
- **`report.csv`** — same data in CSV format (columns: Section, Parameter, Expected, Found, Verdict, Note, Selector) for Jira/Excel import.
- **`report.pdf`** (optional) — attempted via `agent-browser` or headless Chrome fallback.

Supports manual section override via `sections-config.json` (see Step 1). If not present, sections are auto-detected from `site-wide.json`.

**Usage:** `node <skill-dir>/scripts/qa-generate-report.js <collection-directory>`

## Step 0 — Preconditions (must pass before anything else)

1. Check whether a Figma MCP connector is connected and usable (try a lightweight Figma MCP call, e.g. fetching file/page metadata for the given Figma URL).
   - If no Figma MCP tool is available at all → **stop** and tell the user: "Figma isn't connected, so I can't read the design. Please connect the Figma MCP connector first." Use `suggest_connectors` / `search_mcp_registry` if appropriate to help them connect it.
   - If the MCP is connected but fails to read the specific file/page (permissions, bad URL, deleted file, etc.) → **stop** and tell the user the exact reason: "I can connect to Figma but can't read this file — [reason]. Please check the link/permissions."
2. Confirm the user has supplied both a live site URL and a Figma page/frame URL. If either is missing, ask for it (don't guess).
3. Check that `agent-browser` is available (`command -v agent-browser`). If not, tell the user to install it: `npm i -g agent-browser && agent-browser install`.
4. Only after all checks pass, proceed to Step 1.

## Step 1 — Pull the Figma design data

- Fetch the target Figma page/frame(s) via the Figma MCP: node tree, frame dimensions, text content, fonts, font sizes, colors (fills/strokes, including text color), spacing, and image fills.
- Detect the frame width. 1920px is the common desktop baseline, but it varies by project — use whatever width the actual frame reports, don't assume 1920.
- Detect whether the Figma file only contains a desktop frame (no tablet/mobile frames). If so, note this explicitly in the report: responsive breakpoints will be checked against the live site's own responsive behavior and general usability heuristics rather than a pixel design reference, since no mobile/tablet Figma frame exists.
- Break the frame into logical sections in top-to-bottom order (e.g. header/nav, hero, feature sections, testimonials, footer, etc.) using visual grouping/frame names as a guide. This section list is the backbone of the whole report — keep section names consistent between Figma and live site comparisons.

### Mapping Figma sections to live site sections

The collection script auto-detects sections heuristically by scanning for common container classes (`section`, `[class*="hero"]`, `[class*="header"]`, `[class*="footer"]`, etc.). For sites built with page builders (Elementor, WordPress custom themes, Webflow, etc.), auto-detection may miss or misidentify sections. To override:

1. After Step 1 (Figma data), identify the Figma section names and write a **`sections-config.json`** file into the per-run data directory:

   ```json
   {
     "sections": [
       { "name": "Header",      "selector": "header#site-header" },
       { "name": "Hero",         "selector": "section.hero-banner" },
       { "name": "Features",     "selector": ".elementor-section.features" },
       { "name": "Testimonials", "selector": "#testimonials" },
       { "name": "Footer",       "selector": "footer.site-footer" }
     ]
   }
   ```

2. Each entry needs a `name` (the human-readable label used in the report) and a `selector` (any valid CSS selector — ID, class, attribute, or compound — that uniquely identifies the section on the live page).

3. Write this file **before** running Step 5 (report generation). The report generator reads it and uses these sections instead of the auto-detected ones.

4. If the auto-detected sections are close but need minor fixes, you can also edit `site-wide.json`'s `sections` array directly to adjust labels, or write `sections-config.json` to replace only specific sections (unspecified sections fall back to auto-detection).

5. If you cannot determine the correct selector from the Figma design alone, run the collection script first (Step 2), inspect the auto-detected sections in `site-wide.json`, and then create `sections-config.json` using the `selector` fields from the auto-detected sections as a starting point.

## Step 2 — Collect live site data (scripted)

Do **not** use DevTools MCP or manual `evaluate_script` for this. Run the collection script instead.

1. Determine the per-run output directory path: `./figma-design-qa-reports/<YYYY-MM-DD_HH-MM>_<slug>/`.
2. Run the collection script:

   ```bash
   bash <absolute-path-to-scripts/qa-collect.sh> "https://example.com" "./figma-design-qa-reports/<run-folder>"
   ```

3. Wait for the script to complete. On success it prints `"=== QA Collection Complete ==="` and the paths to data and screenshots.
4. Verify the output files exist: `ls <run-folder>/data/site-wide.json` and at least a few `bp-*.json` files.

The script handles:
- Opening the site at desktop width, scrolling to trigger lazy content
- Collecting site-wide data with **CSS selector** and **XPath** on every element:
  - **headings** — tag, text, font-size, color, `selector`, `xpath`
  - **images** — src, natural dimensions, alt, visibility, `selector`, `xpath`
  - **links** — href, text, empty/placeholder flags, `selector`, `xpath`
  - **sections** — tag, class, position/dimensions, text preview, `label` (human-readable name from heading/aria-label), `selector`, `xpath`
  - **overflows** — elements wider than viewport, `selector`, `xpath`
  - heading hierarchy check (h1 count, size inversion)
  - broken image detection, link transition detection, favicon presence
- Testing every breakpoint from `references/breakpoints.md` and taking full-page screenshots
- Breakpoint-specific data with **section attribution**:
  - **overflows** — includes `sectionLabel` (parent section name), `selector`, `xpath`
  - **hiddenSections** — collapsed sections with `label`, `elementSelector`, `xpath`
  - **hamburger nav detection** — mobile only, with extracted nav links

## Step 3 — Section-by-section comparison

For every matched section, evaluate each parameter below and assign exactly one of **pass / warning / severe**. Do not skip a parameter just because it looks fine at a glance — check it explicitly.

Read `references/checklist.md` for the full parameter-by-parameter rules (color, fonts, font size tolerance, content/copy matching, dummy text detection, container sizing, links, hover states, heading hierarchy, images, favicon, page title). That file is the source of truth for severity thresholds — follow it exactly, especially the font-size ±10% rule and the "any content mismatch = severe" rule.

### Aligning sections

If the auto-detected sections in `site-wide.json` don't match the Figma sections from Step 1:

1. **Review the auto-detected sections**: open `site-wide.json` and inspect the `sections` array. Each entry has a `label`, `selector`, `xpath`, `class`, `top`, and `height`.
2. **Match them to Figma sections**: map each Figma section name to the corresponding live site section. Use the `selector` field to verify in the browser.
3. **Create `sections-config.json`** (see Step 1) with the correct `name` → `selector` mapping. Write it to `<run-folder>/data/sections-config.json`.
4. **Re-run the report generator** to pick up the manual section mapping.

For automated checks, cross-reference the data from `./figma-design-qa-reports/<run-folder>/data/site-wide.json` against the Figma design data from Step 1:
- Compare the live site's **page title** (from JSON) against Figma's expected title.
- Compare **favicon** existence (from JSON) against expected.
- Compare **heading hierarchy** (from JSON `headingInversion`, `h1s` count) against Figma. Each heading includes a `selector` for quick location.
- Compare **images** (from JSON `brokenImages`) — flag broken ones. The `selector` field identifies the element.
- Compare **links** (from JSON `emptyLinks`, `placeholderLinks`) — flag issues with `selector` for location.
- Compare **link hover transitions** (from JSON `linkTransition`).
- Compare **section boundaries** (from JSON `sections`) against Figma frame sections. Each section includes `label`, `selector`, `xpath`, and position data.

For color, font family, font size, content/copy, container dimensions, and other visual checks, you still need to compare Figma data against the live site screenshots in `./figma-design-qa-reports/<run-folder>/screenshots/` — the script does not extract per-element computed styles.

## Step 4 — Responsive / cross-browser testing

This is already handled by `qa-collect.sh` — it tests every breakpoint from `references/breakpoints.md`. Do **not** re-run responsive tests with DevTools MCP.

To review results:
1. Read the per-breakpoint JSON files in `./figma-design-qa-reports/<run-folder>/data/bp-*.json` for:
   - `overflows` — elements wider than viewport. Each entry includes `sectionLabel` (which section the overflow belongs to), `selector`, and `xpath` for easy DevTools location.
   - `hiddenSections` — collapsed/zero-height sections. Each entry includes `label` (section name), `elementSelector`, and `xpath`.
   - `hamburgerDetected` / `hamburgerLinks` — mobile-only nav parity
2. Scan the screenshots at each breakpoint (in `./figma-design-qa-reports/<run-folder>/screenshots/`) for:
   - text/content overflow caused by font size
   - all sections and their content remain visible (nothing clipped, collapsed, or hidden unintentionally)
   - spacing between sections still looks balanced (no collisions or huge unintended gaps)
   - on mobile widths specifically: hamburger menu opens, and the resulting nav contains exactly the same links as desktop nav (cross-reference against `site-wide.json` links)

Flag any issues found, using `references/checklist.md` severity rules.

## Step 5 — Compile the report as HTML + CSV (+ PDF)

The final deliverables are **`report.html`** and **`report.csv`** — never just a chat-only summary. All artifacts are written into the per-run folder under `./figma-design-qa-reports/<run-folder>/`.

### Report generation via script

Run the report generator script — it reads collected data and produces `report.html`, `report.csv`, and optionally `report.pdf`:

```bash
node <absolute-path-to-scripts/qa-generate-report.js> ./figma-design-qa-reports/<run-folder>
```

The script:
1. Loads `site-wide.json`, all `bp-*.json` files, and optional `sections-config.json` from the data directory
2. Resolves sections (manual override if `sections-config.json` exists, otherwise auto-detected from `site-wide.json`)
3. Builds `report.html` with:
   - **Summary box** — pass/warning/severe counts, section count, breakpoint count, site URL, date, and whether sections were manual or auto-detected
   - **Per-section tables** — one dedicated table per section, each with columns: Section, Parameter, Expected, Found, Verdict, Note, **Selector** (copy-paste CSS selector for DevTools)
   - **Site-wide checks table** — page title, favicon, broken images, heading hierarchy, empty headings, links, link transitions — all with Selector column
   - **Responsive tables** — grouped by section+category (e.g. "Hero / mobile"), with overflows and hidden sections attributed to their parent section via `sectionLabel`
   - **Screenshots gallery** — all breakpoint screenshots with lazy loading and clickable links
   - **Jump navigation** — anchor links to every section table, site-wide table, responsive section, and screenshots
4. Builds `report.csv` — same data in CSV format with columns: Section, Parameter, Expected, Found, Verdict, Note, Selector. Ready for Jira bug import or Excel analysis.
5. Attempts PDF conversion via `agent-browser` → `chromium` → `google-chrome` → `wkhtmltopdf` → `weasyprint` (first found on PATH)

If the script's report is sufficient, you're done. If additional manual findings need to be added (e.g. color/font discrepancies found in Step 3), append them to the HTML report before PDF conversion, or note them alongside the final PDF.

Structure the report (HTML / CSV) as follows:

1. **Cover / Summary page** — site URL, Figma file/page URL, date, detected Figma frame width, whether mobile/tablet Figma frames existed, section source (manual override vs auto-detected), and a totals box: count of pass / warning / severe / total checks / sections / breakpoints.
2. **Section-by-section report** — for every identified section (in page order), a dedicated table. Every parameter from `references/checklist.md` that applies to that section must appear as its own row. Each row has: **Section | Parameter | Expected (Figma) | Found (Live Site) | Verdict (pass/warning/severe) | Note | Selector**. The Selector column contains a copy-paste CSS selector the developer can use in DevTools to locate the element.
3. **Site-wide checks** — same table format with Selector column for: page title, favicon, broken images (each with its `selector`), heading hierarchy and size-consistency findings, empty heading audit (each with `selector`), full link audit (every bad/empty href with its `selector`), and link hover transition.
4. **Responsive / cross-browser report** — grouped by section+category (e.g. "Hero / desktop", "Footer / mobile"). Within each group, rows cover: overflow (with `sectionLabel` attribution and `selector`), section visibility (collapsed sections with `label` and `elementSelector`), and (mobile only) hamburger nav parity — each with its own verdict, not just a single pass/fail per size.
5. **Appendix (optional)** — screenshots gallery with all breakpoint screenshots, each clickable to view full-size. Any additional screenshots/notes that materially help explain a severe finding. Screenshots are saved under `./figma-design-qa-reports/<run-folder>/screenshots/` and referenced with relative paths from `report.html`.
6. **CSV export** — `report.csv` mirrors the HTML content with columns: Section, Parameter, Expected, Found, Verdict, Note, Selector. Can be imported directly into Jira, Google Sheets, or Excel for bug tracking.

Be specific in every flagged item: name the section, what was expected (from Figma), what was found (on site), why it's that severity level, and include the **Selector** so developers can immediately locate the element. Save the final PDF to `./figma-design-qa-reports/<run-folder>/report.pdf`, the HTML to `report.html`, and the CSV to `report.csv` (all relative to cwd). Present the resolved paths to the user — don't just describe the findings in chat.
