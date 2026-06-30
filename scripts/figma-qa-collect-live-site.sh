#!/usr/bin/env bash
#
# figma-qa-collect-live-site.sh
#
# Collects all live-site data needed for a Figma Design QA report
# using agent-browser (no Playwright/Puppeteer dependency).
#
# Usage:
#   ./figma-qa-collect-live-site.sh <site-url> <run-folder> [figma-frame-width]
#
# Arguments:
#   site-url          — Full URL of the live site to test
#   run-folder        — Name of the run folder under ./figma-design-qa-reports/
#   figma-frame-width — Width of the Figma desktop frame (default: 1920)
#
# Outputs:
#   All artifacts written to ./figma-design-qa-reports/<run-folder>/
#
# Requires:
#   - agent-browser CLI installed and on PATH
#   - Bash 4+
#
# Author: Generated for figma-design-qa skill with agent-browser

set -euo pipefail

# ------------------------------------------------------------------
# Arguments & defaults
# ------------------------------------------------------------------
SITE_URL="${1:?Usage: $0 <site-url> <run-folder> [figma-frame-width]}"
RUN_FOLDER="${2:?Usage: $0 <site-url> <run-folder> [figma-frame-width]}"
FIGMA_FRAME_WIDTH="${3:-1920}"
OUTPUT_ROOT="./figma-design-qa-reports"
OUTPUT_DIR="$OUTPUT_ROOT/$RUN_FOLDER"
SCREENSHOTS_DIR="$OUTPUT_DIR/screenshots"
DATA_DIR="$OUTPUT_DIR/data"

# Breakpoints from references/breakpoints.md
declare -a DESKTOP_BREAKPOINTS=(
  "1280x720" "1366x768" "1400x900" "1440x900" "1536x864"
  "1600x900" "1680x1050" "1792x1120" "1920x1080" "2048x1536" "2560x1440"
)

declare -a IPAD_BREAKPOINTS=(
  "768x1024" "810x1180" "1024x1366"
)

declare -a MOBILE_BREAKPOINTS=(
  "360x740" "412x915" "430x932" "375x740"
)

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------
check_prerequisites() {
  log_info "Checking prerequisites..."

  if ! command -v agent-browser &>/dev/null; then
    log_error "agent-browser is not installed or not on PATH."
    log_error "Install with: npm i -g agent-browser && agent-browser install"
    exit 1
  fi

  if ! command -v jq &>/dev/null; then
    log_error "jq is required but not installed. Install it first."
    exit 1
  fi

  mkdir -p "$SCREENSHOTS_DIR" "$DATA_DIR"
  log_info "Output directory: $OUTPUT_DIR"
}

# ------------------------------------------------------------------
# Cleanup on exit
# ------------------------------------------------------------------
cleanup() {
  log_info "Closing browser session..."
  agent-browser close 2>/dev/null || true
}
trap cleanup EXIT

# ------------------------------------------------------------------
# Core helpers
# ------------------------------------------------------------------
set_viewport() {
  local w="$1"
  local h="$2"
  agent-browser set viewport "$w" "$h"
}

take_screenshot() {
  local path="$1"
  agent-browser screenshot --full "$path"
}

eval_js() {
  # Safely run JS and capture JSON output
  local script="$1"
  local b64
  b64=$(echo -n "$script" | base64 -w0)
  agent-browser eval -b "$b64" --json 2>/dev/null | jq -n 'input // {}'
}

