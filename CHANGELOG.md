# Changelog

All notable changes to uNotch are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.8.1] — 2026-09-22

### Fixed
- **Claude's Resets available row appears on busy accounts.** Claude's usage
  endpoint opens one slot per account every minute or two, and live Claude Code
  sessions and Claude Desktop take many of them, so 1.8.0's single ten-minute
  read was usually refused and the row never showed. The read now retries
  every 20 seconds for up to about two and a half minutes until it lands. The
  refresh control turns while it waits; the meters keep their last values.

## [1.8.0] — 2026-09-22

### Added
- **Claude limit resets in the HUD.** When Claude has granted your account a
  usage-limit reset (the kind claude.ai shows under Settings → Usage → Resets),
  Claude's pop-out gains a **Resets available** row with the count and its
  expiry, and **Use reset** applies one from the HUD — the same
  `reset_rate_limits` call Claude Code's own "Use an available limit reset"
  makes. A spent grant shows **0 resets**. Extra `CLAUDE_CONFIG_DIR` sign-ins
  each report their own.

### Changed
- Claude's resets are read from Claude's usage endpoint with the OAuth token
  Claude Code keeps in the login keychain, every ten minutes and after a reset;
  the per-minute usage read still goes through the CLI. See PRIVACY.md.

## [1.7.0] — 2026-09-22

### Added
- **Use a Codex reset from the HUD.** When Codex reports banked resets, the
  Resets available row offers **Use reset**. uNotch spends one credit through
  the local Codex app-server and refreshes the meters.

## [1.6.0] — 2026-09-21

### Added
- **Multiple Cursor subscriptions.** A second Cursor Agent sign-in kept in its
  own folder — `CURSOR_CONFIG_DIR=~/.cursor-work agent` — joins Cursor's pop-out
  the same way Claude's do. The cell is named from the folder (`work`). Setting
  the variable is the whole setup; uNotch finds the folder and reads that
  sign-in.
- **Grok Bot follows each Cursor sign-in.** A second Cursor subscription brings
  its own Grok Bot allowance into Grok Bot's pop-out, named the same way.

### Changed
- Codex shows **0 resets** when the account has banked resets and none are left.
- Claude's ring follows the lower of the 5-hour window and the weekly limit.
- At or below **10%** remaining, that ring is red whether or not it is hovered.
  The whole edge cue turns red once when something drops that low. Opening the
  HUD dismisses it, and it stays quiet until that usage climbs back above 10%
  and drops again.

## [1.5.4] — 2026-09-18

### Fixed
- A hovered ring with **0%** remaining is a full red circle. 1.5.3 only recoloured
  the remaining arc, so an empty ring stayed invisible.

## [1.5.3] — 2026-09-18

### Changed
- A hovered ring turns **red** instead of mint when that provider has under 10%
  remaining. 10% itself stays mint. The percent under the ring matches.

## [1.5.2] — 2026-09-18

### Changed
- The selected ring is only the mint stroke and the mint percent under it. The
  card behind a hovered provider is gone.
- The settings gear has no disc. Hovering it turns the icon mint and opens
  settings; the section hangs from the gear so the pointer can travel into it
  without crossing a ring.

## [1.5.1] — 2026-09-18

### Fixed
- The callout's pointer comes out of the ring you are on. The callout hangs from
  the selected ring with its title row level with it, drops down the rail for the
  lower rings, and slides to the gear when settings opens. It used to point at
  its own middle, which landed wherever the callout's height put it.

## [1.5.0] — 2026-09-18

### Added
- **Favourite subscription.** Click a cell in the subscription strip to make it
  the one its provider opens on and its ring reports; it is marked ★ and kept
  across launches. Hovering another cell looks at it for as long as the HUD is
  open; closing the HUD returns to the favourite. Click the favourite again to
  clear it.
- **Grok Bot has its own ring**, under Cursor's, with the Grok Bot app's icon.
  Its allowance comes from the same Cursor dashboard read as before, but it no
  longer shares Cursor's pop-out. The ring appears once a read shows the Cursor
  plan includes Grok Bot, so a plan without it (or a pooled enterprise plan)
  shows nothing extra. The rail is 318 pt with four rings.

