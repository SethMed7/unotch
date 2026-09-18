<p align="center">
  <img src="brand/logo/icon.svg" width="112" height="112" alt="uNotch logo">
</p>

<h1 align="center">uNotch</h1>

<p align="center">
  Live AI usage, quietly tucked into the edge of your Mac.
</p>

<p align="center">
  <a href="https://github.com/SethMed7/unotch/releases/latest/download/uNotch-arm64.dmg"><strong>Download for Apple silicon</strong></a>
  · <a href="https://unotch.sethmedina.com/">Website</a>
  · macOS 14+
  · Native Swift
  · MIT
</p>

<p align="center">
  <a href="https://github.com/SethMed7/unotch/actions/workflows/ci.yml"><img src="https://github.com/SethMed7/unotch/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-3BE29B?labelColor=15191B" alt="MIT license"></a>
  <a href="https://github.com/SethMed7/unotch/releases/latest"><img src="https://img.shields.io/github/v/release/SethMed7/unotch?color=3BE29B&labelColor=15191B&label=release" alt="Latest release"></a>
</p>

uNotch is a lightweight menu bar utility for Claude, Codex, and Cursor Agent.
Its nearly hidden edge cue expands into a glass usage HUD when you hover — no
dashboard window and no Dock icon.

## What it monitors

| Provider | Local source | Usage shown |
| --- | --- | --- |
| Claude | Claude Code CLI `/usage` | 5-hour, weekly, and Fable limits |
| Codex | Codex app-server rate limits | Plan windows, plus banked resets when any remain |
| Cursor | Cursor dashboard usage RPCs (Agent `/usage` fallback) | Cursor Models and Other Models |
| Grok Bot | Cursor dashboard usage RPCs, through the Cursor sign-in | Grok Bot's own allowance |

All usage is read from command-line tools already authenticated on your Mac.
uNotch does not ask for, copy, or store provider credentials. Only the providers
whose CLI is installed appear; the rail sizes to fit one to four. Grok Bot has no
CLI of its own — its ring sits under Cursor's and appears once a read shows your
Cursor plan includes it.

### More than one subscription

If you keep a second Claude Code or Codex sign-in in its own folder, uNotch finds
it automatically:

```sh
alias cc-dev='CLAUDE_CONFIG_DIR=~/.claude-dev claude'
alias cx-work='CODEX_HOME=~/.codex-work codex'
```

The folder and the alias can be called anything. uNotch looks one level into your
home folder and `~/.config` for a directory the CLI has used as its home — Claude
Code leaves a `.claude.json` there; Codex leaves an `auth.json` beside its
`config.toml` — and reads it with the same environment variable.
The label comes from the folder name (`~/.claude-dev` → `dev`).

Each provider still has one ring. Once a second subscription is signed in, a
strip appears under the pop-out's title with one cell per subscription — its name
over its remaining percent. **Hover** a cell to look at it; the limits and the ring
follow. **Click** a cell to make it the favourite (marked ★): that is the one the
provider opens on and its ring reports whenever the HUD is closed. Click it again
to clear. The cells share the row equally, so five subscriptions read as cleanly
as two; a long name trails off, and hovering it shows the full name. A
subscription that is signed out is not shown; sign in with your alias and it
appears within a minute. Cursor Agent keeps a single sign-in per Mac user, so it
always has exactly one.

## Install

