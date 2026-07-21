#!/usr/bin/env node
// QA Report Generator for figma-design-qa agent-browser collection
// Usage: node qa-generate-report.js <collection-directory>
// Reads site-wide.json, bp-*.json, optional sections-config.json → writes report.html + report.csv

const fs = require('fs');
const path = require('path');

const inputDir = process.argv[2];
if (!inputDir) {
  console.error('Usage: node qa-generate-report.js <collection-directory>');
  process.exit(1);
}

const dataDir = path.join(inputDir, 'data');
const screenshotDir = path.join(inputDir, 'screenshots');

function loadJSON(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}

const siteWide = loadJSON(path.join(dataDir, 'site-wide.json')) || {};
const bpFiles = fs.readdirSync(dataDir)
  .filter(f => f.startsWith('bp-') && f.endsWith('.json'))
  .sort();
const breakpoints = bpFiles.map(f => ({ file: f, data: loadJSON(path.join(dataDir, f)) }));
const sectionsConfig = loadJSON(path.join(dataDir, 'sections-config.json'));

// ── Resolve sections (manual override or auto-detected) ──────────────
const rawSections = siteWide.sections || [];
const sections = sectionsConfig && sectionsConfig.sections
  ? sectionsConfig.sections.map((cfg, idx) => {
      const match = rawSections.find(s => s.selector === cfg.selector) ||
                    rawSections.find(s => s.label && s.label.includes(cfg.name)) ||
                    rawSections[idx] || {};
      return { index: idx, label: cfg.name, tag: match.tag || '', class: (match.class || '').substring(0, 80),
               top: match.top || 0, height: match.height || 0, width: match.width || 0,
               selector: cfg.selector || match.selector || '', xpath: match.xpath || '' };
    })
  : rawSections.map((s, idx) => ({ index: idx, label: s.label || ('Section ' + (idx + 1)),
               tag: s.tag, class: s.class, top: s.top, height: s.height, width: s.width,
               selector: s.selector || '', xpath: s.xpath || '' }));

