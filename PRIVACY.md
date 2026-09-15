# uNotch privacy

uNotch is designed to show local usage data without creating another account or
data service.

## Data uNotch reads

When it starts, refreshes on its timer, or receives a hover/manual refresh,
uNotch launches installed provider command-line tools and reads their usage
output:

- Claude Code: 5-hour, weekly, and Fable plan usage
- Codex: available account rate-limit windows and banked reset counts
- Cursor: authentication state, then Cursor Models, Other Models, and Grok Bot
  usage. The preferred source is Cursor's dashboard usage RPCs
  (`GetCurrentPeriodUsage` and `GetSandUsageStatus` on `api2.cursor.sh`),
  authenticated with the existing `cursor-access-token` keychain item created
  by Cursor Agent. The token is read into memory for that request and is not
  stored. If the token cannot be read, uNotch falls back to scraping Agent
  CLI `/usage`, which does not include Grok Bot.

The output can contain usage percentages, reset times, and provider account
metadata. uNotch extracts only the values needed for the HUD. Raw standard error
is discarded. Standard output exists only in process memory while it is parsed.

## Data uNotch stores

uNotch stores two preferences through macOS `UserDefaults`:

- selected screen edge
- vertical position on the screen

It does not persist usage output, provider identifiers, prompts, projects,
filenames, credentials, or command history.

To remove its preferences:

```sh
defaults delete app.unotch.utility
```

## Network and analytics

uNotch makes two kinds of network request, both over HTTPS:

- **Update & Restart**, only when you ask for it. That flow requests the latest
  release metadata from `api.github.com` and, if that release is newer than the
  running version, downloads its installer from `github.com`. Those requests
  carry the standard HTTP headers plus a `uNotch/<version>` user agent — no
  account, device, or usage information. Nothing is checked on a timer or at
  launch, and nothing is installed without that click.
- **Cursor usage**, on the same refresh cycle as the other providers. uNotch
  posts empty JSON bodies to Cursor's dashboard usage RPCs on `api2.cursor.sh`
  with the local session token as a bearer. Those endpoints report plan usage;
  they do not run models or spend included usage. The response is parsed in
  memory for percentages and reset times only.

uNotch does not run a local server or listen on a port. It includes no
analytics, telemetry, advertising, tracking pixels, or third-party
crash-reporting SDKs.

The provider CLIs launched by uNotch may contact their respective services and
may maintain their own authentication records, caches, or logs. Those behaviors
are controlled by the provider tools and their privacy terms, not by uNotch.

macOS may collect system diagnostics according to the user's operating-system
settings. uNotch does not add a separate diagnostics service.

## Credentials

uNotch never asks you to type an API key. It relies on the normal
authentication state of each installed CLI. For Cursor dashboard usage it
reads the existing `cursor-access-token` keychain item created by Cursor
Agent, uses it for that HTTPS request, and does not persist it. Signing and
notarization credentials used to build a release remain in the release
operator's Keychain and are not stored in this repository or bundled with
the app.
