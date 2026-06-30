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
- When you need a slug for the run folder, derive it from the live site's hostname (e.g. `example.com`).
- Before writing, run `mkdir -p ./figma-design-qa-reports/<run-folder>` so all subsequent paths resolve.

## Step 0 — Preconditions (must pass before anything else)

1. Check whether a Figma MCP connector is connected and usable (try a lightweight Figma MCP call, e.g. fetching file/page metadata for the given Figma URL).
   - If no Figma MCP tool is available at all → **stop** and tell the user: "Figma isn't connected, so I can't read the design. Please connect the Figma MCP connector first." Use `suggest_connectors` / `search_mcp_registry` if appropriate to help them connect it.
   - If the MCP is connected but fails to read the specific file/page (permissions, bad URL, deleted file, etc.) → **stop** and tell the user the exact reason: "I can connect to Figma but can't read this file — [reason]. Please check the link/permissions."
2. Confirm the user has supplied both a live site URL and a Figma page/frame URL. If either is missing, ask for it (don't guess).
3. Only after both checks pass, proceed to Step 1.

## Step 1 — Pull the Figma design data

- Fetch the target Figma page/frame(s) via the Figma MCP: node tree, frame dimensions, text content, fonts, font sizes, colors (fills/strokes, including text color), spacing, and image fills.
- Detect the frame width. 1920px is the common desktop baseline, but it varies by project — use whatever width the actual frame reports, don't assume 1920.
- Detect whether the Figma file only contains a desktop frame (no tablet/mobile frames). If so, note this explicitly in the report: responsive breakpoints will be checked against the live site's own responsive behavior and general usability heuristics rather than a pixel design reference, since no mobile/tablet Figma frame exists.
- Break the frame into logical sections in top-to-bottom order (e.g. header/nav, hero, feature sections, testimonials, footer, etc.) using visual grouping/frame names as a guide. This section list is the backbone of the whole report — keep section names consistent between Figma and live site comparisons.

## Step 2 — Pull the live site data

- Load the live site at the Figma frame's reference width first (e.g. via browser viewport set to the detected frame width) and segment it into the same sections identified in Step 1, matching by content/order, not just by visual guess.
- Also collect site-wide metadata once: `<title>`, favicon `<link>` tag and whether it 200s, all `<img>` src statuses, all `<a href>` values (including `mailto:`), computed hover styles/transition durations on links, and the full heading tree (h1–h6) for the page in document order.

## Step 3 — Section-by-section comparison

For every matched section, evaluate each parameter below and assign exactly one of **pass / warning / severe**. Do not skip a parameter just because it looks fine at a glance — check it explicitly.

Read `references/checklist.md` for the full parameter-by-parameter rules (color, fonts, font size tolerance, content/copy matching, dummy text detection, container sizing, links, hover states, heading hierarchy, images, favicon, page title). That file is the source of truth for severity thresholds — follow it exactly, especially the font-size ±10% rule and the "any content mismatch = severe" rule.

## Step 4 — Responsive / cross-browser testing

Test the live site at every breakpoint listed in `references/breakpoints.md` (this is the fixed, required list — don't substitute your own sizes). At each breakpoint check, per `references/checklist.md`'s responsive section:
- text/content overflow caused by font size
- all sections and their content remain visible (nothing clipped, collapsed, or hidden unintentionally)
- spacing between sections still looks balanced (no collisions or huge unintended gaps)
- on mobile widths specifically: hamburger menu opens, and the resulting nav contains exactly the same links as desktop nav

## Step 5 — Compile the report as a PDF

The final deliverable is always a **PDF file** — never just a chat-only summary. The PDF (and every intermediate artifact) is written into the per-run folder under `./figma-design-qa-reports/<run-folder>/` relative to cwd (see "Working directory" above).

### PDF generation (self-contained, project-relative)

Do NOT reference any external/absolute skill path (e.g. `/mnt/skills/...`) — assume it does not exist. Build the PDF yourself from the report HTML, using whatever HTML→PDF tooling is available in the current environment. Use this workflow:

1. Build the report as a single clean HTML file at `./figma-design-qa-reports/<run-folder>/report.html`. Inline all CSS (use a `<style>` block), use simple table-based layout for the verdict tables, and embed any screenshots as relative paths (e.g. `<img src="screenshots/hero.png">`) — keep everything inside the run folder so the PDF is portable.
2. Detect which HTML→PDF converter is available (try them in this order, use the first that exists on `PATH`):
   - `weasyprint` → `weasyprint ./figma-design-qa-reports/<run-folder>/report.html ./figma-design-qa-reports/<run-folder>/report.pdf`
   - `wkhtmltopdf` → `wkhtmltopdf ./figma-design-qa-reports/<run-folder>/report.html ./figma-design-qa-reports/<run-folder>/report.pdf`
   - `chromium` / `google-chrome` / `chrome` (headless) → `<browser> --headless --disable-gpu --no-pdf-header-footer --print-to-pdf=./figma-design-qa-reports/<run-folder>/report.pdf ./figma-design-qa-reports/<run-folder>/report.html`
   - `pandoc` with a PDF engine → `pandoc ./figma-design-qa-reports/<run-folder>/report.html -o ./figma-design-qa-reports/<run-folder>/report.pdf` (add `--pdf-engine=weasyprint|wkhtmltopdf|pdflatex` as available)
3. If none of the above are installed, install one on demand (e.g. `pip install weasyprint` or the OS package), or ask the user which they prefer. As a last resort, deliver `report.html` and tell the user exactly why no PDF engine was available.
4. Verify the PDF was created (`ls -la` on the path) before declaring done. If conversion fails, still keep `report.html` as the deliverable and tell the user exactly which engine failed and why.

Structure the report (HTML → PDF) as follows:

1. **Cover / Summary page** — site URL, Figma file/page URL, date, detected Figma frame width, whether mobile/tablet Figma frames existed (and therefore whether responsive checks used a design reference or general heuristics), and a totals box: count of pass / warning / severe across the whole audit.
2. **Section-by-section report** — for every section identified in Step 1/2 (in page order), include a table with one row per parameter actually tested for that section. Every parameter from `references/checklist.md` that applies to that section must appear as its own row — do not collapse or omit parameters, and do not only list failures. Each row has: **Parameter | Expected (Figma) | Found (Live Site) | Verdict (pass/warning/severe) | Note**. Use a clear visual marker for verdict (e.g. ✅ pass, ⚠️ warning, 🛑 severe) so the scale is scannable at a glance.
3. **Site-wide checks** — same table format for page title, favicon, full link audit (every href, including mailto, with its own row), and heading hierarchy/size-consistency findings across the whole page.
4. **Responsive / cross-browser report** — one subsection per breakpoint category (Desktop, iPad, Mobile), and within each, one row per breakpoint size from `references/breakpoints.md` covering: overflow, section visibility, section spacing, and (mobile only) hamburger nav parity — each with its own verdict, not just a single pass/fail per size.
5. **Appendix (optional)** — any screenshots/notes that materially help explain a severe finding, if available. Save screenshots into `./figma-design-qa-reports/<run-folder>/screenshots/` and reference them with relative paths from `report.html`.

Be specific in every flagged item: name the section, what was expected (from Figma), what was found (on site), and why it's that severity level. Save the final PDF to `./figma-design-qa-reports/<run-folder>/report.pdf` (relative to cwd) and present the absolute resolved path to the user — don't just describe the findings in chat.