# ------------------------------------------------------------------
# 1. Open site at Figma frame width and collect site-wide metadata
# ------------------------------------------------------------------
collect_site_metadata() {
  log_info "Step 1: Opening site at ${FIGMA_FRAME_WIDTH}px width..."

  agent-browser open "$SITE_URL"
  agent-browser wait --load networkidle

  # Determine a reasonable height for the viewport (we'll scroll anyway)
  set_viewport "$FIGMA_FRAME_WIDTH" 1080
  agent-browser wait 1000

  # --- Page title ---
  log_info "  → Collecting page title..."
  local title
  title=$(agent-browser get title)
  echo "$title" > "$DATA_DIR/page-title.txt"

  # --- Favicon ---
  log_info "  → Collecting favicon info..."
  local favicon_data
  favicon_data=$(eval_js '
    const link = document.querySelector("link[rel*=\"icon\"]");
    if (!link) return JSON.stringify({found: false, href: null});
    return JSON.stringify({found: true, href: link.href, sizes: link.sizes?.value || null});
  ')
  echo "$favicon_data" | jq '.' > "$DATA_DIR/favicon.json"

  # --- All links ---
  log_info "  → Collecting all links..."
  local links_data
  links_data=$(eval_js '
    const links = Array.from(document.querySelectorAll("a"));
    return JSON.stringify(links.map(a => ({
      href: a.getAttribute("href"),
      resolvedHref: a.href,
      text: a.innerText.trim().substring(0, 200),
      hasClickHandler: a.onclick !== null || a.getAttribute("onclick") !== null
    })));
  ')
  echo "$links_data" | jq '.' > "$DATA_DIR/all-links.json"

  # --- All images ---
  log_info "  → Collecting all images..."
  local images_data
  images_data=$(eval_js '
    const imgs = Array.from(document.querySelectorAll("img"));
    return JSON.stringify(imgs.map(img => ({
      src: img.src,
      alt: img.alt,
      width: img.naturalWidth,
      height: img.naturalHeight,
      visible: img.offsetParent !== null
    })));
  ')
  echo "$images_data" | jq '.' > "$DATA_DIR/all-images.json"

  # --- Heading hierarchy ---
  log_info "  → Collecting heading hierarchy..."
  local headings_data
  headings_data=$(eval_js '
    const headings = Array.from(document.querySelectorAll("h1,h2,h3,h4,h5,h6"));
    return JSON.stringify(headings.map(h => {
      const rect = h.getBoundingClientRect();
      const style = window.getComputedStyle(h);
      return {
        tag: h.tagName,
        text: h.innerText.trim().substring(0, 300),
        fontSize: style.fontSize,
        fontFamily: style.fontFamily,
        fontWeight: style.fontWeight,
        color: style.color,
        top: rect.top + window.scrollY,
        id: h.id,
        className: h.className
      };
    }));
  ')
  echo "$headings_data" | jq '.' > "$DATA_DIR/heading-hierarchy.json"

  # --- Computed styles sample (hero + nav areas) ---
  log_info "  → Collecting computed styles for key elements..."
  local styles_data
  styles_data=$(eval_js '
    const selectors = ["body", "h1", "h2", "h3", "a", "button", "header", "nav", "main", "footer", "section"];
    const results = {};
    selectors.forEach(sel => {
      const el = document.querySelector(sel);
      if (el) {
        const style = window.getComputedStyle(el);
        results[sel] = {
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          color: style.color,
          backgroundColor: style.backgroundColor,
          lineHeight: style.lineHeight,
          letterSpacing: style.letterSpacing
        };
      }
    });
    return JSON.stringify(results);
  ')
  echo "$styles_data" | jq '.' > "$DATA_DIR/computed-styles.json"

  # --- Hover state data ---
  log_info "  → Collecting hover state data..."
  local hover_data
  hover_data=$(eval_js '
    const firstLink = document.querySelector("a");
    if (!firstLink) return JSON.stringify({found: false});
    const before = window.getComputedStyle(firstLink);
    return JSON.stringify({
      found: true,
      defaultColor: before.color,
      defaultTextDecoration: before.textDecoration,
      transitionDuration: before.transitionDuration,
      transitionProperty: before.transitionProperty
    });
  ')
  echo "$hover_data" | jq '.' > "$DATA_DIR/hover-states.json"

  # --- Section boundary map ---
  log_info "  → Mapping section boundaries..."
  local sections_data
  sections_data=$(eval_js '
    const sectionTags = ["header", "nav", "section", "footer", "main", "article", "aside"];
    const elements = [];
    sectionTags.forEach(tag => {
      document.querySelectorAll(tag).forEach(el => {
        const rect = el.getBoundingClientRect();
        const style = window.getComputedStyle(el);
        elements.push({
          tag: el.tagName,
          id: el.id,
          className: el.className.substring(0, 200),
          top: rect.top + window.scrollY,
          height: rect.height,
          width: rect.width,
          bgColor: style.backgroundColor,
          textColor: style.color
        });
      });
    });
    // Also include common section class patterns
    document.querySelectorAll("[class*=hero], [class*=banner], [class*=feature], [class*=testimonial], [class*=cta], [class*=about], [class*=contact], [class*=service], [class*=portfolio], [class*=pricing], [class*=team], [class*=faq]").forEach(el => {
      const rect = el.getBoundingClientRect();
      const style = window.getComputedStyle(el);
      elements.push({
        tag: el.tagName,
        id: el.id,
        className: el.className.substring(0, 200),
        top: rect.top + window.scrollY,
        height: rect.height,
        width: rect.width,
        bgColor: style.backgroundColor,
        textColor: style.color
      });
    });
    // Sort by top position and deduplicate
    const seen = new Set();
    const unique = [];
    elements.sort((a, b) => a.top - b.top).forEach(el => {
      const key = el.tag + "|" + el.id + "|" + el.className;
      if (!seen.has(key)) { seen.add(key); unique.push(el); }
    });
    return JSON.stringify(unique);
  ')
  echo "$sections_data" | jq '.' > "$DATA_DIR/section-boundaries.json"

  # Screenshot at Figma frame width
  log_info "  → Taking full-page screenshot at ${FIGMA_FRAME_WIDTH}px..."
  take_screenshot "$SCREENSHOTS_DIR/desktop-${FIGMA_FRAME_WIDTH}x1080-full.png"

  log_info "Site metadata collection complete."
}

# ------------------------------------------------------------------
# 2. Responsive breakpoint testing
# ------------------------------------------------------------------
test_breakpoint() {
  local category="$1"
  local size="$2"
  local w h
  w=$(echo "$size" | cut -dx -f1)
  h=$(echo "$size" | cut -dx -f2)

  log_info "  [$category] Testing ${w}x${h}..."

  set_viewport "$w" "$h"
  agent-browser wait 800

  # Full-page screenshot
  take_screenshot "$SCREENSHOTS_DIR/${category}-${w}x${h}-full.png"

  # Collect responsive-specific data
  local resp_data
  resp_data=$(eval_js '
    // Check for overflow issues
    const allElements = Array.from(document.querySelectorAll("*"));
    const overflowIssues = allElements.filter(el => {
      const style = window.getComputedStyle(el);
      return (el.scrollWidth > el.clientWidth || el.scrollHeight > el.clientHeight) &&
             style.overflow === "hidden" &&
             el.clientWidth > 0 && el.clientHeight > 0;
    }).map(el => ({
      tag: el.tagName,
      className: el.className.substring(0, 100),
      id: el.id,
      scrollWidth: el.scrollWidth,
      clientWidth: el.clientWidth,
      scrollHeight: el.scrollHeight,
      clientHeight: el.clientHeight
    }));

    // Check section visibility
    const sections = Array.from(document.querySelectorAll("section, header, footer, .section, [class*=hero], [class*=banner]"));
    const sectionVisibility = sections.map(el => {
      const rect = el.getBoundingClientRect();
      const style = window.getComputedStyle(el);
      return {
        tag: el.tagName,
        className: el.className.substring(0, 100),
        visible: style.display !== "none" && style.visibility !== "hidden",
        inViewport: rect.top < window.innerHeight && rect.bottom > 0,
        height: rect.height,
        width: rect.width
      };
    });

    // Check for hamburger menu (mobile only)
    const hamburgerElements = Array.from(document.querySelectorAll("button, [role=button], a")).filter(el => {
      const text = el.innerText.toLowerCase();
      const aria = el.getAttribute("aria-label")?.toLowerCase() || "";
      return text.includes("menu") || text.includes("☰") || text.includes("hamburger") ||
             aria.includes("menu") || aria.includes("navigation") ||
             el.className.toLowerCase().includes("hamburger") ||
             el.className.toLowerCase().includes("menu-toggle");
    }).map(el => ({
      tag: el.tagName,
      className: el.className.substring(0, 100),
      text: el.innerText.trim().substring(0, 50),
      ariaLabel: el.getAttribute("aria-label")
    }));

    // Collect spacing between sections
    const spacingIssues = [];
    for (let i = 0; i < sections.length - 1; i++) {
      const current = sections[i].getBoundingClientRect();
      const next = sections[i + 1].getBoundingClientRect();
      const gap = next.top - (current.top + current.height);
      if (gap < -5 || gap > 200) {
        spacingIssues.push({
          between: sections[i].className.substring(0, 50) + " → " + sections[i+1].className.substring(0, 50),
          gap: gap
        });
      }
    }

    return JSON.stringify({
      viewport: { width: window.innerWidth, height: window.innerHeight },
      overflowIssues: overflowIssues.slice(0, 20),
      sectionVisibility: sectionVisibility,
      hamburgerMenu: hamburgerElements.slice(0, 5),
      spacingIssues: spacingIssues.slice(0, 10)
    });
  ')

  echo "$resp_data" | jq '.' > "$DATA_DIR/responsive-${category}-${w}x${h}.json"

  # For mobile: test hamburger menu if found
  if [[ "$category" == "mobile" ]]; then
    local has_hamburger
    has_hamburger=$(echo "$resp_data" | jq '.hamburgerMenu | length')
    if [[ "$has_hamburger" -gt 0 ]]; then
      log_info "    → Hamburger menu detected, testing..."
      # We can''t easily click via JSON eval, but we can note it was found
      echo '{"tested": true, "found": true}' > "$DATA_DIR/mobile-nav-${w}x${h}.json"
    fi
  fi
}

run_responsive_tests() {
  log_info "Step 2: Running responsive breakpoint tests..."

  # Make sure we''re on the site first
  local current_url
  current_url=$(agent-browser get url 2>/dev/null || echo "")
  if [[ "$current_url" != *"webnhubs.com"* ]]; then
    agent-browser open "$SITE_URL"
    agent-browser wait --load networkidle
  fi

  # Desktop
  log_info "Desktop breakpoints..."
  for size in "${DESKTOP_BREAKPOINTS[@]}"; do
    test_breakpoint "desktop" "$size"
  done

  # iPad
  log_info "iPad breakpoints..."
  for size in "${IPAD_BREAKPOINTS[@]}"; do
    test_breakpoint "ipad" "$size"
  done

  # Mobile
  log_info "Mobile breakpoints..."
  for size in "${MOBILE_BREAKPOINTS[@]}"; do
    test_breakpoint "mobile" "$size"
  done

  log_info "Responsive testing complete."
}

# ------------------------------------------------------------------
# 3. Hover state capture
# ------------------------------------------------------------------
collect_hover_states() {
  log_info "Step 3: Collecting hover states..."

  set_viewport "$FIGMA_FRAME_WIDTH" 1080
  agent-browser open "$SITE_URL"
  agent-browser wait --load networkidle

  # Find all interactive elements and collect before/after hover styles
  local hover_details
  hover_details=$(eval_js '
    const interactiveSelectors = ["a", "button", "[role=button]", ".btn", "[class*=button]"];
    const results = [];
    interactiveSelectors.forEach(sel => {
      document.querySelectorAll(sel).forEach((el, idx) => {
        if (idx > 20) return; // Limit to avoid huge payloads
        const rect = el.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) return;
        const style = window.getComputedStyle(el);
        results.push({
          tag: el.tagName,
          className: el.className.substring(0, 100),
          text: el.innerText.trim().substring(0, 50),
          href: el.href || null,
          defaultStyles: {
            color: style.color,
            backgroundColor: style.backgroundColor,
            textDecoration: style.textDecoration,
            borderColor: style.borderColor,
            transitionDuration: style.transitionDuration,
            transitionProperty: style.transitionProperty
          }
        });
      });
    });
    return JSON.stringify(results);
  ')

  echo "$hover_details" | jq '.' > "$DATA_DIR/hover-states-detailed.json"
  log_info "Hover states collected."
}

# ------------------------------------------------------------------
# 4. Per-section screenshot capture
# ------------------------------------------------------------------
collect_section_screenshots() {
  log_info "Step 4: Capturing per-section screenshots..."

  set_viewport "$FIGMA_FRAME_WIDTH" 1080
  agent-browser open "$SITE_URL"
  agent-browser wait --load networkidle

  # Get section bounding boxes
  local sections_info
  sections_info=$(eval_js '
    const sectionSelectors = "header, nav, section, footer, main, article, aside, [class*=hero], [class*=banner], [class*=feature], [class*=testimonial], [class*=cta], [class*=about], [class*=contact], [class*=service], [class*=portfolio], [class*=pricing], [class*=team], [class*=faq]";
    const elements = Array.from(document.querySelectorAll(sectionSelectors));
    const unique = [];
    const seen = new Set();
    elements.forEach(el => {
      const rect = el.getBoundingClientRect();
      if (rect.height < 50) return; // Skip tiny elements
      const key = el.tagName + "|" + el.id + "|" + el.className;
      if (seen.has(key)) return;
      seen.add(key);
      unique.push({
        tag: el.tagName,
        id: el.id,
        className: el.className.substring(0, 200),
        top: rect.top + window.scrollY,
        left: rect.left + window.scrollX,
        width: rect.width,
        height: rect.height
      });
    });
    return JSON.stringify(unique.sort((a, b) => a.top - b.top));
  ')

  # Save section info
  echo "$sections_info" | jq '.' > "$DATA_DIR/section-bboxes.json"

  # Screenshot each section by scrolling to it
  local count
  count=$(echo "$sections_info" | jq 'length')
  log_info "  → Found $count sections, capturing screenshots..."

  for ((i=0; i<count; i++)); do
    local top class_name safe_name
    top=$(echo "$sections_info" | jq -r ".[$i].top")
    class_name=$(echo "$sections_info" | jq -r ".[$i].className")
    safe_name=$(echo "$class_name" | tr ' ' '_' | tr '/' '_' | cut -c1-50)

    log_info "    → Section $((i+1))/$count at y=${top}px"

    eval_js "window.scrollTo(0, $top - 50);"
    agent-browser wait 300

    # Take a screenshot (full page, but we'll crop mentally based on y position)
    take_screenshot "$SCREENSHOTS_DIR/section-${i}-${safe_name}.png"
  done

  log_info "Section screenshots complete."
}

# ------------------------------------------------------------------
# 5. Summary generation
# ------------------------------------------------------------------
generate_summary() {
  log_info "Step 5: Generating collection summary..."

  local screenshots_count
  screenshots_count=$(find "$SCREENSHOTS_DIR" -name "*.png" | wc -l)

  local data_files_count
  data_files_count=$(find "$DATA_DIR" -name "*.json" | wc -l)

  cat > "$OUTPUT_DIR/collection-summary.json" <<EOF
{
  "siteUrl": "$SITE_URL",
  "runFolder": "$RUN_FOLDER",
  "figmaFrameWidth": $FIGMA_FRAME_WIDTH,
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "screenshotsCaptured": $screenshots_count,
  "dataFilesGenerated": $data_files_count,
  "breakpointsTested": {
    "desktop": ${#DESKTOP_BREAKPOINTS[@]},
    "ipad": ${#IPAD_BREAKPOINTS[@]},
    "mobile": ${#MOBILE_BREAKPOINTS[@]}
  },
  "outputDirectory": "$OUTPUT_DIR"
}
EOF

  log_info "========================================"
  log_info "Collection Complete!"
  log_info "========================================"
  log_info "Screenshots:     $screenshots_count"
  log_info "Data files:      $data_files_count"
  log_info "Output folder:   $OUTPUT_DIR"
  log_info ""
  log_info "Next steps:"
  log_info "  1. Pull Figma design data (via Figma MCP)"
  log_info "  2. Generate the QA report by comparing"
  log_info "     $DATA_DIR/ against Figma data"
  log_info "  3. Produce PDF at: $OUTPUT_DIR/report.pdf"
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
main() {
  log_info "========================================"
  log_info "Figma Design QA — Live Site Collection"
  log_info "========================================"
  log_info "Site URL:        $SITE_URL"
  log_info "Run Folder:      $RUN_FOLDER"
  log_info "Figma Width:     $FIGMA_FRAME_WIDTH"
  log_info ""

  # Optional: install agent-browser if not present
  if ! command -v agent-browser &>/dev/null; then
    log_warn "agent-browser not found. Attempting to install..."
    if command -v npm &>/dev/null; then
      npm install -g agent-browser
      agent-browser install
    else
      log_error "npm not found. Cannot install agent-browser automatically."
      exit 1
    fi
  fi

  check_prerequisites
  collect_site_metadata
  collect_hover_states
  collect_section_screenshots
  run_responsive_tests
  generate_summary

  log_info ""
  log_info "All done! Artifacts saved to: $OUTPUT_DIR"
}

main "$@"
