---
name: uNotch
description: Live AI usage, quietly tucked into the edge of your Mac.
colors:
  charcoal: "#15191B"
  graphite: "#1E2427"
  ash: "#2A3135"
  smoke: "#8B9498"
  paper: "#F4F7F6"
  mint: "#3BE29B"
  ink: "#F4F7F6F5"
  ink-2: "#F4F7F6B8"
  ink-3: "#F4F7F680"
  hairline: "#F4F7F629"
  divider: "#F4F7F61A"
  glass: "#15191B9E"
  glass-strong: "#15191BB8"
typography:
  display:
    fontFamily: "ui-rounded, -apple-system, BlinkMacSystemFont, 'SF Pro Rounded', Inter, 'Helvetica Neue', sans-serif"
    fontSize: "clamp(2.25rem, 6vw, 4rem)"
    fontWeight: 600
    lineHeight: 1.05
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "ui-rounded, -apple-system, BlinkMacSystemFont, 'SF Pro Rounded', Inter, 'Helvetica Neue', sans-serif"
    fontSize: "clamp(1.5rem, 3vw, 2rem)"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "-0.015em"
  title:
    fontFamily: "ui-rounded, -apple-system, BlinkMacSystemFont, 'SF Pro Rounded', Inter, 'Helvetica Neue', sans-serif"
    fontSize: "15px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "normal"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', Inter, 'Helvetica Neue', sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.55
    letterSpacing: "normal"
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', Inter, 'Helvetica Neue', sans-serif"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "normal"
  mono:
    fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.6
    letterSpacing: "normal"
rounded:
  chip: "6px"
  control: "11px"
  callout: "15px"
  rail: "24px"
  pill: "999px"
spacing:
  s1: "4px"
  s2: "8px"
  s3: "12px"
  s4: "16px"
  s6: "24px"
  s8: "32px"
  s12: "48px"
  s16: "64px"
  s24: "96px"
components:
  button-primary:
    backgroundColor: "{colors.mint}"
    textColor: "{colors.charcoal}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "12px 20px"
    height: "44px"
  button-primary-hover:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.charcoal}"
  button-ghost:
    backgroundColor: "{colors.glass}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "12px 20px"
    height: "44px"
  button-ghost-hover:
    backgroundColor: "{colors.graphite}"
    textColor: "{colors.paper}"
  callout:
    backgroundColor: "{colors.glass}"
    textColor: "{colors.ink}"
    rounded: "{rounded.callout}"
    padding: "14px 16px"
  rail:
    backgroundColor: "{colors.glass-strong}"
    textColor: "{colors.ink-2}"
    rounded: "{rounded.rail}"
    padding: "11px 4px"
    width: "58px"
  segment:
    backgroundColor: "{colors.divider}"
    textColor: "{colors.ink-2}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "5px 10px"
    height: "26px"
  segment-selected:
    backgroundColor: "{colors.hairline}"
    textColor: "{colors.ink}"
  data-label:
    backgroundColor: "{colors.graphite}"
    textColor: "{colors.smoke}"
    typography: "{typography.mono}"
    rounded: "{rounded.chip}"
    padding: "2px 6px"
---

<!--
  GENERATED from brand/BRAND.md + brand/tokens.json (2026-09-07).
  The brand folder is the canon and wins any conflict with this file.
  REGENERATE this file when the canon changes — never hand-edit it.
-->

# Design System: uNotch

## 1. Overview

**Creative North Star: "Tucked"**

uNotch is a quiet instrument. It lives at the edge of a Mac screen as a seven-point cue and
only becomes a readout when the pointer asks. Everything in the system follows from that
posture: dark glass that borrows the desktop behind it, ink that is paper at opacity rather
than fixed grey, and one accent — the mint status point from the logo — that appears only
where something is live or where the user acts. The system is native first: SF Rounded
numerals, the system text face, `NSVisualEffectView` glass, and no loaded web fonts or
third-party requests anywhere, on the app or on the site.

The system explicitly rejects the "AI tool" landing-page look: purple-to-blue gradients,
neon glows, card grids of features, floating blobs, eyebrow caps labels over every heading,
and marketing verbs. It also rejects dashboard density. uNotch shows a handful of numbers;
each one gets room.

