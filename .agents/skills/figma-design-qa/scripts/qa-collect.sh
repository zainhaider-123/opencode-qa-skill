#!/usr/bin/env bash
# QA Data Collection Script for figma-design-qa using agent-browser
# Usage: ./qa-collect.sh <site-url> [output-directory]
set -euo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  echo "Usage: $0 <site-url> [output-directory]"
  echo "Example: $0 https://dev.webnhubs.com/laura-couture/"
  exit 1
fi

# Derive output directory
SITE_SLUG=$(echo "$URL" | sed -E 's|https?://||; s|/.*||; s|www\.||')
TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
OUTDIR="${2:-./figma-design-qa-reports/${TIMESTAMP}_${SITE_SLUG}}"
mkdir -p "$OUTDIR/screenshots" "$OUTDIR/data"

echo "=== QA Collection Start ==="
echo "Site: $URL"
echo "Output: $OUTDIR"

# ── Utility helpers ─────────────────────────────────────────────────
# Run JS in the browser and write result (raw stdout) to a file.
_eval_to_file() {
  local out="$1"
  agent-browser --session "$SESSION_NAME" eval --stdin > "$out"
}

# Check if agent-browser binary is available
if ! command -v agent-browser &> /dev/null; then
  echo "ERROR: agent-browser not found. Install with: npm i -g agent-browser && agent-browser install"
  exit 1
fi

SESSION_NAME="qa-collect-$(date +%s)"

# ── Step 0: Clean any hung sessions ─────────────────────────────────
echo "Cleaning up any existing sessions..."
agent-browser close --all 2>/dev/null || true

# ── Step 1: Open the page ────────────────────────────────────────────
echo ""
echo "[1/4] Opening site at 1920x1080..."
agent-browser --session "$SESSION_NAME" open "$URL"
agent-browser --session "$SESSION_NAME" wait --load networkidle
agent-browser --session "$SESSION_NAME" set viewport 1920 1080

# Scroll to bottom to trigger all lazy-loads and entrance animations
echo "        Scrolling to bottom to trigger lazy content..."
cat <<'SCROLL' | agent-browser --session "$SESSION_NAME" eval --stdin
(function () {
  let scrollTop = 0;
  const step = window.innerHeight;
  const maxScroll = document.body.scrollHeight;
  while (scrollTop < maxScroll) {
    scrollTop += step;
    window.scrollTo(0, scrollTop);
  }
  return { scrolledTo: scrollTop, bodyHeight: document.body.scrollHeight };
})();
SCROLL
agent-browser --session "$SESSION_NAME" wait 2000  # allow animations to settle after scroll

# ── Step 2: Site-wide checks (run once at desktop width) ────────────
echo "[2/4] Collecting site-wide data..."

