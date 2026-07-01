#!/usr/bin/env node
// QA Report Generator for figma-design-qa agent-browser collection
// Usage: node qa-generate-report.js <collection-directory>
// It reads site-wide.json and bp-*.json files, then writes report.html

const fs = require('fs');
const path = require('path');

const inputDir = process.argv[2];
if (!inputDir) {
  console.error('Usage: node qa-generate-report.js <collection-directory>');
  process.exit(1);
}

const dataDir = path.join(inputDir, 'data');
const screenshotDir = path.join(inputDir, 'screenshots');

// ── Load data ───────────────────────────────────────────────────────
function loadJSON(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}

const siteWide = loadJSON(path.join(dataDir, 'site-wide.json')) || {};
const bpFiles = fs.readdirSync(dataDir)
  .filter(f => f.startsWith('bp-') && f.endsWith('.json'))
  .sort();
const breakpoints = bpFiles.map(f => ({ file: f, data: loadJSON(path.join(dataDir, f)) }));

// ── Determine verdict helpers ─────────────────────────────────────
function verdictClass(v) {
  if (v === 'pass') return 'verdict-pass';
  if (v === 'warning') return 'verdict-warning';
  if (v === 'severe') return 'verdict-severe';
  return 'verdict-pass';
}
function verdictIcon(v) {
  if (v === 'pass') return '&#10003;';
  if (v === 'warning') return '&#9888;';
  if (v === 'severe') return '&#10007;';
  return '&#10003;';
}

// ── Severity counts ─────────────────────────────────────────────────
let severeCount = 0, warningCount = 0, passCount = 0;
function countVerdict(v) {
  if (v === 'severe') severeCount++;
  else if (v === 'warning') warningCount++;
  else if (v === 'pass') passCount++;
}

// ── Build rows ──────────────────────────────────────────────────────
let rows = [];

// Page title
const title = siteWide.title || '(not found)';
rows.push({ section: 'Page-wide', parameter: 'Page title', expected: 'From Figma design', found: title, verdict: 'pass', note: 'Check against Figma' });
countVerdict('pass');

// Favicon
const faviconOK = siteWide.favicon && siteWide.favicon.length > 0;
rows.push({ section: 'Page-wide', parameter: 'Favicon', expected: 'Present & loads', found: faviconOK ? siteWide.favicon : 'Missing', verdict: faviconOK ? 'pass' : 'severe', note: faviconOK ? '' : 'No favicon link tag found' });
countVerdict(faviconOK ? 'pass' : 'severe');

// Images
const broken = siteWide.brokenImages || [];
broken.forEach(img => {
  rows.push({ section: 'Page-wide', parameter: 'Broken image', expected: 'Image renders', found: img.src, verdict: 'severe', note: '0x0 natural dimensions' });
  countVerdict('severe');
});
if (broken.length === 0) {
  rows.push({ section: 'Page-wide', parameter: 'Images', expected: 'All render', found: 'All loaded', verdict: 'pass', note: `${(siteWide.images || []).length} images checked` });
  countVerdict('pass');
}

// Heading hierarchy
const headings = siteWide.headings || [];
const h1s = headings.filter(h => h.tag === 'H1');
if (h1s.length !== 1) {
  rows.push({ section: 'Page-wide', parameter: 'H1 count', expected: 'Exactly one', found: `${h1s.length} found`, verdict: 'severe', note: h1s.map(h => h.text).join('; ') });
  countVerdict('severe');
} else {
  rows.push({ section: 'Page-wide', parameter: 'H1 count', expected: 'Exactly one', found: h1s[0].text.substring(0,80), verdict: 'pass', note: '' });
  countVerdict('pass');
}

// Heading inversion
if (siteWide.headingInversion) {
  const inv = siteWide.headingInversion;
  rows.push({ section: 'Page-wide', parameter: 'Heading size hierarchy', expected: 'h1 > h2 > h3 > h4 > h5 > h6', found: `${inv.tag} larger than prior heading (${inv.size}px > ${inv.previousSize}px)`, verdict: 'severe', note: 'Font size inversion detected' });
  countVerdict('severe');
} else {
  rows.push({ section: 'Page-wide', parameter: 'Heading size hierarchy', expected: 'Strictly descending', found: 'Descending', verdict: 'pass', note: '' });
  countVerdict('pass');
}

// Empty headings
const emptyHeadings = headings.filter(h => !h.text || h.text.length === 0);
if (emptyHeadings.length > 0) {
  rows.push({ section: 'Page-wide', parameter: 'Empty headings', expected: 'None', found: `${emptyHeadings.length} empty (${emptyHeadings.map(h => h.tag).join(', ')})`, verdict: 'warning', note: 'Headings with no text content may be hidden icons or decorative' });
  countVerdict('warning');
} else {
  rows.push({ section: 'Page-wide', parameter: 'Empty headings', expected: 'None', found: '0', verdict: 'pass', note: '' });
  countVerdict('pass');
}

