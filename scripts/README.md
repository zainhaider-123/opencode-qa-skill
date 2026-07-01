# Figma Design QA with agent-browser

Automated Figma Design QA workflow using **agent-browser** (no Playwright/Puppeteer dependency).

## Overview

This toolkit performs complete design QA audits by:
1. Collecting live site data via `agent-browser` screenshots and DOM inspection
2. Mapping sections and responsive behavior across 20+ breakpoints
3. Generating a structured HTML/PDF report with pass/warning/severe verdicts
4. Comparing against Figma design data (requires manual or MCP-driven Figma data input)

## Scripts

| Script | Purpose |
|--------|---------|
| `figma-qa-collect-live-site.sh` | Full live site data collection using agent-browser |
| `figma-qa-generate-report.sh` | Builds HTML/PDF report from collected data |
| `figma-qa-delegator.sh` | Orchestrates single or batch QA runs |

## Quick Start

### 1. Single Run

```bash
# Set permissions
chmod +x scripts/*.sh

# Collect live site data
./scripts/figma-qa-collect-live-site.sh \
  "https://dev.webnhubs.com/laura-couture/" \
  "2024-01-15_laura-couture" \
  1920

# Generate report from collected data
./scripts/figma-qa-generate-report.sh "2024-01-15_laura-couture"
```

### 2. Using the Delegator

```bash
# Single run
./scripts/figma-qa-delegator.sh run \
  "https://dev.webnhubs.com/laura-couture/" \
  "https://www.figma.com/design/...?node-id=535-336" \
  1920

# Batch from config
./scripts/figma-qa-delegator.sh batch ./qa-jobs.json
```

### 3. Batch Config Format

```json
[
  {
    "siteUrl": "https://dev.webnhubs.com/laura-couture/",
    "figmaUrl": "https://www.figma.com/design/2ccVTVMYcSblKswGQ6oJO8/...",
    "frameWidth": 1920
  }
]
```

## What Gets Collected

### Site-Wide Data
- **Page title** — `<title>` tag content
- **Favicon** — `link[rel*=icon]` detection and status
- **All images** — src, alt text, natural dimensions, visibility
- **All links** — href resolved/empty/placeholder detection
- **Heading hierarchy** — h1-h6 in document order with computed styles
- **Computed styles** — font-family, font-size, color, background-color per key element
- **Hover states** — default transition and color properties

### Per-Section Data
- **Screenshot mapping** — each detected section (`<header>`, `<nav>`, `<section>`, `<footer>`, etc.) is individually screenshotted at the Figma frame width
- **Bounding boxes** — position, dimensions, background color per section
- **Computed styles** — font and color properties per section type

### Responsive Testing (All Breakpoints)

| Category | Breakpoints |
|----------|------------|
| Desktop | 1280x720, 1366x768, 1400x900, 1440x900, 1536x864, 1600x900, 1680x1050, 1792x1120, 1920x1080, 2048x1536, 2560x1440 |
| iPad | 768x1024, 810x1180, 1024x1366 |
| Mobile | 360x740, 412x915, 430x932, 375x740 |

For each breakpoint the script checks:
- **Overflow** — elements with `scrollWidth > clientWidth` or `scrollHeight > clientHeight`
- **Section visibility** — any `display: none` or `visibility: hidden` sections
- **Spacing** — gaps between sections (overlap or >200px gap detection)
- **Hamburger menu** — mobile-only: detection of menu toggle elements

## Output Structure

```
./figma-design-qa-reports/
└── <YYYY-MM-DD_HH-MM>_<hostname>/
    ├── screenshots/
    │   ├── desktop-1920x1080-full.png
    │   ├── section-0-header.png
    │   ├── section-1-hero.png
    │   ├── desktop-1280x720-full.png
    │   ├── ipad-768x1024-full.png
    │   ├── mobile-360x740-full.png
    │   └── ...
    ├── data/
    │   ├── collection-summary.json
    │   ├── page-title.txt
    │   ├── favicon.json
    │   ├── all-images.json
    │   ├── all-links.json
    │   ├── heading-hierarchy.json
    │   ├── computed-styles.json
    │   ├── hover-states.json
    │   ├── hover-states-detailed.json
    │   ├── section-boundaries.json
    │   ├── section-bboxes.json
    │   └── responsive-{category}-{w}x{h}.json (one per breakpoint)
    ├── report.html
    └── report.pdf
```

## Report Verdicts

| Verdict | Meaning |
|---------|---------|
| **pass** | Matches expected behavior or no issue found |
| **warning** | Cosmetic drift, placeholder content, or minor spacing issue |
| **severe** | Broken functionality, missing content, structural issues, accessibility problems |

## Requirements

- `agent-browser` CLI installed globally: `npm i -g agent-browser && agent-browser install`
- `jq` for JSON processing
- A headless browser for PDF conversion (chromium/google-chrome/wkhtmltopdf/weasyprint/pandoc)
- Bash 4+

## Integration with Figma MCP

These scripts handle the **live site** side of the QA workflow. To complete the full Figma comparison:

1. **Figma data pull** — Use the Figma MCP tools (e.g., `figma_get_design_context`, `figma_get_variable_defs`) to export:
   - Frame dimensions
   - Section colors/fonts/font-sizes
   - Text content
   - Image fills
   - Component specs

2. **Merge** — Place Figma data alongside `data/` and update the report generator to compare values

3. **Full comparison** — The report currently marks Figma-expected fields as *"Pending Figma data"*. With Figma JSON injected, these become automatic pass/warning/severe checks.

## Delegation via Task Tool

These scripts are designed to be called via the `task` tool for background execution:

```bash
# In your agent session, delegate the collection:
task subagent_type="fixer" description="QA collect live site data" prompt="
Run the live site data collection script for https://dev.webnhubs.com/laura-couture/
using agent-browser. Execute: ./scripts/figma-qa-collect-live-site.sh <url> <run-folder> <width>
Wait for it to complete and return the path to the output folder.
"
```

## Troubleshooting

### "agent-browser not found"
```bash
npm install -g agent-browser
agent-browser install
```

### "jq not found"
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq
```

### Browser session stuck
The collection script automatically calls `agent-browser close` on exit via `trap cleanup EXIT`. If a session hangs manually:
```bash
agent-browser close
```

### Screenshot quality
For higher resolution, set viewport with device pixel ratio before collection:
```bash
agent-browser set viewport 1920 1080 2  # 2x retina
```

## Extending

- **Add more breakpoints**: Edit the `*_BREAKPOINTS` arrays in `figma-qa-collect-live-site.sh`
- **Add custom checks**: Extend the `eval_js` calls in each collection function
- **Custom report templates**: Modify the HTML generation in `figma-qa-generate-report.sh`