**Key Characteristics:**
- Dark glass surfaces tinted charcoal; depth from tint, never from stacked shadows
- One accent (mint) rationed to live state and the single primary action
- Rounded numerals are the loudest thing on any surface
- Hairlines and spacing group content; cards are the exception, not the layout
- Motion is a single spring for presentation and a short ease for bar fills

## 2. Colors

A charcoal ground, paper ink, and a single mint signal.

### Primary
- **Mint** (#3BE29B): the status point. The "remaining" fill of the selected provider ring
  and bars, the point on the mark, and the one primary button on a page. 10.5:1 on charcoal.

### Neutral
- **Charcoal** (#15191B): brand ground — icon tile, site background, the tint under glass.
- **Graphite** (#1E2427): raised dark surface for HUD mock backdrops and code blocks.
- **Ash** (#2A3135): hairlines and dividers on solid dark surfaces.
- **Smoke** (#8B9498): secondary text on charcoal (5.7:1, AA for body).
- **Paper** (#F4F7F6): primary text on dark and the mark itself (16.2:1 on charcoal).
- **Ink / Ink-2 / Ink-3**: paper at 0.96 / 0.72 / 0.50 over glass — primary, secondary,
  tertiary text inside the HUD and glass surfaces.
- **Hairline / Divider**: paper at 0.16 / 0.10 — 1 px borders and separators on glass.
- **Glass / Glass-strong**: charcoal at 0.62 / 0.72 behind `backdrop-filter`; the callout
  uses Glass, the provider rail uses Glass-strong.

### Named Rules (optional, powerful)
**The Status Point Rule.** Mint is a signal, not a theme. It reports live state or marks
the primary action — one action per page, which may repeat (a download button at the top
and bottom) but never differ. Never on headings, borders, bullets, backgrounds, or
decoration. If a screen has mint on two different actions, one of them is wrong.

**The Paper-Over-Glass Rule.** Text on glass is paper at opacity, never a hex grey. Opacity
lets the desktop behind the HUD tint the type so it reads as part of the surface.

## 3. Typography

**Display Font:** ui-rounded (SF Rounded on Apple platforms; falls back to the system face)
**Body Font:** -apple-system / BlinkMacSystemFont (SF Pro Text; falls back to Inter, Helvetica Neue)
**Label/Mono Font:** ui-monospace (SF Mono; falls back to Menlo)

**Character:** The Mac's own voice. Rounded display and numerals feel soft and instrument-like
against a plain, tight-tracked text face. Nothing is loaded from a network.

### Hierarchy
- **Display** (600, clamp(2.25rem, 6vw, 4rem), 1.05, −0.02em): the hero sentence on the site.
- **Headline** (600, clamp(1.5rem, 3vw, 2rem), 1.15, −0.015em): section headings.
- **Title** (700, 15px, 1.2, rounded): HUD callout title ("Claude usage").
- **Body** (400, 17px, 1.55): site prose, max 62ch.
- **Label** (600, 11px, 1.2): HUD row labels, segment text, button text.
- **Mono** (400, 13px, 1.6): code blocks and data labels only.

### Named Rules (optional)
**The Numeral Rule.** Percentages and reset times are the product. They are rounded-display,
semibold or bolder, `tabular-nums`, and the most legible element in view. A percentage set in
the body face is a defect.

**The No-Eyebrow Rule.** Small caps labels above headings are prohibited. Caps/mono labels
exist only as genuine data labels (table heads, status chips).

## 4. Elevation

uNotch is a tonal system. Surfaces are glass over the desktop (or over charcoal on the site);
hierarchy comes from tint strength — Glass for the callout, Glass-strong for the rail — and
from a 1 px paper hairline at 0.16. Exactly one shadow exists.

### Shadow Vocabulary (if applicable)
- **Callout** (`box-shadow: 0 3px 7px rgba(0,0,0,0.18)`): the usage/settings callout only,
  because it floats away from the rail. Nothing else casts a shadow.

### Named Rules (optional)
**The One Shadow Rule.** If a second shadow appears anywhere, delete it. Depth is tint.

**The Hairline Rule.** Borders on glass are 1 px paper at 0.16 — never a solid grey line and
never thicker than 1 px.

## 5. Components

### Buttons
- **Shape:** pill (999px) on the site; rounded control (11px) inside the HUD.
- **Primary:** mint fill, charcoal text, 600 weight, 12px 20px padding, 44px min height.
  One per page. On the site it is the download action; in the HUD it is "Update & Restart".
- **Hover / Focus:** primary lifts to paper fill with charcoal text; ghost brightens from
  Glass to Graphite. Focus is a 2 px mint ring offset 2 px, on every interactive element.
- **Ghost:** glass fill, ink text, paper hairline border. Used for "View on GitHub", "Quit".

### Chips (if used)
- **Style:** graphite background, smoke mono text, 6 px radius. Data labels only
  ("macOS 14+", "arm64", "MIT").
- **State:** chips are not interactive and have no selected state.

### Cards / Containers
- **Corner Style:** callout 15 px; rail 24 px on the edge-facing corners only (flat against
  the screen edge).
- **Background:** Glass (callout) / Glass-strong (rail) with `backdrop-filter: blur(24px)
  saturate(1.4)`.
- **Shadow Strategy:** callout only, per Elevation.
- **Border:** 1 px hairline.
- **Internal Padding:** 14px 16px (callout), 11px vertical (rail).
- Cards are not a layout device on the site. Sections are separated by hairlines and 96 px
  of space; feature lists are rows, not boxes.

### Inputs / Fields
- **Segment (side picker):** two-option control, divider fill at rest, hairline fill when
  selected, ink-2 → ink text, 11 px radius, 26 px tall.
- **Drag grip:** a 6-dot grip glyph in ink-3 inside a divider-filled row; the pointer becomes
  an open hand on hover and a closed hand while dragging.
- No text inputs exist in the product.

### Navigation
- Site header is a mark plus three text links (GitHub, Privacy, Security) in ink-2, hover to
  ink, no background, no border, 64 px tall. On mobile the links stay inline; they are short.
- The menu bar item is the mark as a template image with a plain NSMenu.

### Signature Component: the edge HUD
- **Idle cue:** 7×52 pt glass sliver clipped to a pressure curve at the screen edge, a 1×15
  paper line at 0.22, and the mint status point (2.5 pt) above it.
- **Rail:** 58×252 pt Glass-strong column; three provider rings (36 pt, 4 pt stroke, mint
  when selected, paper 0.58 otherwise) with percentage labels; a 42 pt footer that reveals
  the settings gear only when the pointer is within 56 pt of the bottom.
- **Callout:** 292 pt wide Glass bubble with a 10 pt pointer toward the rail. Shows usage
  rows (label, percentage, 6 pt bar, reset text) or the settings section (side segment,
  drag grip, Update & Restart, Quit).

## 6. Do's and Don'ts

### Do:
- **Do** write the name as `uNotch` — lowercase u, capital N — everywhere, including at the
  start of a sentence.
- **Do** keep mint to live state and the single primary action (The Status Point Rule).
- **Do** set every percentage in ui-rounded, ≥600 weight, `tabular-nums` (The Numeral Rule).
- **Do** express text on glass as paper at 0.96 / 0.72 / 0.50 opacity.
- **Do** separate sections with hairlines and space (96 px on desktop, 64 px on mobile),
  not boxes.
- **Do** ship the site with zero external requests: no web fonts, analytics, or CDNs.
- **Do** verify contrast numerically; the floor is 4.5:1 for body and 3:1 for UI.
- **Do** provide a visible 2 px mint focus ring on every interactive element.

### Don't:
- **Don't** use purple-to-blue gradients, neon glows, or "AI" sparkle iconography.
- **Don't** put features in a grid of cards. Rows with hairlines.
- **Don't** add eyebrow caps labels above headings.
- **Don't** add a second shadow anywhere; the callout is the only surface that casts one.
- **Don't** colour the mint point in the menu bar; the menu bar mark is a template image.
- **Don't** use the words seamless, powerful, supercharge, empower, or effortless.
- **Don't** load a web font. If the display face is unavailable, the system face is correct.
- **Don't** let the mark shrink below 16 px or draw it without the status point.