// Links
const links = siteWide.links || [];
const emptyLinks = links.filter(l => l.isEmpty);
const placeholderLinks = links.filter(l => l.isPlaceholder);
emptyLinks.forEach(l => {
  rows.push({ section: 'Page-wide', parameter: 'Link href', expected: 'Valid URL', found: `empty (${l.text.substring(0,40)})`, verdict: 'severe', note: '<a> with empty href' });
  countVerdict('severe');
});
placeholderLinks.forEach(l => {
  rows.push({ section: 'Page-wide', parameter: 'Link href', expected: 'Valid URL', found: `# (${l.text.substring(0,40)})`, verdict: 'warning', note: 'Placeholder href detected' });
  countVerdict('warning');
});
if (emptyLinks.length === 0 && placeholderLinks.length === 0) {
  rows.push({ section: 'Page-wide', parameter: 'Link hrefs', expected: 'All valid', found: `${links.length} links OK`, verdict: 'pass', note: '' });
  countVerdict('pass');
}

// Link transitions
if (siteWide.linkTransition === '0s' || !siteWide.linkTransition) {
  rows.push({ section: 'Page-wide', parameter: 'Link hover transition', expected: 'Smooth transition', found: siteWide.linkTransition || 'none', verdict: 'warning', note: 'No visible transition duration on link hover' });
  countVerdict('warning');
} else {
  rows.push({ section: 'Page-wide', parameter: 'Link hover transition', expected: 'Smooth transition', found: siteWide.linkTransition, verdict: 'pass', note: '' });
  countVerdict('pass');
}

// Sections
(siteWide.sections || []).forEach((sec, idx) => {
  rows.push({ section: `Section ${idx + 1}`, parameter: 'Section detection', expected: 'Visible container', found: `${sec.tag} ${sec.class}`, verdict: 'pass', note: `Top: ${sec.top}px, H: ${sec.height}px` });
  countVerdict('pass');
});

// ── Responsive checks ───────────────────────────────────────────────
breakpoints.forEach(bp => {
  const d = bp.data || {};
  const cat = (d.viewport && d.viewport.category) || 'unknown';
  const vw = (d.viewport && d.viewport.innerWidth) || '?';
  const vh = (d.viewport && d.viewport.innerHeight) || '?';

  // Overflow
  const overflows = d.overflows || [];
  if (overflows.length > 0) {
    const intentional = overflows.filter(o => o.class && (o.class.includes('swiper') || o.class.includes('owl') || o.class.includes('carousel') || o.class.includes('marquee')));
    const unintentional = overflows.filter(o => !intentional.includes(o));
    if (unintentional.length > 0) {
      rows.push({ section: `Responsive ${cat}`, parameter: `Overflow @ ${vw}x${vh}`, expected: 'No horizontal overflow', found: `${unintentional.length} overflowing elements`, verdict: 'severe', note: unintentional.map(o => `${o.tag}.${o.class.substring(0,40)}`).join('; ') });
      countVerdict('severe');
    } else {
      rows.push({ section: `Responsive ${cat}`, parameter: `Overflow @ ${vw}x${vh}`, expected: 'No horizontal overflow', found: `${intentional.length} intentional overflows (carousel etc.)`, verdict: 'pass', note: 'Swiper/carousel elements detected' });
      countVerdict('pass');
    }
  } else {
    rows.push({ section: `Responsive ${cat}`, parameter: `Overflow @ ${vw}x${vh}`, expected: 'No horizontal overflow', found: '0', verdict: 'pass', note: '' });
    countVerdict('pass');
  }

  // Hidden sections
  const hidden = d.hiddenSections || [];
  if (hidden.length > 0) {
    rows.push({ section: `Responsive ${cat}`, parameter: `Hidden sections @ ${vw}x${vh}`, expected: 'All sections visible', found: `${hidden.length} collapsed`, verdict: 'severe', note: hidden.map(s => s.selector).join('; ') });
    countVerdict('severe');
  }

  // Mobile hamburger
  if (cat === 'mobile') {
    if (d.hamburgerDetected) {
      rows.push({ section: `Responsive ${cat}`, parameter: `Hamburger @ ${vw}x${vh}`, expected: 'Opens with desktop nav links', found: 'Detected', verdict: 'pass', note: `Links: ${(d.hamburgerLinks || []).join(', ').substring(0,120)}` });
      countVerdict('pass');
    } else {
      rows.push({ section: `Responsive ${cat}`, parameter: `Hamburger @ ${vw}x${vh}`, expected: 'Opens with desktop nav links', found: 'Not detected', verdict: 'warning', note: 'No visible hamburger button found' });
      countVerdict('warning');
    }
  }
});