// ── Helpers ──────────────────────────────────────────────────────────
function h(str) { return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function csv(str) { return '"' + String(str).replace(/"/g,'""') + '"'; }

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

let severeCount = 0, warningCount = 0, passCount = 0;
function countVerdict(v) {
  if (v === 'severe') severeCount++;
  else if (v === 'warning') warningCount++;
  else if (v === 'pass') passCount++;
}

function makeRow(section, param, expected, found, verdict, note, selector, parentSelector) {
  countVerdict(verdict);
  return { section, param, expected, found, verdict, note, selector: selector || '', parentSelector: parentSelector || '' };
}

// ── Data structures for tables ───────────────────────────────────────
let siteWideRows = [];
let sectionRows = {};   // { label: [rows] }
let responsiveRows = {}; // { 'sectionLabel / category': [rows] }

// Init section rows
sections.forEach(s => { sectionRows[s.label] = []; });

// ── Site-wide checks ─────────────────────────────────────────────────
const title = siteWide.title || '(not found)';
siteWideRows.push(makeRow('Page-wide', 'Page title', 'From Figma design', title, 'pass', 'Check against Figma', ''));

const faviconOK = siteWide.favicon && siteWide.favicon.length > 0;
siteWideRows.push(makeRow('Page-wide', 'Favicon', 'Present & loads', faviconOK ? siteWide.favicon : 'Missing', faviconOK ? 'pass' : 'severe', faviconOK ? '' : 'No favicon link tag found', ''));

// Images
const broken = siteWide.brokenImages || [];
broken.forEach(img => {
  siteWideRows.push(makeRow('Page-wide', 'Broken image', 'Image renders', img.src, 'severe', '0x0 natural dimensions — image not visible', img.selector || '', img.parentSelector || ''));
});
if (broken.length === 0) {
  siteWideRows.push(makeRow('Page-wide', 'Images', 'All render', 'All loaded', 'pass', `${(siteWide.images || []).length} images checked`, ''));
}

// Heading hierarchy
const headings = siteWide.headings || [];
const h1s = headings.filter(h => h.tag === 'H1');
const h1Selector = h1s.length > 0 ? (h1s[0].selector || '') : '';
if (h1s.length !== 1) {
  siteWideRows.push(makeRow('Page-wide', 'H1 count', 'Exactly one', `${h1s.length} found`, 'severe', h1s.map(h => h.text).join('; '), h1Selector));
} else {
  siteWideRows.push(makeRow('Page-wide', 'H1 count', 'Exactly one', h1s[0].text.substring(0,80), 'pass', '', h1Selector));
}

// Heading inversion
if (siteWide.headingInversion) {
  const inv = siteWide.headingInversion;
  const invHeading = headings.find(h => h.tag === inv.tag);
  siteWideRows.push(makeRow('Page-wide', 'Heading size hierarchy', 'h1 > h2 > h3 > h4 > h5 > h6', `${inv.tag} larger than prior heading (${inv.size}px > ${inv.previousSize}px)`, 'severe', 'Font size inversion detected', invHeading ? invHeading.selector : ''));
} else {
  siteWideRows.push(makeRow('Page-wide', 'Heading size hierarchy', 'Strictly descending', 'Descending', 'pass', '', ''));
}

// Empty headings
const emptyHeadings = headings.filter(h => !h.text || h.text.length === 0);
emptyHeadings.forEach(h => {
  siteWideRows.push(makeRow('Page-wide', 'Empty heading', 'None', `${h.tag} — empty`, 'warning', 'Heading with no text content', h.selector || ''));
});
if (emptyHeadings.length === 0) {
  siteWideRows.push(makeRow('Page-wide', 'Empty headings', 'None', '0', 'pass', '', ''));
}

// Figma heading comparison — reads figma-heading-expectations.json written by AI agent after Step 1
const figmaHeadingsFile = loadJSON(path.join(dataDir, 'figma-heading-expectations.json'));
if (!figmaHeadingsFile || !Array.isArray(figmaHeadingsFile) || figmaHeadingsFile.length === 0) {
  siteWideRows.push(makeRow('Page-wide', 'Figma heading comparison', 'Must compare every heading against Figma', 'figma-heading-expectations.json missing', 'severe', 'AI agent did not perform heading comparison — verify text, font-size, font-weight, font-family, color per heading', ''));
} else {
  const expectationsBySelector = {};
  figmaHeadingsFile.forEach(exp => {
    if (exp.selector) expectationsBySelector[exp.selector] = exp;
  });

  headings.forEach(live => {
    const exp = expectationsBySelector[live.selector];
    if (!exp) {
      // Try text match as fallback
      const textMatch = figmaHeadingsFile.find(e => e.expectedText && e.expectedText.trim().toLowerCase() === live.text.toLowerCase());
      if (textMatch) {
        compareHeadingProps(live, textMatch);
      } else {
        siteWideRows.push(makeRow('Page-wide', `Heading content: ${live.tag}`, 'Match Figma', `${live.text.substring(0,50)}`, 'warning', 'No Figma expectation found for this selector; compare manually', live.selector));
      }
      return;
    }
    compareHeadingProps(live, exp);
  });

  // Also flag Figma expectations that weren't found on live site
  figmaHeadingsFile.forEach(exp => {
    if (exp.selector) {
      const found = headings.find(h => h.selector === exp.selector);
      if (!found) {
        const byText = headings.find(h => h.text.toLowerCase() === (exp.expectedText || '').toLowerCase());
        if (!byText) {
          siteWideRows.push(makeRow('Page-wide', `Missing heading`, exp.expectedText || exp.selector, 'Not on page', 'severe', 'Heading expected from Figma not found on live site', exp.selector || ''));
        }
      }
    }
  });

  function compareHeadingProps(live, exp) {
    const label = `Heading: ${live.tag} "${live.text.substring(0,50)}"`;
    const sel = live.selector;

    // Text content (accounts for CSS text-transform in Figma)
    if (exp.expectedText !== undefined && exp.expectedText !== null) {
      const effectiveText = applyTransform((exp.expectedText || '').trim(), exp.expectedTextTransform);
      const textMatch = live.text.trim() === effectiveText;
      const note = textMatch ? '' : (exp.expectedTextTransform ? `Content mismatch (Figma raw: "${exp.expectedText}" with ${exp.expectedTextTransform})` : 'Content mismatch with Figma');
      siteWideRows.push(makeRow('Page-wide', `${label} — Text content`, effectiveText, live.text, textMatch ? 'pass' : 'severe', note, sel));
    }

    // Text transform
    if (exp.expectedTextTransform) {
      const liveTransform = live.textTransform || 'none';
      const ttMatch = liveTransform === exp.expectedTextTransform;
      siteWideRows.push(makeRow('Page-wide', `${label} — Text transform`, exp.expectedTextTransform, liveTransform, ttMatch ? 'pass' : 'warning', ttMatch ? '' : 'CSS text-transform mismatch', sel));
    }

    // Font size
    if (exp.expectedFontSize) {
      const livePx = parseFloat(live.fontSize);
      const expPx = parseFloat(exp.expectedFontSize);
      let fsVerdict = 'pass', fsNote = '';
      if (!isNaN(livePx) && !isNaN(expPx)) {
        const pctDiff = Math.abs(livePx - expPx) / expPx;
        if (pctDiff > 0.1) { fsVerdict = 'severe'; fsNote = `${(pctDiff * 100).toFixed(1)}% deviation (>10%)`; }
        else if (pctDiff > 0) { fsVerdict = 'warning'; fsNote = `${(pctDiff * 100).toFixed(1)}% deviation (within ±10%)`; }
      }
      siteWideRows.push(makeRow('Page-wide', `${label} — Font size`, exp.expectedFontSize, live.fontSize, fsVerdict, fsNote, sel));
    }

    // Font family
    if (exp.expectedFontFamily) {
      const ffMatch = live.fontFamily.toLowerCase().includes(exp.expectedFontFamily.toLowerCase().replace(/['"]/g, ''));
      siteWideRows.push(makeRow('Page-wide', `${label} — Font family`, exp.expectedFontFamily, live.fontFamily, ffMatch ? 'pass' : 'severe', ffMatch ? '' : 'Wrong typeface', sel));
    }

    // Font weight
    if (exp.expectedFontWeight) {
      const lw = String(live.fontWeight);
      const ew = String(exp.expectedFontWeight);
      siteWideRows.push(makeRow('Page-wide', `${label} — Font weight`, ew, lw, lw === ew ? 'pass' : 'severe', lw === ew ? '' : `Expected ${ew}, found ${lw}`, sel));
    }

    // Color
    if (exp.expectedColor) {
      const liveColor = normalizeColor(live.color);
      const expColor = normalizeColor(exp.expectedColor);
      let cVerdict = 'pass', cNote = '';
      if (liveColor !== expColor) {
        const sameHue = sameHueFamily(liveColor, expColor);
        cVerdict = sameHue ? 'warning' : 'severe';
        cNote = sameHue ? 'Same hue family, different shade' : 'Wrong color';
      }
      siteWideRows.push(makeRow('Page-wide', `${label} — Color`, exp.expectedColor, live.color, cVerdict, cNote, sel));
    }
  }
}

function applyTransform(text, transform) {
  if (!transform || transform === 'none') return text;
  if (transform === 'uppercase') return text.toUpperCase();
  if (transform === 'lowercase') return text.toLowerCase();
  if (transform === 'capitalize') return text.replace(/\b\w/g, function(c) { return c.toUpperCase(); });
  return text;
}

function normalizeColor(c) {
  if (!c) return '';
  if (c.startsWith('rgb')) {
    const m = c.match(/[\d.]+/g);
    if (!m || m.length < 3) return c;
    const hex = m.slice(0, 3).map(x => parseInt(x).toString(16).padStart(2, '0').toUpperCase()).join('');
    return '#' + hex;
  }
  return c.toUpperCase().replace(/\s/g, '');
}

function sameHueFamily(a, b) {
  if (!a || !b) return false;
  const ma = a.match(/[\d.]+/g);
  const mb = b.match(/[\d.]+/g);
  if (!ma || !mb || ma.length < 3 || mb.length < 3) return false;
  // Compare rough RGB ratios — if ratios are within 0.2 of each other, same hue family
  const sumA = ma.reduce((s, v) => s + parseInt(v), 0) || 1;
  const sumB = mb.reduce((s, v) => s + parseInt(v), 0) || 1;
  const ratiosA = ma.map(v => parseInt(v) / sumA);
  const ratiosB = mb.map(v => parseInt(v) / sumB);
  return ratiosA.every((r, i) => Math.abs(r - ratiosB[i]) < 0.2);
}

// Links
const links = siteWide.links || [];
const emptyLinks = links.filter(l => l.isEmpty);
const placeholderLinks = links.filter(l => l.isPlaceholder);
emptyLinks.forEach(l => {
  siteWideRows.push(makeRow('Page-wide', 'Link href', 'Valid URL', `empty (${l.text.substring(0,40)})`, 'severe', '<a> with empty href', l.selector || ''));
});
placeholderLinks.forEach(l => {
  siteWideRows.push(makeRow('Page-wide', 'Link href', 'Valid URL', `# (${l.text.substring(0,40)})`, 'warning', 'Placeholder href detected', l.selector || ''));
});
if (emptyLinks.length === 0 && placeholderLinks.length === 0) {
  siteWideRows.push(makeRow('Page-wide', 'Link hrefs', 'All valid', `${links.length} links OK`, 'pass', '', ''));
}

// Link transitions
if (siteWide.linkTransition === '0s' || !siteWide.linkTransition) {
  siteWideRows.push(makeRow('Page-wide', 'Link hover transition', 'Smooth transition', siteWide.linkTransition || 'none', 'warning', 'No visible transition duration on link hover', ''));
} else {
  siteWideRows.push(makeRow('Page-wide', 'Link hover transition', 'Smooth transition', siteWide.linkTransition, 'pass', '', ''));
}

// ── Per-section metadata ─────────────────────────────────────────────
sections.forEach(sec => {
  const rows = sectionRows[sec.label] || [];
  rows.push(makeRow(sec.label, 'Section bounds', 'Visible container', `${sec.tag} ${sec.class}`.substring(0, 80), 'pass', `Top: ${sec.top}px  H: ${sec.height}px  W: ${sec.width}px`, sec.selector));
  sectionRows[sec.label] = rows;
});

// ── Responsive checks (attributed to sections) ───────────────────────
breakpoints.forEach(bp => {
  const d = bp.data || {};
  const cat = (d.viewport && d.viewport.category) || 'unknown';
  const vw = (d.viewport && d.viewport.innerWidth) || '?';
  const vh = (d.viewport && d.viewport.innerHeight) || '?';

  // Overflow — attribute to section via sectionLabel
  const overflows = d.overflows || [];
  if (overflows.length > 0) {
    const intentional = overflows.filter(o => o.class && (o.class.includes('swiper') || o.class.includes('owl') || o.class.includes('carousel') || o.class.includes('marquee')));
    const unintentional = overflows.filter(o => !intentional.includes(o));
    if (unintentional.length > 0) {
      // Group by sectionLabel
      const bySection = {};
      unintentional.forEach(o => {
        const secLabel = o.sectionLabel || 'Unknown';
        if (!bySection[secLabel]) bySection[secLabel] = [];
        bySection[secLabel].push(o);
      });
      Object.keys(bySection).forEach(secLabel => {
        const items = bySection[secLabel];
        const key = `${secLabel} / ${cat}`;
        if (!responsiveRows[key]) responsiveRows[key] = [];
        items.forEach((o, i) => {
          responsiveRows[key].push(makeRow(secLabel, `Overflow @ ${vw}x${vh}`, 'No horizontal overflow', `${o.tag}.${o.class.substring(0,30)} (${o.width}px > ${o.vw}px vw)`, 'severe', i === 0 ? `${items.length} overflowing in this section` : '', o.selector || '', o.parentSelector || ''));
        });
      });
    } else {
      const key = `All / ${cat}`;
      if (!responsiveRows[key]) responsiveRows[key] = [];
      responsiveRows[key].push(makeRow('All', `Overflow @ ${vw}x${vh}`, 'No horizontal overflow', `${intentional.length} intentional (carousel etc.)`, 'pass', 'Swiper/carousel detected', ''));
    }
  } else {
    const key = `All / ${cat}`;
    if (!responsiveRows[key]) responsiveRows[key] = [];
    responsiveRows[key].push(makeRow('All', `Overflow @ ${vw}x${vh}`, 'No horizontal overflow', '0', 'pass', '', ''));
  }

  // Hidden sections
  const hidden = d.hiddenSections || [];
  hidden.forEach(s => {
    const secLabel = s.label || 'Unknown';
    const key = `${secLabel} / ${cat}`;
    if (!responsiveRows[key]) responsiveRows[key] = [];
    responsiveRows[key].push(makeRow(secLabel, `Hidden section @ ${vw}x${vh}`, 'All sections visible', `Collapsed (height=0)`, 'severe', `Query: ${s.selector}`, s.elementSelector || '', s.parentSelector || ''));
  });

  // Mobile hamburger
  if (cat === 'mobile') {
    const key = `Navigation / ${cat}`;
    if (!responsiveRows[key]) responsiveRows[key] = [];
    if (d.hamburgerDetected) {
      responsiveRows[key].push(makeRow('Navigation', `Hamburger @ ${vw}x${vh}`, 'Opens with desktop nav links', 'Detected', 'pass', `Links: ${(d.hamburgerLinks || []).join(', ').substring(0,120)}`, ''));
    } else {
      responsiveRows[key].push(makeRow('Navigation', `Hamburger @ ${vw}x${vh}`, 'Opens with desktop nav links', 'Not detected', 'warning', 'No visible hamburger button found', ''));
    }
  }
});

// ── HTML generation ──────────────────────────────────────────────────
function renderTable(title, rows, showSelector) {
  if (!rows || rows.length === 0) return '';
  const hasParent = rows.some(r => r.parentSelector && r.parentSelector.length > 0);
  return `<h3>${h(title)}</h3>
<table>
<thead><tr>
<th>Section</th><th>Parameter</th><th>Expected</th><th>Found</th><th>Verdict</th><th>Note</th>
${showSelector ? '<th>Selector</th>' : ''}
${showSelector && hasParent ? '<th>Parent XPath</th>' : ''}
</tr></thead>
<tbody>
${rows.map(r => `<tr>
<td>${h(r.section)}</td>
<td>${h(r.param)}</td>
<td>${h(r.expected)}</td>
<td>${h(r.found)}</td>
<td class="${verdictClass(r.verdict)}">${verdictIcon(r.verdict)} ${h(r.verdict.toUpperCase())}</td>
<td>${h(r.note)}</td>
${showSelector ? `<td class="selector-cell"><code class="devtools">document.querySelector("${h(r.selector)}").scrollIntoView()</code></td>` : ''}
${showSelector && hasParent ? `<td class="selector-cell" style="color:#b71c1c"><code class="devtools">document.querySelector("${h(r.parentSelector)}").scrollIntoView()</code></td>` : ''}
</tr>`).join('')}
</tbody>
</table>`;
}

let htmlParts = [];

// Per-section tables
sections.forEach(sec => {
  const rows = sectionRows[sec.label] || [];
  if (rows.length > 0) {
    htmlParts.push(renderTable(`Section: ${sec.label}`, rows, true));
  }
});

// Site-wide table
if (siteWideRows.length > 0) {
  htmlParts.push(renderTable('Site-wide Checks', siteWideRows, true));
}

// Responsive tables — grouped by responsive key
const respKeys = Object.keys(responsiveRows).sort();
respKeys.forEach(key => {
  htmlParts.push(renderTable(`Responsive: ${key}`, responsiveRows[key], true));
});

const allRows = [].concat(
  ...Object.values(sectionRows).flat(),
  siteWideRows,
  ...Object.values(responsiveRows).flat()
);

const html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>QA Report — ${h(title)}</title>
<style>
body{font-family:system-ui,-apple-system,sans-serif;margin:40px;max-width:1400px;line-height:1.5;color:#222}
h1{border-bottom:3px solid #222;padding-bottom:10px}
h2{border-bottom:2px solid #666;padding-bottom:6px;margin-top:36px}
h3{margin-top:28px;color:#333}
.summary{background:#f5f5f5;padding:16px;border-radius:8px;margin-bottom:24px;display:flex;gap:32px;flex-wrap:wrap}
.summary-box{text-align:center;min-width:100px}
.summary-box .big{font-size:32px;font-weight:700}
.summary-box .label{font-size:12px;text-transform:uppercase;color:#666;letter-spacing:.05em}
table{width:100%;border-collapse:collapse;margin:16px 0 32px 0;font-size:13px}
th,td{border:1px solid #ddd;padding:8px;text-align:left;vertical-align:top}
th{background:#f8f8f8;position:sticky;top:0}
.verdict-pass{color:#1b7b2b;font-weight:700}
.verdict-warning{color:#b87a00;font-weight:700}
.verdict-severe{color:#b71c1c;font-weight:700}
.selector-cell{font-family:Consolas,Monaco,monospace;font-size:11px;word-break:break-all;max-width:320px}
tr:nth-child(even){background:#fafafa}
.screenshots{display:flex;flex-wrap:wrap;gap:12px;margin-top:24px}
.screenshot{max-width:280px;border:1px solid #ddd;border-radius:4px}
.screenshot img{max-width:100%;display:block}
.screenshot .caption{font-size:11px;padding:6px;color:#555;text-align:center}
.sec-nav{display:flex;flex-wrap:wrap;gap:8px;margin:16px 0}
.sec-nav a{background:#eee;padding:4px 12px;border-radius:4px;text-decoration:none;color:#333;font-size:13px}
.sec-nav a:hover{background:#ddd}
</style></head><body>
<h1>Figma Design QA Report</h1>

<p style="color:#888;margin-bottom:4px">Site: ${h(siteWide.url || '')}  |  ${new Date().toISOString().slice(0,10)}</p>

<div class="summary">
  <div class="summary-box"><div class="big">${passCount}</div><div class="label">Pass</div></div>
  <div class="summary-box"><div class="big">${warningCount}</div><div class="label">Warning</div></div>
  <div class="summary-box"><div class="big">${severeCount}</div><div class="label">Severe</div></div>
  <div class="summary-box"><div class="big">${allRows.length}</div><div class="label">Checks</div></div>
  <div class="summary-box"><div class="big">${sections.length}</div><div class="label">Sections</div></div>
  <div class="summary-box"><div class="big">${breakpoints.length}</div><div class="label">Breakpoints</div></div>
</div>

<div class="sec-nav"><strong>Jump to:</strong>
${sections.map(s => `<a href="#sec-${s.index}">${h(s.label)}</a>`).join('')}
<a href="#sitewide">Site-wide</a>
<a href="#responsive">Responsive</a>
<a href="#screenshots">Screenshots</a>
</div>

${htmlParts.map((part, i) => {
  if (i < sections.length) return `<div id="sec-${i}">${part}</div>`;
  if (i === sections.length) return `<div id="sitewide">${part}</div>`;
  return `<div id="responsive">${part}</div>`;
}).join('\n')}

<h2 id="screenshots">Screenshots</h2>
<div class="screenshots">
${breakpoints.map(bp => {
  const dims = bp.file.replace('bp-', '').replace('.json', '');
  const png = path.join(screenshotDir, `${dims}.png`);
  if (fs.existsSync(png)) {
    const rel = path.relative(inputDir, png).replace(/\\/g, '/');
    return `<div class="screenshot"><a href="${rel}" target="_blank"><img src="${rel}" alt="${dims}" loading="lazy"></a><div class="caption">${dims}</div></div>`;
  }
  return '';
}).join('')}
</div>

<p style="margin-top:40px;color:#888;font-size:12px">Generated from agent-browser collection data.<br>Directory: ${h(inputDir)}  |  Sections: ${sectionsConfig ? 'manual override' : 'auto-detected'}</p>
</body></html>`;

// ── Write HTML ───────────────────────────────────────────────────────
const outHtml = path.join(inputDir, 'report.html');
fs.writeFileSync(outHtml, html);
console.log(`Report (HTML) written to: ${outHtml}`);

// ── Write CSV ────────────────────────────────────────────────────────
const csvHeader = 'Section,Parameter,Expected,Found,Verdict,Note,Selector,ParentSelector\n';
const csvBody = allRows.map(r =>
  [csv(r.section), csv(r.param), csv(r.expected), csv(r.found), csv(r.verdict), csv(r.note), csv(r.selector), csv(r.parentSelector || '')].join(',')
).join('\n');
const outCsv = path.join(inputDir, 'report.csv');
fs.writeFileSync(outCsv, csvHeader + csvBody);
console.log(`Report (CSV) written to: ${outCsv}`);

// ── Attempt PDF conversion ──────────────────────────────────────────
function hasCmd(cmd) { try { require('child_process').execSync(`where ${cmd}`, {stdio: 'ignore'}); return true; } catch { return false; } }

const outPdf = path.join(inputDir, 'report.pdf');

if (hasCmd('agent-browser')) {
  try {
    const fileUrl = 'file://' + outHtml.replace(/\\/g, '/');
    require('child_process').execSync(`agent-browser --allow-file-access open "${fileUrl}"`, {stdio: 'inherit'});
    require('child_process').execSync(`agent-browser pdf "${outPdf}"`, {stdio: 'inherit'});
    console.log(`PDF written to: ${outPdf}`);
  } catch {
    console.log('agent-browser PDF generation failed. Falling back...');
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
  console.log('No PDF engine found. Skipping PDF. Deliver report.html + report.csv.');
}
