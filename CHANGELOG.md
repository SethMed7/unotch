# Changelog

All notable changes to uNotch are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/SethMed7/unotch/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/SethMed7/unotch/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/SethMed7/unotch/compare/v1.2.4...v1.3.0
[1.2.4]: https://github.com/SethMed7/unotch/compare/v1.2.3...v1.2.4
[1.2.3]: https://github.com/SethMed7/unotch/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/SethMed7/unotch/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/SethMed7/unotch/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/SethMed7/unotch/compare/v1.0.0...v1.2.0
[1.1.0]: https://github.com/SethMed7/unotch/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/SethMed7/unotch/releases/tag/v1.0.0