### Changed
- The settings gear is always visible at the bottom of the rail instead of
  appearing when the pointer nears it.
- **The subscription switcher is its own row.** The pop-out's title stays
  `Claude usage`; underneath it, every signed-in subscription gets an equal-width
  cell — name over percent — in one segmented strip. Two cells read as well as
  five. With five, the title, refresh button, and limits no longer overflow the
  callout, and names are no longer cut to three letters (`cc-`, `per`, `ant`);
  a name that is too long for its cell trails off, and hovering it shows the full
  name. The callout is one row taller when a provider has more than one
  subscription.
- The callout shares the rail's top edge instead of centring on it. Providers
  have different numbers of limits, so the centred callout carried its title and
  refresh button up and down with every switch.

### Fixed
- Hovering a subscription cell switches to it. Hover inside the HUD only reported
  while uNotch was the active app, and a menu bar app hovered from another app's
  window never is, so the cells only answered clicks. Every hover in the HUD now
  tracks the way the panel itself does, including the highlights on the gear and
  the settings buttons.
- The refresh arrow no longer bounces or keeps turning after moving quickly
  through the providers. Hovering a ring starts a read when its usage is stale,
  and the arrow used to spring back to rest on every change of state; the turning
  arrow now reads its angle from the clock and crossfades with the still one.

## [1.4.0] — 2026-09-18

### Added
- **Multiple Codex subscriptions.** A second Codex sign-in kept in its own home —
  `CODEX_HOME=~/.codex-work codex` — joins Codex's pop-out the same way Claude's
  do. uNotch recognises a Codex home by its `auth.json` sitting beside something
  only Codex writes (`config.toml`, `installation_id`, …), so another tool's `auth.json`
  is never mistaken for one.
- Codex sign-in is validated like Claude's: a signed-out Codex says **Sign in
  with Codex CLI**, and a signed-out extra subscription stays hidden.

### Changed
- Extra subscriptions are found by what the folder is, not what it is called.
  Any folder counts — `~/.cc-work`, `~/claude_personal`,
  `~/.config/anthropic-team` — as long as the CLI has used it as its home. 1.3.0
  only noticed folders named `~/.claude-*`. The switcher label is the folder's
  name with the dot and any provider prefix removed.
- With three or more subscriptions, the unselected ones in the switcher shrink to
  a few letters; hovering one opens it back up.

Cursor Agent keeps one sign-in per Mac user regardless of `CURSOR_CONFIG_DIR`, so
it has no extra subscriptions to find; its sign-in check is unchanged.

## [1.3.0] — 2026-09-18

### Added
- **Multiple Claude subscriptions.** A second Claude Code sign-in kept in its own
  config directory — for example
  `alias cc-dev='CLAUDE_CONFIG_DIR=~/.claude-dev claude'` — shows up in Claude's
  pop-out. The rail keeps one ring per provider; when more than one subscription
  is signed in, the pop-out's title becomes a switcher (`Claude 86%` · `dev 40%`)
  named from the folder. Hover or click one to see its limits; the ring follows
  it, and the menu bar menu lists them all. uNotch finds these by looking for
  `~/.claude-*/.claude.json`; there is nothing to configure.
- Only signed-in subscriptions are offered. A signed-out one stays hidden and
  returns within a minute of signing back in.

### Fixed
- A signed-out Claude Code says **Sign in with Claude Code** instead of
  "Claude CLI returned no plan limits".

## [1.2.4] — 2026-09-15

### Fixed
- Cursor's rail ring follows **Cursor Models**. Other Models and Grok Bot stay in
  the callout.

## [1.2.3] — 2026-09-15

### Fixed
- Claude's rail ring follows the **5-hour** session window. Fable and the weekly
  all-models limit stay in the callout; they no longer steal the glanceable
  percent when they are more depleted.

## [1.2.2] — 2026-09-15

### Changed
- Cursor usage now shows **Cursor Models**, **Other Models**, and **Grok Bot**,
  matching the dashboard. Those numbers come from Cursor's free dashboard usage
  RPCs using the local Agent session; the Agent `/usage` screen remains the
  fallback if the session token is unavailable.
