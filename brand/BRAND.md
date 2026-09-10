# uNotch brand

This folder is the single source of truth for how uNotch looks. The app
(`Sources/uNotch/Brand.swift`), the icon generator (`scripts/generate-icon.swift`),
the site (`site/index.html`), and the generated `DESIGN.md` all derive from it.
Change a value here first, then propagate.

## Idea

A notch is the one part of a Mac screen that stays out of the way. uNotch borrows
that posture: a thin cue at the screen edge that becomes a glass readout only when
you ask. The brand is **quiet, exact, and dark-glass native** — it should feel like
part of macOS, not like a dashboard.

One word to keep in mind while designing: *tucked*.

## Name

- Written **uNotch** — lowercase `u`, capital `N`, no space, never "UNotch",
  "Unotch", or "u-Notch". At the start of a sentence it is still "uNotch".
- Bundle id: `app.unotch.utility`. Domain-style lowercase is fine in code and URLs.

## Mark

The mark is a **screen with a side notch**: a rounded rectangular screen outline
with a solid mint rail extending inward from its left edge. It describes the
actual app placement, with no letterform or detached status dot.
Geometry lives on a 1024 grid (see `logo/mark.svg`):

- Screen: (176, 256), 672 × 512, corner radius 80, stroke 64.
- Side notch: x=144–336, y=392–632; flush left edge and 56 px inner corners.
  Its left edge aligns with the outside of the screen stroke.
- Tile variant (`logo/icon.svg`): charcoal rounded square (radius 205 on 928),
  paper screen, mint notch. This is the macOS app icon and the social avatar.
- Favicon: the same mark on a full-bleed charcoal tile (radius 224 on 1024).
- Mono variants (`logo/mark-mono-black.svg`, `logo/mark-mono-white.svg`) render
  the screen and notch in the same ink.
- **Menu bar**: always a macOS *template* image (system tints it). Never draw
  the mint notch in colour in the menu bar.

Clear space: keep at least one stroke width (64/1024 of the mark height) free
around the mark. Minimum size: 16 px. The screen and attached side notch must
remain distinct at that size; never omit the notch.

## Social preview

The share card is a 1200 × 630 PNG, composed in `social/card.html` and rendered
with `scripts/generate-social.sh`. It uses the backdrop ground, charcoal type,
the existing tagline, the new icon, and a screen showing the actual site HUD
with illustrative usage values. Provider names, free/open-source status, and
macOS requirements come from the site. Keep primary content 64 px from the
card edges. Use a new versioned image filename whenever its pixels change,
since `/assets/` is cached immutably. Open Graph and Twitter metadata must
reference the same absolute PNG URL, with dimensions and descriptive alt text.

## Colour

| Token | Hex | Role |
| --- | --- | --- |
| `charcoal` | `#15191B` | Brand ground. Icon tile, site background, dark surfaces. |
| `graphite` | `#1E2427` | Raised dark surface: HUD mock backdrops, code blocks. |
| `ash` | `#2A3135` | Hairlines and dividers on dark. |
| `smoke` | `#8B9498` | Secondary text on dark (5.7:1 on charcoal). |
| `paper` | `#F4F7F6` | Primary text on dark; the mark itself. |
| `mint` | `#3BE29B` | **The live signal.** Side notch, status point, and remaining usage. |

**The Status Point Rule.** Mint is a signal, not a theme. It appears where there is
live state or the primary action: the side notch on the mark, the "remaining" fill of the
selected provider, the one primary action on a page (it may repeat — a download
button at the top and bottom — but it is always the *same* action). Never on
headings, borders, bullets, backgrounds, or decoration. If a screen has mint on two
different actions, or on anything that is not reporting state, remove one.

Contrast (measured, WCAG): paper on charcoal 16.2:1 · smoke on charcoal 5.7:1 ·
mint on charcoal 10.5:1 · charcoal on mint 10.5:1.

In the HUD, ink is expressed as paper at opacity over glass rather than as fixed
greys (`0.96` primary, `0.72` secondary, `0.50` tertiary, `0.16` hairline,
`0.10` divider). Tokens are in `tokens.css` / `tokens.json`.

## Surfaces

uNotch has two grounds, and every screen is one or the other:

1. **Dark glass** — the product. The HUD, the menu bar, the app icon. Charcoal tint
   over `NSVisualEffectView`, paper ink at opacity, mint as the status point.
2. **Backdrop** — the website. The ground is Seth's own
   [Aetheria](https://aetheria.sethmedina.com) render *emerald flow* (seed `805214`),
   kept in `site/assets/` as responsive WebP and used three ways exactly as on
   sethmedina.com: faint and fixed behind the whole page (`--ambient: 0.5`), at full
   strength inside the hero's "desk" frame under the HUD (the glass over a real
   wallpaper), and strong again behind the closing and footer, faded with
   `mask-image`, never with painted scrims. The page ground `#B7C9C1` is sampled from
   the render's pale edge so the image has no seams. Ink is **charcoal**; secondary
   text is **ash** (`7.4:1` on the ground, `4.1:1` on the emerald core — so ash only
   sits where the ambient is faint, and any text over a strong layer is full charcoal,
   `5.0:1` on the core). On this ground the **primary action is charcoal**, not mint:
   mint has no edge against pale mint, and the Status Point Rule keeps it for state.

The footer of every uNotch web surface credits the render: *Backdrop made with
Aetheria*.

## Type

uNotch is a Mac utility; it speaks in the Mac's own voice.

- **Display / numerals**: `ui-rounded` (SF Rounded on Apple platforms), weight
  600–700, letter-spacing −0.02em, `font-variant-numeric: tabular-nums`.
- **Body / UI**: system stack — `-apple-system, BlinkMacSystemFont, "SF Pro Text",
  Inter, "Helvetica Neue", sans-serif`, weight 400–600.
- **Data labels / code**: `ui-monospace, "SF Mono", Menlo, monospace`.

No webfonts are loaded anywhere. Zero third-party requests is part of the brand.

**The Numeral Rule.** Percentages and reset times are the product. They are always
rounded-display, semibold-or-bolder, tabular, and the most legible thing in view.

## Shape and depth

- Radii: `6` chips · `11` buttons/rows · `15` callouts · `24` rail · `999` pills.
- Glass: `NSVisualEffectView` under-window material with a paper wash of 0.035
  (idle cue), black tint 0.18 (callout) or 0.26 (rail), plus a 1 px paper hairline
  at 0.16. On the web this is `backdrop-filter: blur(24px) saturate(1.4)` over
  `rgba(21,25,27,0.62)` with a `rgba(244,247,246,0.16)` border.
- One shadow, for the callout only: `0 3px 7px rgba(0,0,0,0.18)`. Nothing else
  casts a shadow. Depth otherwise comes from tint, not from shadow.

## Motion

Spring `response 0.35, damping 0.8` for presentation changes; `0.28s ease-out`
for bar fills. Reduced motion collapses everything to a 0.12 s fade. Nothing loops
except the refresh glyph while a read is in flight.

## Voice

Short declarative sentences. Say what the software does; never what it "empowers".
Prefer "reads", "shows", "stores two preferences" over "seamless", "powerful",
"supercharge". Privacy claims are stated as facts with the mechanism next to them.

Tagline: **Live AI usage, quietly tucked into the edge of your Mac.**