1. [Download `uNotch-arm64.dmg`](https://github.com/SethMed7/unotch/releases/latest/download/uNotch-arm64.dmg) — the latest signed release. Release notes are on the [releases page](https://github.com/SethMed7/unotch/releases/latest).
2. Open it and drag **uNotch** into **Applications**.
3. Launch uNotch from Applications. Its mark appears in the menu bar.

The release app and DMG are Developer ID signed, Apple notarized, and stapled.
The installer supports Apple silicon Macs running macOS 14 Sonoma or newer.

## Use

- Move the pointer to the subtle cue at the screen edge and hold for 150 ms to
  reveal the HUD.
- Hover a provider logo to switch providers and refresh stale usage. The hovered
  ring and its percent turn red when remaining is under 10% — a full red circle
  even at 0%. 10% and above stay mint. Providers without an installed CLI are not shown; install one and its
  ring appears within a minute.
- Use the refresh control for an immediate read from the selected local CLI.
- Drag the rail vertically or across the display to place it on either edge.
- Hover the settings gear at the bottom of the rail. The section hangs from the
  gear so you can move into it, and it holds everything uNotch can be told:
  - **Side** — dock to the left or right edge.
  - **Position** — a drag handle to move the HUD anywhere along the edge.
  - **Update & Restart** — fetch the latest signed release and relaunch.
  - **Quit**.
- The menu bar item offers the same refresh, edge, update, and quit actions.

The saved edge and vertical position are restored on the next launch.

## Privacy by design

- No analytics, telemetry, advertising, or crash-reporting SDKs.
- No uNotch account, cloud service, incoming server, or listening port.
- CLI output is parsed in memory and is not logged or written to disk.
- Raw CLI errors are discarded so account identifiers and local paths are not
  exposed in the interface.
- Only the screen edge and vertical position are stored in macOS preferences.
- Network use is **Update & Restart** (GitHub Releases, only when you click it)
  and Cursor dashboard usage RPCs that reuse the local Agent session. Those
  usage endpoints do not run models or spend included usage.

Provider CLIs still use their own network connections, authentication stores,
and caches. See [PRIVACY.md](PRIVACY.md) for the complete data flow and
[SECURITY.md](SECURITY.md) for trust boundaries, the update verification steps,
and how to report a vulnerability.

## Requirements

- macOS 14 or newer
- Apple silicon for the downloadable DMG
- At least one supported local CLI: `claude`, `codex`, or Cursor's `agent`

Missing or signed-out CLIs are shown as unavailable without affecting the other
providers.

## Build from source

The Swift package has no third-party package dependencies.

```sh
swift test
swift run uNotch
```

Create a local release DMG:

```sh
./scripts/build-dmg.sh
```

For a notarized distribution build, provide a Developer ID identity and a
`notarytool` profile stored in Keychain. Never put their real values in the
repository.

```sh
APPLE_SIGNING_IDENTITY="Developer ID Application: …" \
NOTARY_PROFILE="your-keychain-profile" \
./scripts/build-dmg.sh
```

The script signs the app with hardened runtime, optionally notarizes and
staples it, creates the DMG, then signs and optionally notarizes and staples the
installer.

## Verify a download

Download `SHA256SUMS` from the [same release](https://github.com/SethMed7/unotch/releases/latest), then run:

```sh
shasum -a 256 -c SHA256SUMS
xcrun stapler validate uNotch-arm64.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 \
  uNotch-arm64.dmg
```

`spctl` should report `accepted` with a notarized Developer ID source.

## Project layout

```text
Sources/uNotch/        AppKit windowing, SwiftUI UI, state, CLI readers, updater
Tests/uNotchTests/     Parser, state, hover geometry, updater, and render checks
brand/                 Brand canon: BRAND.md, tokens, logo variants
site/                  The single-page website (Caddy on Railway)
Resources/             macOS bundle metadata
scripts/               Icon generation and signed DMG packaging
DESIGN.md              Generated design system (Stitch format) for AI agents
```

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md)
first — it covers the scope uNotch keeps deliberately small, how to run the
tests, and the review flow. `main` is protected: changes land through reviewed
pull requests with CI passing.

## Security

Please do not disclose a suspected vulnerability in a public issue. Use
[GitHub's private vulnerability report](https://github.com/SethMed7/unotch/security/advisories/new)
so it can be investigated before publication.

## License

[MIT](LICENSE) © 2026 Seth Medina. Claude, Codex, ChatGPT, and Cursor are
trademarks of their respective owners; uNotch is an independent project and is
not affiliated with Anthropic, OpenAI, or Anysphere.