// ── HTML generation ─────────────────────────────────────────────────
const html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>QA Report</title>
<style>
body{font-family:system-ui,-apple-system,sans-serif;margin:40px;max-width:1200px;line-height:1.5;color:#222}
h1{border-bottom:3px solid #222;padding-bottom:10px}
.summary{background:#f5f5f5;padding:16px;border-radius:8px;margin-bottom:24px;display:flex;gap:32px;flex-wrap:wrap}
.summary-box{text-align:center;min-width:100px}
.summary-box .big{font-size:32px;font-weight:700}
.summary-box .label{font-size:12px;text-transform:uppercase;color:#666;letter-spacing:.05em}
table{width:100%;border-collapse:collapse;margin:24px 0;font-size:14px}
th,td{border:1px solid #ddd;padding:8px;text-align:left;vertical-align:top}
th{background:#f8f8f8}
.verdict-pass{color:#1b7b2b;font-weight:700}
.verdict-warning{color:#b87a00;font-weight:700}
.verdict-severe{color:#b71c1c;font-weight:700}
tr:nth-child(even){background:#fafafa}
.screenshots{display:flex;flex-wrap:wrap;gap:12px;margin-top:24px}
.screenshot{max-width:280px;border:1px solid #ddd;border-radius:4px}
.screenshot img{max-width:100%;display:block}
.screenshot .caption{font-size:11px;padding:6px;color:#555;text-align:center}
</style></head><body>
<h1>Figma Design QA Report</h1>
<div class="summary">
  <div class="summary-box"><div class="big">${passCount}</div><div class="label">Pass</div></div>
  <div class="summary-box"><div class="big">${warningCount}</div><div class="label">Warning</div></div>
  <div class="summary-box"><div class="big">${severeCount}</div><div class="label">Severe</div></div>
  <div class="summary-box"><div class="big">${rows.length}</div><div class="label">Checks</div></div>
</div>

<table>
<thead><tr>
<th>Section</th><th>Parameter</th><th>Expected</th><th>Found</th><th>Verdict</th><th>Note</th>
</tr></thead>
<tbody>
${rows.map(r => `<tr>
<td>${r.section}</td>
<td>${r.parameter}</td>
<td>${r.expected}</td>
<td>${r.found}</td>
<td class="${verdictClass(r.verdict)}">${verdictIcon(r.verdict)} ${r.verdict.toUpperCase()}</td>
<td>${r.note}</td>
</tr>`).join('')}
</tbody>
</table>

<h2>Screenshots</h2>
<div class="screenshots">
${breakpoints.map(bp => {
  const dims = bp.file.replace('bp-', '').replace('.json', '');
  const png = path.join(screenshotDir, `${dims}.png`);
  if (fs.existsSync(png)) {
    const rel = path.relative(inputDir, png);
    return `<div class="screenshot"><img src="${rel}" alt="${dims}"><div class="caption">${dims}</div></div>`;
  }
  return '';
}).join('')}
</div>

<p style="margin-top:40px;color:#888;font-size:12px">Generated from agent-browser collection data.<br>Directory: ${inputDir}</p>
</body></html>`;

const outHtml = path.join(inputDir, 'report.html');
fs.writeFileSync(outHtml, html);
console.log(`Report written to: ${outHtml}`);

// ── Attempt PDF conversion ──────────────────────────────────────────
function hasCmd(cmd) { try { require('child_process').execSync(`which ${cmd}`, {stdio: 'ignore'}); return true; } catch { return false; } }

const outPdf = path.join(inputDir, 'report.pdf');

if (hasCmd('agent-browser')) {
  try {
    // Open the HTML file in agent-browser and save as PDF
    const fileUrl = 'file://' + outHtml.replace(/\\/g, '/');
    require('child_process').execSync(`agent-browser --allow-file-access open "${fileUrl}"`, {stdio: 'inherit'});
    require('child_process').execSync(`agent-browser pdf "${outPdf}"`, {stdio: 'inherit'});
    console.log(`PDF written to: ${outPdf}`);
  } catch {
    console.log('agent-browser PDF generation failed. Trying fallback engines...');
  }
} else if (hasCmd('chromium')) {
  require('child_process').execSync(`chromium --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="${outPdf}" "${outHtml}"`, {stdio: 'inherit'});
  console.log(`PDF written to: ${outPdf}`);
} else if (hasCmd('google-chrome')) {
  require('child_process').execSync(`google-chrome --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="${outPdf}" "${outHtml}"`, {stdio: 'inherit'});
  console.log(`PDF written to: ${outPdf}`);
} else if (hasCmd('wkhtmltopdf')) {
  require('child_process').execSync(`wkhtmltopdf "${outHtml}" "${outPdf}"`, {stdio: 'inherit'});
  console.log(`PDF written to: ${outPdf}`);
} else if (hasCmd('weasyprint')) {
  require('child_process').execSync(`weasyprint "${outHtml}" "${outPdf}"`, {stdio: 'inherit'});
  console.log(`PDF written to: ${outPdf}`);
} else {
  console.log('No PDF engine found (agent-browser, chromium, google-chrome, wkhtmltopdf, weasyprint). Skipping PDF. Deliver report.html only.');
}