cat <<'EOF' | _eval_to_file "$OUTDIR/data/site-wide-raw.txt"
(function () {
  function getSelector(el) {
    if (!el || el === document.body || el === document.documentElement) return el ? el.tagName.toLowerCase() : '';
    if (el.id) return '#' + el.id;
    var parts = [];
    var c = el;
    while (c && c !== document.body && c !== document.documentElement && c.nodeType === 1) {
      var s = c.tagName.toLowerCase();
      if (c.id) { s = '#' + c.id; parts.unshift(s); break; }
      if (c.className && typeof c.className === 'string') {
        var cls = c.className.trim().replace(/\s+/g, '.');
        if (cls) s += '.' + cls;
      }
      var p = c.parentElement;
      if (p) {
        var siblings = Array.from(p.children).filter(function(x) { return x.tagName === c.tagName; });
        if (siblings.length > 1) s += ':nth-of-type(' + (siblings.indexOf(c) + 1) + ')';
      }
      parts.unshift(s);
      c = c.parentElement;
    }
    return parts.join(' > ');
  }
  function getXPath(el) {
    if (!el || el.nodeType !== 1) return '';
    if (el.id) return '//*[@id="' + el.id + '"]';
    var parts = [];
    var c = el;
    while (c && c !== document.body && c !== document.documentElement && c.nodeType === 1) {
      var tag = c.tagName.toLowerCase();
      var idx = 1;
      var sib = c.previousElementSibling;
      while (sib) {
        if (sib.tagName === c.tagName) idx++;
        sib = sib.previousElementSibling;
      }
      parts.unshift(tag + '[' + idx + ']');
      c = c.parentElement;
    }
    return '//' + parts.join('/');
  }
  function getSectionLabel(el) {
    var h = el.querySelector('h1,h2,h3,h4,h5,h6');
    if (h && h.innerText.trim()) return h.innerText.trim().substring(0, 60);
    var lbl = el.getAttribute('aria-label') || el.getAttribute('data-label') || el.getAttribute('title');
    if (lbl) return lbl.substring(0, 60);
    var txt = el.innerText.trim();
    if (txt) { var words = txt.split(/\s+/).slice(0, 5); return words.join(' ') + (txt.split(/\s+/).length > 5 ? '\u2026' : ''); }
    return el.className ? el.className.split(' ')[0].substring(0, 40) : el.tagName.toLowerCase();
  }
  const results = {
    title: document.title,
    url: window.location.href,
    headings: Array.from(document.querySelectorAll('h1,h2,h3,h4,h5,h6')).map(h => ({
      tag: h.tagName,
      text: h.innerText.trim(),
      fontSize: getComputedStyle(h).fontSize,
      color: getComputedStyle(h).color,
      selector: getSelector(h),
      xpath: getXPath(h)
    })),
    images: Array.from(document.images).map(img => ({
      src: img.src,
      naturalWidth: img.naturalWidth,
      naturalHeight: img.naturalHeight,
      alt: img.alt,
      visible: !!(img.offsetWidth || img.offsetHeight || img.getClientRects().length),
      selector: getSelector(img),
      xpath: getXPath(img)
    })),
    links: Array.from(document.querySelectorAll('a')).map(a => ({
      href: a.getAttribute('href'),
      text: a.innerText.trim(),
      isEmpty: !a.getAttribute('href') || a.getAttribute('href') === '',
      isPlaceholder: a.getAttribute('href') === '#',
      selector: getSelector(a),
      xpath: getXPath(a)
    })),
    favicon: (function () {
      const link = document.querySelector('link[rel~="icon"]');
      return link ? link.href : null;
    })()
  };

  // Check heading size descending rule: h1 > h2 > h3 > h4 > h5 > h6
  const sizes = {};
  results.headings.forEach(h => {
    const px = parseFloat(h.fontSize);
    if (!isNaN(px) && !sizes[h.tag]) sizes[h.tag] = px;
  });
  const order = ['H1','H2','H3','H4','H5','H6'];
  let lastSize = Infinity;
  let inversion = null;
  for (const tag of order) {
    if (sizes[tag] !== undefined) {
      if (sizes[tag] > lastSize) {
        inversion = { tag, size: sizes[tag], previousSize: lastSize };
        break;
      }
      lastSize = sizes[tag];
    }
  }
  results.headingInversion = inversion;

  // Detect broken images (0x0 natural dimensions = likely broken)
  results.brokenImages = results.images.filter(i => i.naturalWidth === 0 && i.naturalHeight === 0 && i.src && !i.src.endsWith('.svg'));

  // Check link hover transition via first <a> with an href
  const sampleLink = document.querySelector('a[href]:not([href="#"])');
  if (sampleLink) {
    const styles = getComputedStyle(sampleLink);
    results.linkTransition = styles.transitionDuration;
  } else {
    results.linkTransition = null;
  }

  // Detect overflow / hidden elements
  const overflows = [];
  document.querySelectorAll('*').forEach(el => {
    const rect = el.getBoundingClientRect();
    const computed = getComputedStyle(el);
    if (rect.width > window.innerWidth && computed.overflowX !== 'hidden' && computed.position !== 'fixed' && computed.position !== 'absolute') {
      overflows.push({ tag: el.tagName, class: el.className, width: rect.width, innerWidth: window.innerWidth, selector: getSelector(el), xpath: getXPath(el) });
    }
  });
  results.overflows = overflows.slice(0, 50); // cap

  // Section boundaries (heuristic: top-level sections, large divs, or common container classes)
  const sections = [];
  const candidates = document.querySelectorAll('section, [class*="section"], [class*="hero"], [class*="header"], [class*="footer"], [class*="testimonial"], [class*="feature"]');
  candidates.forEach((el, idx) => {
    const rect = el.getBoundingClientRect();
    if (rect.height > 50) {
      sections.push({
        index: idx,
        tag: el.tagName,
        class: el.className.substring(0, 100),
        top: Math.round(rect.top),
        height: Math.round(rect.height),
        width: Math.round(rect.width),
        textPreview: el.innerText.trim().substring(0, 150).replace(/\s+/g, ' '),
        selector: getSelector(el),
        xpath: getXPath(el),
        label: getSectionLabel(el)
      });
    }
  });
  results.sections = sections;

  return results;
})();
EOF

