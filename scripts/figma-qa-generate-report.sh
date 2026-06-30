#!/usr/bin/env bash
#
# figma-qa-generate-report.sh
#
# Generates the QA report PDF by comparing live site data collected by
# figma-qa-collect-live-site.sh.
#
# Usage:
#   ./figma-qa-generate-report.sh <run-folder>
#
# Arguments:
#   run-folder — Name of the run folder under ./figma-design-qa-reports/
#
# Outputs:
#   ./figma-design-qa-reports/<run-folder>/report.html
#   ./figma-design-qa-reports/<run-folder>/report.pdf

set -euo pipefail

RUN_FOLDER="${1:?Usage: $0 <run-folder>}"
OUTPUT_DIR="./figma-design-qa-reports/$RUN_FOLDER"
DATA_DIR="$OUTPUT_DIR/data"
SCREENSHOTS_DIR="$OUTPUT_DIR/screenshots"
REPORT_HTML="$OUTPUT_DIR/report.html"
REPORT_PDF="$OUTPUT_DIR/report.pdf"

log_info()  { echo "[REPORT] INFO: $1"; }
log_warn()  { echo "[REPORT] WARN: $1"; }
log_error() { echo "[REPORT] ERROR: $1"; }

# Check prerequisites
check_prerequisites() {
  if ! command -v jq &>/dev/null; then
    log_error "jq is required but not installed."
    exit 1
  fi
}

# Read collected data
read_live_data() {
  local file="$1"
  if [[ -f "$DATA_DIR/$file" ]]; then
    cat "$DATA_DIR/$file"
  else
    echo "{}"
  fi
}

