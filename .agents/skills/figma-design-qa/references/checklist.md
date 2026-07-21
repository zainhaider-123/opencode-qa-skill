# QA Checklist & Severity Rules

Severity scale used throughout: **pass**, **warning**, **severe**. When a rule below doesn't explicitly state a severity, use judgment but default to **warning** for cosmetic drift and **severe** for anything a user/client would immediately notice as wrong or broken.

## Color
- Compare text color, content/background color, and overall palette used per section against the Figma fills/strokes.
- Exact or near-exact (imperceptible) match → pass.
- Noticeably different shade/tone but same general hue family → warning.
- Wrong color entirely (e.g. brand blue vs gray, or contrast/accessibility broken) → severe.

## Fonts
- Font family must match Figma exactly (same typeface, same weight where specified) → otherwise **severe** (wrong font is highly visible and a common QA miss).

## Font size
- Compare live site computed font-size to the Figma text node's font size, per section/element.
- Within ±10% of the Figma value → **warning** at most (note the delta, don't fail it hard).
- Beyond ±10% → **severe**.
- Exact match → pass.

## Content / copy matching
- Text content on the site must match Figma content exactly (same words, same casing/punctuation where it matters). CSS `text-transform` is accounted for: if Figma applies `text-transform: uppercase`/`capitalize`/`lowercase`, the effective rendered text is used for comparison, not the raw string.
- Any deviation, however small → **severe**. This is intentionally strict — content drift is treated as a content bug, not cosmetic.
- Any placeholder/dummy text on the live site (lorem ipsum, "Lorem ipsum dolor...", "Sample text", "Your text here", placeholder names like "John Doe" where real content was expected, etc.) → **severe**, flagged immediately regardless of surrounding context.

## Container / section sizing
- Compare each section's container dimensions (width, height, padding/margins as visible) between Figma and the live site at the matching breakpoint.
- Meaningful mismatch (not just sub-pixel rounding) → **severe**.

## Page title
- Browser `<title>` must match the title specified/implied in Figma (e.g. cover frame or page name intended as title) → mismatch is **severe**.

## Favicon
- Must exist and load (no 404/broken icon link) → missing or broken is **severe**.

## Images
- Every image on the page must render (no broken-image icon, no 404 on the `src`).
- Any broken image → **severe**.

## Links
- Collect every `<a>` href (including `mailto:` links).
- Empty href (`href=""` or missing) → **severe**.
- Placeholder href (`href="#"`) → **warning**.
- Working, real destination → pass.

## Hover states
- Links should have a visible hover state, and the transition duration should match what's specified/implied in the design (or at minimum be present and reasonable if Figma has no interactive spec).
- Missing hover feedback entirely → severe.
- Present but duration/easing clearly mismatched from spec → warning.

## Heading hierarchy
- Exactly one `<h1>` per page → more than one, or zero, is **severe**.
- `<h2>` used for subheadings beneath it, and hierarchy should nest logically (no skipping levels in a way that breaks semantic order, e.g. h1 → h4 directly) → violations are **severe**.
- Heading font sizes must descend strictly: h1 > h2 > h3 > h4 > h5 > h6. Any inversion → **severe**.
- A given heading level's size must stay consistent everywhere it's used on the site (e.g. every h2 should be the same size) → inconsistency → **severe**.

## Mobile navigation
- Hamburger menu must open and must contain the same links as the desktop nav, in the same order/grouping where reasonable → mismatch or broken hamburger → **severe**.

## Responsive checks (see references/breakpoints.md for sizes)
- Overflow/clipping caused by font size at a given breakpoint → **severe** if content is cut off or unreadable, **warning** if just visually tight.
- Any section or its content becoming invisible/unreachable at a breakpoint → **severe**.
- Spacing between sections becoming visually broken (overlapping elements, huge unintended gaps) → **warning**, or **severe** if it breaks usability/readability.