# Verify raw file has content
if [ ! -s "$OUTDIR/data/site-wide-raw.txt" ]; then
  echo "WARNING: site-wide eval produced no output"
fi

# Save a copy as JSON if the first line looks like JSON
head -c 1 "$OUTDIR/data/site-wide-raw.txt" | grep -q '^[\[{]' && \
  cp "$OUTDIR/data/site-wide-raw.txt" "$OUTDIR/data/site-wide.json" || \
  echo "WARNING: site-wide output is not JSON"

# ── Step 3: Responsive screenshots & breakpoint checks ───────────────
echo "[3/4] Testing responsive breakpoints..."

BREAKPOINTS=(
  "1280x720:desktop"
  "1366x768:desktop"
  "1400x900:desktop"
  "1440x900:desktop"
  "1536x864:desktop"
  "1600x900:desktop"
  "1680x1050:desktop"
  "1792x1120:desktop"
  "1920x1080:desktop"
  "2048x1536:desktop"
  "2560x1440:desktop"
  "768x1024:ipad"
  "810x1180:ipad"
  "1024x1366:ipad"
  "360x740:mobile"
  "412x915:mobile"
  "430x932:mobile"
  "375x740:mobile"
)

for bp in "${BREAKPOINTS[@]}"; do
  IFS=':' read -r dims category <<< "$bp"
  IFS='x' read -r w h <<< "$dims"

  echo "  → $dims ($category)"
  agent-browser --session "$SESSION_NAME" set viewport "$w" "$h"
  agent-browser --session "$SESSION_NAME" wait 1500  # allow responsive CSS and entrance animations to settle

  # Scroll to bottom at this breakpoint to trigger all lazy-loads and entrance animations
  cat <<'SCROLL' | agent-browser --session "$SESSION_NAME" eval --stdin
(function () {
  let scrollTop = 0;
  const step = window.innerHeight || 800;
  const maxScroll = document.body.scrollHeight;
  while (scrollTop < maxScroll) {
    scrollTop += step;
    window.scrollTo(0, scrollTop);
  }
  return { scrolledTo: scrollTop, bodyHeight: maxScroll };
})();
SCROLL
  agent-browser --session "$SESSION_NAME" wait 1500

  # Screenshot (full page)
  agent-browser --session "$SESSION_NAME" screenshot --full "$OUTDIR/screenshots/${dims}.png"

  # Collect breakpoint-specific data
  cat <<EOF | _eval_to_file "$OUTDIR/data/bp-${dims}-raw.txt"