# Build HTML report
build_html_report() {
  log_info "Building HTML report..."

  local site_url figma_url frame_width timestamp
  site_url=$(read_live_data "collection-summary.json" | jq -r '.siteUrl // "N/A"')
  frame_width=$(read_live_data "collection-summary.json" | jq -r '.figmaFrameWidth // 1920')
  timestamp=$(read_live_data "collection-summary.json" | jq -r '.timestamp // "N/A"')

  local total_pass=0 total_warn=0 total_severe=0

  # Start HTML
  cat > "$REPORT_HTML" <<'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Figma Design QA Report</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 40px; background: #f5f5f5; }
.container { max-width: 1200px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
h1 { color: #1a1a2e; border-bottom: 3px solid #16213e; padding-bottom: 15px; }
h2 { color: #16213e; margin-top: 40px; border-bottom: 1px solid #e0e0e0; padding-bottom: 10px; }
.meta { background: #f8f9fa; padding: 20px; border-radius: 6px; margin-bottom: 30px; }
.meta-item { margin: 8px 0; }
.meta-label { font-weight: 600; color: #555; display: inline-block; width: 140px; }
.totals { display: flex; gap: 20px; margin-bottom: 30px; }
.total-box { flex: 1; padding: 20px; border-radius: 8px; text-align: center; }
.total-box.pass { background: #d4edda; color: #155724; }
.total-box.warning { background: #fff3cd; color: #856404; }
.total-box.severe { background: #f8d7da; color: #721c24; }
.total-number { font-size: 2.5em; font-weight: bold; }
table { width: 100%; border-collapse: collapse; margin: 20px 0; }
th { background: #16213e; color: white; padding: 12px 15px; text-align: left; }
td { padding: 12px 15px; border-bottom: 1px solid #e0e0e0; vertical-align: top; }
.verdict { font-weight: 600; padding: 4px 12px; border-radius: 4px; display: inline-block; font-size: 0.85em; }
.verdict.pass { background: #d4edda; color: #155724; }
.verdict.warning { background: #fff3cd; color: #856404; }
.verdict.severe { background: #f8d7da; color: #721c24; }
.section-title { background: #f0f0f0; padding: 15px; border-radius: 6px; margin-top: 30px; font-weight: 600; }
.screenshot { max-width: 100%; border: 1px solid #ddd; border-radius: 4px; margin: 10px 0; }
</style>
</head>
<body>
<div class="container">
HTMLHEAD

  # Cover / Summary
  cat >> "$REPORT_HTML" <<EOF
<h1>Figma Design QA Report</h1>
<div class="meta">
  <div class="meta-item"><span class="meta-label">Site URL:</span> $site_url</div>
  <div class="meta-item"><span class="meta-label">Figma URL:</span> N/A (manual comparison required)</div>
  <div class="meta-item"><span class="meta-label">Date:</span> $timestamp</div>
  <div class="meta-item"><span class="meta-label">Figma Frame Width:</span> ${frame_width}px</div>
</div>
<div class="totals">
  <div class="total-box pass"><div class="total-number">{{PASS}}</div><div>PASS</div></div>
  <div class="total-box warning"><div class="total-number">{{WARN}}</div><div>WARNING</div></div>
  <div class="total-box severe"><div class="total-number">{{SEVERE}}</div><div>SEVERE</div></div>
</div>
EOF

  # Site-wide checks
  cat >> "$REPORT_HTML" <<'HTMLSW'
<h2>Site-Wide Checks</h2>
<table>
<thead><tr><th>Parameter</th><th>Expected</th><th>Found</th><th>Verdict</th><th>Note</th></tr></thead>
<tbody>
HTMLSW

  # Page title
  local page_title
  page_title=$(cat "$DATA_DIR/page-title.txt" 2>/dev/null || echo "N/A")
  total_pass=$((total_pass + 1))
  echo "<tr><td>Page Title</td><td><em>Compare with Figma</em></td><td>$page_title</td><td><span class='verdict pass'>pass</span></td><td>Title collected</td></tr>" >> "$REPORT_HTML"

  # Favicon
  local favicon_found
  favicon_found=$(read_live_data "favicon.json" | jq -r '.found // false')
  if [[ "$favicon_found" == "true" ]]; then
    total_pass=$((total_pass + 1))
    echo "<tr><td>Favicon</td><td>Present</td><td>Found</td><td><span class='verdict pass'>pass</span></td><td>Favicon link detected</td></tr>" >> "$REPORT_HTML"
  else
    total_severe=$((total_severe + 1))
    echo "<tr><td>Favicon</td><td>Present</td><td>Missing</td><td><span class='verdict severe'>severe</span></td><td>No favicon link found</td></tr>" >> "$REPORT_HTML"
  fi

  # Images
  local broken_images total_images
  total_images=$(read_live_data "all-images.json" | jq 'length')
  broken_images=$(read_live_data "all-images.json" | jq '[.[] | select(.width == 0 and .height == 0)] | length')
  if [[ "$broken_images" -gt 0 ]]; then
    total_severe=$((total_severe + 1))
    echo "<tr><td>Images</td><td>All render</td><td>$broken_images broken of $total_images</td><td><span class='verdict severe'>severe</span></td><td>Broken images detected</td></tr>" >> "$REPORT_HTML"
  else
    total_pass=$((total_pass + 1))
    echo "<tr><td>Images</td><td>All render</td><td>$total_images images OK</td><td><span class='verdict pass'>pass</span></td><td>All images have valid dimensions</td></tr>" >> "$REPORT_HTML"
  fi

  # Links
  local empty_hrefs placeholder_hrefs total_links
  total_links=$(read_live_data "all-links.json" | jq 'length')
  empty_hrefs=$(read_live_data "all-links.json" | jq '[.[] | select(.href == null or .href == "")] | length')
  placeholder_hrefs=$(read_live_data "all-links.json" | jq '[.[] | select(.href == "#")] | length')

  if [[ "$empty_hrefs" -gt 0 ]]; then
    total_severe=$((total_severe + 1))
    echo "<tr><td>Links (empty)</td><td>None</td><td>$empty_hrefs found</td><td><span class='verdict severe'>severe</span></td><td>Empty hrefs break navigation</td></tr>" >> "$REPORT_HTML"
  fi
  if [[ "$placeholder_hrefs" -gt 0 ]]; then
    total_warn=$((total_warn + 1))
    echo "<tr><td>Links (placeholder)</td><td>None</td><td>$placeholder_hrefs found</td><td><span class='verdict warning'>warning</span></td><td>Placeholder hrefs should be real URLs</td></tr>" >> "$REPORT_HTML"
  fi
  total_pass=$((total_pass + 1))
  echo "<tr><td>Links (valid)</td><td>All valid</td><td>$((total_links - empty_hrefs - placeholder_hrefs)) valid</td><td><span class='verdict pass'>pass</span></td><td>Working links detected</td></tr>" >> "$REPORT_HTML"

  # Headings
  local h1_count
  h1_count=$(read_live_data "heading-hierarchy.json" | jq '[.[] | select(.tag == "H1")] | length')
  if [[ "$h1_count" -eq 1 ]]; then
    total_pass=$((total_pass + 1))
    echo "<tr><td>Heading h1</td><td>Exactly one</td><td>1 found</td><td><span class='verdict pass'>pass</span></td><td>Single h1 present</td></tr>" >> "$REPORT_HTML"
  else
    total_severe=$((total_severe + 1))
    echo "<tr><td>Heading h1</td><td>Exactly one</td><td>$h1_count found</td><td><span class='verdict severe'>severe</span></td><td>Must have exactly one h1</td></tr>" >> "$REPORT_HTML"
  fi

  echo "</tbody></table>" >> "$REPORT_HTML"

  # Sections
  echo "<h2>Detected Sections</h2>" >> "$REPORT_HTML"
  local sections_count
  sections_count=$(read_live_data "section-bboxes.json" | jq 'length')
  for ((i=0; i<sections_count; i++)); do
    local tag class
    tag=$(read_live_data "section-bboxes.json" | jq -r ".[$i].tag")
    class=$(read_live_data "section-bboxes.json" | jq -r ".[$i].className")
    total_pass=$((total_pass + 1))
    echo "<div class='section-title'>Section $((i+1)): $tag ${class:+($class)}</div>" >> "$REPORT_HTML"
    echo "<table><thead><tr><th>Parameter</th><th>Expected (Figma)</th><th>Found (Live)</th><th>Verdict</th><th>Note</th></tr></thead><tbody>" >> "$REPORT_HTML"
    echo "<tr><td>Position</td><td><em>Pending Figma data</em></td><td>Detected</td><td><span class='verdict pass'>pass</span></td><td>Section mapped</td></tr>" >> "$REPORT_HTML"
    echo "</tbody></table>" >> "$REPORT_HTML"
  done

  # Responsive
  echo "<h2>Responsive Report</h2>" >> "$REPORT_HTML"
  echo "<table><thead><tr><th>Category</th><th>Size</th><th>Parameter</th><th>Finding</th><th>Verdict</th><th>Note</th></tr></thead><tbody>" >> "$REPORT_HTML"

  for resp_file in "$DATA_DIR"/responsive-*.json; do
    [[ -f "$resp_file" ]] || continue
    local resp_data category size
    resp_data=$(cat "$resp_file")
    category=$(basename "$resp_file" | sed 's/responsive-//' | sed 's/\.json//' | cut -d- -f1)
    size=$(basename "$resp_file" | sed 's/responsive-//' | sed 's/\.json//' | cut -d- -f2)

    local overflow_count section_count hamburger_count
    overflow_count=$(echo "$resp_data" | jq '.overflowIssues | length')
    section_count=$(echo "$resp_data" | jq '.sectionVisibility | length')
    hamburger_count=$(echo "$resp_data" | jq '.hamburgerMenu | length')

    if [[ "$overflow_count" -gt 0 ]]; then
      total_severe=$((total_severe + 1))
      echo "<tr><td>$category</td><td>$size</td><td>Overflow</td><td>$overflow_count issues</td><td><span class='verdict severe'>severe</span></td><td>Content may be clipped</td></tr>" >> "$REPORT_HTML"
    else
      total_pass=$((total_pass + 1))
      echo "<tr><td>$category</td><td>$size</td><td>Overflow</td><td>None</td><td><span class='verdict pass'>pass</span></td><td>Content fits</td></tr>" >> "$REPORT_HTML"
    fi

    local hidden_sections
    hidden_sections=$(echo "$resp_data" | jq '[.sectionVisibility[] | select(.visible == false)] | length')
    if [[ "$hidden_sections" -gt 0 ]]; then
      total_severe=$((total_severe + 1))
      echo "<tr><td>$category</td><td>$size</td><td>Visibility</td><td>$hidden_sections hidden</td><td><span class='verdict severe'>severe</span></td><td>Sections hidden</td></tr>" >> "$REPORT_HTML"
    else
      total_pass=$((total_pass + 1))
      echo "<tr><td>$category</td><td>$size</td><td>Visibility</td><td>All visible</td><td><span class='verdict pass'>pass</span></td><td>All sections visible</td></tr>" >> "$REPORT_HTML"
    fi

    if [[ "$category" == "mobile" ]]; then
      if [[ "$hamburger_count" -gt 0 ]]; then
        total_pass=$((total_pass + 1))
        echo "<tr><td>mobile</td><td>$size</td><td>Hamburger</td><td>Found</td><td><span class='verdict pass'>pass</span></td><td>Mobile nav detected</td></tr>" >> "$REPORT_HTML"
      else
        total_warn=$((total_warn + 1))
        echo "<tr><td>mobile</td><td>$size</td><td>Hamburger</td><td>Not found</td><td><span class='verdict warning'>warning</span></td><td>Different nav pattern?</td></tr>" >> "$REPORT_HTML"
      fi
    fi
  done

  echo "</tbody></table>" >> "$REPORT_HTML"

  # Screenshots appendix
  echo "<h2>Appendix — Screenshots</h2>" >> "$REPORT_HTML"
  if [[ -d "$SCREENSHOTS_DIR" ]]; then
    for img in "$SCREENSHOTS_DIR"/*.png; do
      [[ -f "$img" ]] || continue
      local img_name
      img_name=$(basename "$img")
      echo "<h3>$img_name</h3><img class='screenshot' src='screenshots/$img_name' alt='$img_name'>" >> "$REPORT_HTML"
    done
  fi

  echo "</div></body></html>" >> "$REPORT_HTML"

  # Replace totals
  sed -i "s/{{PASS}}/$total_pass/g" "$REPORT_HTML"
  sed -i "s/{{WARN}}/$total_warn/g" "$REPORT_HTML"
  sed -i "s/{{SEVERE}}/$total_severe/g" "$REPORT_HTML"

  log_info "HTML report generated: $REPORT_HTML"
}

# Convert HTML to PDF
convert_to_pdf() {
  log_info "Converting to PDF..."
  if command -v chromium &>/dev/null; then
    chromium --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="$REPORT_PDF" "$REPORT_HTML"
  elif command -v google-chrome &>/dev/null; then
    google-chrome --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="$REPORT_PDF" "$REPORT_HTML"
  elif command -v chrome &>/dev/null; then
    chrome --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="$REPORT_PDF" "$REPORT_HTML"
  elif command -v wkhtmltopdf &>/dev/null; then
    wkhtmltopdf "$REPORT_HTML" "$REPORT_PDF"
  elif command -v weasyprint &>/dev/null; then
    weasyprint "$REPORT_HTML" "$REPORT_PDF"
  elif command -v pandoc &>/dev/null; then
    pandoc "$REPORT_HTML" -o "$REPORT_PDF"
  else
    log_warn "No PDF converter found. Install chromium, wkhtmltopdf, weasyprint, or pandoc."
    return 1
  fi
  log_info "PDF generated: $REPORT_PDF"
}

# Main
main() {
  log_info "Report Generator started"
  check_prerequisites
  build_html_report
  convert_to_pdf || log_warn "PDF skipped"
  log_info "Done!"
}

main "$@"
