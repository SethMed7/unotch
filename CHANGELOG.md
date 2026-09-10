# Changelog

All notable changes to uNotch are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
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

[Unreleased]: https://github.com/SethMed7/unotch/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/SethMed7/unotch/compare/v1.0.0...v1.2.0
[1.1.0]: https://github.com/SethMed7/unotch/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/SethMed7/unotch/releases/tag/v1.0.0