(function () {
  function getSelector(el) {
    if (!el || el === document.body || el === document.documentElement) return el ? el.tagName.toLowerCase() : '';
    if (el.id) return '#' + el.id;
    var parts = [];
    var c = el;
    while (c && c !== document.body && c !== document.documentElement && c.nodeType === 1) {
      var s = c.tagName.toLowerCase();
      if (c.id) { s = '#' + c.id; parts.unshift(s); break; }
      if (c.className && typeof c.className === 'string') {
        var cls = c.className.trim().replace(/\s+/g, '.');
        if (cls) s += '.' + cls;
      }
      var p = c.parentElement;
      if (p) {
        var siblings = Array.from(p.children).filter(function(x) { return x.tagName === c.tagName; });
        if (siblings.length > 1) s += ':nth-of-type(' + (siblings.indexOf(c) + 1) + ')';
      }
      parts.unshift(s);
      c = c.parentElement;
    }
    return parts.join(' > ');
  }
  function getXPath(el) {
    if (!el || el.nodeType !== 1) return '';
    if (el.id) return '//*[@id="' + el.id + '"]';
    var parts = [];
    var c = el;
    while (c && c !== document.body && c !== document.documentElement && c.nodeType === 1) {
      var tag = c.tagName.toLowerCase();
      var idx2 = 1;
      var sib = c.previousElementSibling;
      while (sib) {
        if (sib.tagName === c.tagName) idx2++;
        sib = sib.previousElementSibling;
      }
      parts.unshift(tag + '[' + idx2 + ']');
      c = c.parentElement;
    }
    return '//' + parts.join('/');
  }
  function getSectionLabel(el) {
    var h = el.querySelector('h1,h2,h3,h4,h5,h6');
    if (h && h.innerText.trim()) return h.innerText.trim().substring(0, 60);
    var lbl = el.getAttribute('aria-label') || el.getAttribute('data-label') || el.getAttribute('title');
    if (lbl) return lbl.substring(0, 60);
    var txt = el.innerText.trim();
    if (txt) { var words = txt.split(/\s+/).slice(0, 5); return words.join(' ') + (txt.split(/\s+/).length > 5 ? '\u2026' : ''); }
    return el.className ? el.className.split(' ')[0].substring(0, 40) : el.tagName.toLowerCase();
  }
  function findParentSection(el) {
    var sectionSelectors = ['section', '[class*="hero"]', '[class*="section"]', '[class*="header"]', '[class*="footer"]', '[class*="feature"]', '[class*="testimonial"]'];
    var current = el.parentElement;
    while (current && current !== document.body && current !== document.documentElement) {
      for (var i = 0; i < sectionSelectors.length; i++) {
        if (current.matches && current.matches(sectionSelectors[i])) {
          return getSectionLabel(current);
        }
      }
      current = current.parentElement;
    }
    return '';
  }
  const results = {
    viewport: { width: ${w}, height: ${h}, category: '${category}', innerWidth: window.innerWidth, innerHeight: window.innerHeight },
    overflows: [],
    hiddenSections: [],
    hamburgerDetected: false,
    hamburgerLinks: [],
    sectionBounds: []
  };

  // Overflow detection (elements wider than viewport)
  document.querySelectorAll('*').forEach(el => {
    const rect = el.getBoundingClientRect();
    const computed = getComputedStyle(el);
    if (rect.width > window.innerWidth + 2 && computed.overflowX !== 'hidden' && computed.position !== 'fixed' && computed.position !== 'absolute' && el.tagName !== 'HTML' && el.tagName !== 'BODY') {
      results.overflows.push({
        tag: el.tagName,
        class: el.className.substring(0, 80),
        width: Math.round(rect.width),
        vw: window.innerWidth,
        selector: getSelector(el),
        xpath: getXPath(el),
        sectionLabel: findParentSection(el)
      });
    }
  });

  // Count unique overflow culprits, cap at 30
  const seen = new Set();
  results.overflows = results.overflows.filter(o => {
    const key = o.tag + '|' + o.class;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).slice(0, 30);

  // Section visibility: check if known major sections go off-screen or collapse to 0 height
  const sectionSelectors = ['header', 'footer', 'section', '[class*="hero"]', '[class*="section"]', '[class*="feature"]', '[class*="testimonial"]'];
  sectionSelectors.forEach(sel => {
    document.querySelectorAll(sel).forEach(el => {
      const rect = el.getBoundingClientRect();
      if (rect.height === 0) {
        results.hiddenSections.push({ selector: sel, class: el.className.substring(0, 80), elementSelector: getSelector(el), xpath: getXPath(el), label: getSectionLabel(el) });
      }
    });
  });

  // Hamburger detection (mobile only)
  if ('${category}' === 'mobile') {
    const hamburgerSelectors = [
      'button[class*="hamburger"]',
      'button[class*="menu"]',
      '[class*="hamburger"]',
      '[class*="navbar-toggler"]',
      '[aria-label*="menu"]',
      'button:has(.bar)',
      '[class*="toggle"]'
    ];
    for (const sel of hamburgerSelectors) {
      const btn = document.querySelector(sel);
      if (btn && btn.offsetParent !== null) {
        results.hamburgerDetected = true;
        btn.click();
        // Allow menu to open
        const start = Date.now();
        while (Date.now() - start < 500) { /* spin briefly */ }
        const navLinks = document.querySelectorAll('nav a, [class*="menu"] a, [class*="nav"] a, .mobile-menu a');
        results.hamburgerLinks = Array.from(navLinks).map(a => a.innerText.trim()).filter(Boolean);
        break;
      }
    }
  }

  return results;
})();
EOF

  # Save as JSON if valid
  head -c 1 "$OUTDIR/data/bp-${dims}-raw.txt" | grep -q '^[\[{]' && \
    cp "$OUTDIR/data/bp-${dims}-raw.txt" "$OUTDIR/data/bp-${dims}.json" || \
    echo "    WARNING: bp-${dims} output is not JSON"
done

# ── Step 4: Close browser ──────────────────────────────────────────
echo "[4/4] Closing browser..."
agent-browser --session "$SESSION_NAME" close 2>/dev/null || true
agent-browser close --all 2>/dev/null || true

echo ""
echo "=== QA Collection Complete ==="
echo "Raw data saved to: $OUTDIR/data/"
echo "Screenshots saved to: $OUTDIR/screenshots/"
echo ""
echo "Next step: run a report generator to produce report.html → report.pdf"