- Claude usage includes the weekly **Fable** limit alongside the 5-hour and
  all-models weekly windows.
- Codex usage notes banked **resets available** when the account has any.

## [1.2.1] — 2026-09-10

### Changed
- T3 Code uses the canonical logo through the checked-in project configuration.
- The logo now depicts a screen with a notch tucked into its left edge, across
  the app icon, menu bar, settings, website, and favicons.
- Link previews now show a designed share card with the tagline and usage HUD,
  with complete Open Graph and Twitter image metadata.

## [1.2.0] — 2026-09-07

### Added
- **The rail fits what you have.** uNotch checks which provider CLIs are installed
  (`claude`, `codex`, `agent`) and shows only those. With two providers the rail is
  186 pt; with one, 120 pt. The check reruns every refresh, so installing a CLI
  later adds its ring within a minute. If none are found, all three stay visible
  with their "not found" messages.
- `scripts/publish-release.sh` builds, notarizes, verifies, tags, and publishes a
  release with all three assets in one step.

### Changed
- A provider whose CLI is missing can no longer be the selected one; the first
  installed provider is selected instead.

## [1.1.0] — 2026-09-07

### Added
- **Settings dock.** Hovering near the bottom of the expanded HUD reveals a gear.
  It opens a small section with a Left/Right side picker, a drag handle to move
  the HUD, **Update & Restart**, and **Quit** — the entire settings surface.
- **Update & Restart.** A user-initiated updater that reads the latest GitHub
  release, downloads the `-arm64.dmg`, refuses anything not signed by the same
  Team ID or rejected by Gatekeeper, swaps the bundle, and relaunches. Also
  available from the menu bar menu, which now shows the running version.
- **Brand.** A brand canon in `brand/` (BRAND.md, tokens, logo variants), a
  generated `DESIGN.md` in Google Stitch format, and `Brand` tokens in Swift. The
  idle edge cue now carries the mint status point; the selected provider's ring
  and the usage bars are mint.
- **Website.** A single-page site in `site/`, served by Caddy on Railway and deployed from CI, on an Aetheria emerald-flow backdrop with the same three-layer treatment and colophon footer as sethmedina.com.
- Open-source scaffolding: MIT license, contributing guide, code of conduct,
  issue and pull request templates, CODEOWNERS, CI, Dependabot for Actions.

### Changed
- The expanded HUD is 252 pt tall (was 220) to make room for the rail footer.
- The Codex app-server handshake reports the real bundle version.
- `PRIVACY.md` and `SECURITY.md` document the updater's single network request
  and its verification steps.

### Removed
- The release DMG and checksums are no longer committed to the repository; they
  live on GitHub Releases. `dist/` is ignored.

## [1.0.0] — 2026-09-04

### Added
- Initial release: edge cue, provider rail, usage callout for Claude, Codex, and
  Cursor Agent; menu bar item; signed and notarized DMG.

[Unreleased]: https://github.com/SethMed7/unotch/compare/v1.8.1...HEAD
[1.8.1]: https://github.com/SethMed7/unotch/compare/v1.8.0...v1.8.1
[1.8.0]: https://github.com/SethMed7/unotch/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/SethMed7/unotch/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/SethMed7/unotch/compare/v1.5.4...v1.6.0
[1.5.4]: https://github.com/SethMed7/unotch/compare/v1.5.3...v1.5.4
[1.5.3]: https://github.com/SethMed7/unotch/compare/v1.5.2...v1.5.3
[1.5.2]: https://github.com/SethMed7/unotch/compare/v1.5.1...v1.5.2
[1.5.1]: https://github.com/SethMed7/unotch/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/SethMed7/unotch/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/SethMed7/unotch/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/SethMed7/unotch/compare/v1.2.4...v1.3.0
[1.2.4]: https://github.com/SethMed7/unotch/compare/v1.2.3...v1.2.4
[1.2.3]: https://github.com/SethMed7/unotch/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/SethMed7/unotch/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/SethMed7/unotch/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/SethMed7/unotch/compare/v1.0.0...v1.2.0
[1.1.0]: https://github.com/SethMed7/unotch/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/SethMed7/unotch/releases/tag/v1.0.0
