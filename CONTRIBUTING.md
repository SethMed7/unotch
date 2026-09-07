# Contributing to uNotch

Thanks for looking. uNotch is small on purpose, and contributions that keep it small
are the ones most likely to land.

## What uNotch is, and is not

uNotch shows local AI usage limits in a glass HUD at the screen edge. It is:

- native Swift with **no third-party dependencies**
- **privacy-first**: no accounts, no telemetry, no network traffic except the
  user-initiated Update & Restart
- **quiet**: one accent colour, one shadow, a settings surface with exactly four
  controls (side, position, update, quit)

Good contributions: a new provider read from a local CLI, a parser fix when a CLI
changes its output, accessibility improvements, a bug fix with a test. Things that
will be declined: dependencies, analytics of any kind, a preferences window, cloud
features, or anything that needs an API key typed into uNotch.

If you are unsure whether an idea fits, open an issue first and describe the
problem you are solving. That is cheaper for both of us than a pull request.

## Setup

```sh
git clone https://github.com/SethMed7/unotch.git
cd unotch
swift test          # parsers, state, hover geometry, updater, render checks
swift run uNotch    # runs the app from the package (unsigned, no updater)
```

Requirements: macOS 14+, Xcode 15.3+ / Swift 5.10+. There is nothing to install.

Local snapshots of the HUD and settings section can be written from the tests:

```sh
UNOTCH_SNAPSHOT=/tmp/hud.png UNOTCH_SETTINGS_SNAPSHOT=/tmp/settings.png swift test
```

The website is `site/index.html`; `scripts/build-site.sh` assembles it with the
brand tokens into `_site/` for a local preview (`python3 -m http.server -d _site`).

## Making a change

1. Fork and branch from `main`. Branch names are not enforced.
2. Keep the change focused. One fix or one feature per pull request.
3. Add or update a test in `Tests/uNotchTests` when behaviour changes. Parsers in
   particular must have a fixture-based test.
4. Run `swift test` and make sure it is green.
5. If you touched the UI, read `DESIGN.md` and `brand/BRAND.md` first. The named
   rules there (Status Point, Numeral, One Shadow, Hairline) are the review bar.
6. If you touched anything that reads, stores, or sends data, update `PRIVACY.md`
   and `SECURITY.md` in the same pull request. The docs must stay true.
7. Add a line to `CHANGELOG.md` under **Unreleased**.
8. Open the pull request against `main` and fill in the template.

Commit messages describe *why*, not just what.

## Code style

- Swift strict concurrency; `@MainActor` for UI state, actors or detached tasks for
  process execution.
- Minimal abstraction. Prefer a direct function over a protocol until there is a
  second implementation (the `UsageFetching` and `ReleaseSource` protocols exist
  because tests need them).
- Never surface raw CLI output or standard error in the UI. Map failures to short,
  fixed messages.
- Colours, radii, and motion come from `Brand` in `Sources/uNotch/Brand.swift`,
  which mirrors `brand/tokens.json`. Do not introduce ad-hoc values.

## Review and merging

`main` is protected. Every change lands through a pull request that:

- passes CI (`swift build` and `swift test` on macOS), and
- is approved by the code owner (`@SethMed7`, see `.github/CODEOWNERS`).

Pull requests are squash-merged to keep history linear. Stale approvals are
dismissed when new commits are pushed. The maintainer may push small follow-up
commits (typos, changelog) to a contributor's branch before merging.

## Releasing (maintainer)

Releases are built locally and signed with a Developer ID that lives only in the
maintainer's Keychain; CI never sees signing material.

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist`, the default
   `VERSION` in `scripts/build-dmg.sh`, and move the **Unreleased** changelog
   section under the new version.
2. `APPLE_SIGNING_IDENTITY=… NOTARY_PROFILE=… ./scripts/build-dmg.sh`
3. Tag `vX.Y.Z`, create the GitHub release, and attach `dist/uNotch-X.Y.Z-arm64.dmg`
   and `dist/SHA256SUMS`. The asset name must end in `-arm64.dmg` — the in-app
   updater looks for that suffix.

## Reporting security issues

Do not open a public issue. Use
[private vulnerability reporting](https://github.com/SethMed7/unotch/security/advisories/new).
See `SECURITY.md`.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be kind and
be specific.
