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

Opens the live site via `agent-browser`, collects all site-wide data (title, favicon, images, links, headings, sections, overflow), tests every responsive breakpoint from `references/breakpoints.md`, takes full-page screenshots, and detects hamburger nav + overflow issues. Saves everything into the per-run data directory.

**Usage:** `bash <skill-dir>/scripts/qa-collect.sh <site-url> [output-directory]`

- `<skill-dir>` is the absolute path to this skill's folder (resolve it at runtime with `dirname $(readlink -f $0)` or by finding `.agents/skills/figma-design-qa/` relative to cwd).
- `[output-directory]` defaults to `./figma-design-qa-reports/<timestamp>_<slug>/`.

### `scripts/qa-generate-report.js`

Reads collected data (site-wide.json, bp-*.json, screenshots) from the per-run folder and generates `report.html` + attempts PDF conversion.

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
- Collecting site-wide data (title, favicon, images, links, headings, heading hierarchy, broken images, overflows, section boundaries)
- Testing every breakpoint from `references/breakpoints.md` and taking full-page screenshots
- Overflow detection, hidden section detection, and hamburger nav detection (mobile only)

## Step 3 — Section-by-section comparison

For every matched section, evaluate each parameter below and assign exactly one of **pass / warning / severe**. Do not skip a parameter just because it looks fine at a glance — check it explicitly.

Read `references/checklist.md` for the full parameter-by-parameter rules (color, fonts, font size tolerance, content/copy matching, dummy text detection, container sizing, links, hover states, heading hierarchy, images, favicon, page title). That file is the source of truth for severity thresholds — follow it exactly, especially the font-size ±10% rule and the "any content mismatch = severe" rule.

For automated checks, cross-reference the data from `./figma-design-qa-reports/<run-folder>/data/site-wide.json` against the Figma design data from Step 1:
- Compare the live site's **page title** (from JSON) against Figma's expected title.
- Compare **favicon** existence (from JSON) against expected.
- Compare **heading hierarchy** (from JSON `headingInversion`, `h1s` count) against Figma.
- Compare **images** (from JSON `brokenImages`) — flag broken ones.
- Compare **links** (from JSON `emptyLinks`, `placeholderLinks`) — flag issues.
- Compare **link hover transitions** (from JSON `linkTransition`).
- Compare **section boundaries** (from JSON `sections`) against Figma frame sections.

For color, font family, font size, content/copy, container dimensions, and other visual checks, you still need to compare Figma data against the live site screenshots in `./figma-design-qa-reports/<run-folder>/screenshots/` — the script does not extract per-element computed styles.

## Step 4 — Responsive / cross-browser testing

This is already handled by `qa-collect.sh` — it tests every breakpoint from `references/breakpoints.md`. Do **not** re-run responsive tests with DevTools MCP.

To review results:
1. Read the per-breakpoint JSON files in `./figma-design-qa-reports/<run-folder>/data/bp-*.json` for:
   - `overflows` — elements wider than viewport (script caps at 30 unique culprits)
   - `hiddenSections` — collapsed/zero-height sections
   - `hamburgerDetected` / `hamburgerLinks` — mobile-only nav parity
2. Scan the screenshots at each breakpoint (in `./figma-design-qa-reports/<run-folder>/screenshots/`) for:
   - text/content overflow caused by font size
   - all sections and their content remain visible (nothing clipped, collapsed, or hidden unintentionally)
   - spacing between sections still looks balanced (no collisions or huge unintended gaps)
   - on mobile widths specifically: hamburger menu opens, and the resulting nav contains exactly the same links as desktop nav (cross-reference against `site-wide.json` links)

Flag any issues found, using `references/checklist.md` severity rules.

## Step 5 — Compile the report as a PDF

The final deliverable is always a **PDF file** — never just a chat-only summary. The PDF (and every intermediate artifact) is written into the per-run folder under `./figma-design-qa-reports/<run-folder>/` relative to cwd (see "Working directory" above).

### PDF generation via script

Run the report generator script — it reads collected data and produces `report.html`, then attempts PDF conversion:

```bash
node <absolute-path-to-scripts/qa-generate-report.js> ./figma-design-qa-reports/<run-folder>
```

The script:
1. Loads `site-wide.json` and all `bp-*.json` files from the data directory
2. Builds a complete `report.html` with:
   - Summary box (pass/warning/severe counts)
   - Table rows for: page title, favicon, broken images, heading hierarchy, empty headings, links, link transitions, section detection, and responsive checks (overflow, hidden sections, hamburger) at every breakpoint
   - Screenshots gallery
3. Attempts PDF conversion via `agent-browser` (open file with `--allow-file-access`, then `pdf` command), falling back to `chromium` → `google-chrome` → `wkhtmltopdf` → `weasyprint` (first found on PATH)
4. Falls back to `report.html` only if no PDF engine is available

If the script's report is sufficient, you're done. If additional manual findings need to be added (e.g. color/font discrepancies found in Step 3), append them to the HTML report before PDF conversion, or note them alongside the final PDF.

Structure the report (HTML → PDF) as follows:

1. **Cover / Summary page** — site URL, Figma file/page URL, date, detected Figma frame width, whether mobile/tablet Figma frames existed (and therefore whether responsive checks used a design reference or general heuristics), and a totals box: count of pass / warning / severe across the whole audit.
2. **Section-by-section report** — for every section identified in Step 1/2 (in page order), include a table with one row per parameter actually tested for that section. Every parameter from `references/checklist.md` that applies to that section must appear as its own row — do not collapse or omit parameters, and do not only list failures. Each row has: **Parameter | Expected (Figma) | Found (Live Site) | Verdict (pass/warning/severe) | Note**. Use a clear visual marker for verdict (e.g. ✅ pass, ⚠️ warning, 🛑 severe) so the scale is scannable at a glance.
3. **Site-wide checks** — same table format for page title, favicon, full link audit (every href, including mailto, with its own row), and heading hierarchy/size-consistency findings across the whole page.
4. **Responsive / cross-browser report** — one subsection per breakpoint category (Desktop, iPad, Mobile), and within each, one row per breakpoint size from `references/breakpoints.md` covering: overflow, section visibility, section spacing, and (mobile only) hamburger nav parity — each with its own verdict, not just a single pass/fail per size.
5. **Appendix (optional)** — any screenshots/notes that materially help explain a severe finding, if available. Save screenshots into `./figma-design-qa-reports/<run-folder>/screenshots/` and reference them with relative paths from `report.html`.

Be specific in every flagged item: name the section, what was expected (from Figma), what was found (on site), and why it's that severity level. Save the final PDF to `./figma-design-qa-reports/<run-folder>/report.pdf` (relative to cwd) and present the absolute resolved path to the user — don't just describe the findings in chat.
