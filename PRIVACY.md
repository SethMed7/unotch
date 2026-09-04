# uNotch privacy

uNotch is designed to show local usage data without creating another account or
data service.

## Data uNotch reads

When it starts, refreshes on its timer, or receives a hover/manual refresh,
uNotch launches installed provider command-line tools and reads their usage
output:

- Claude Code: 5-hour and weekly plan usage
- Codex: available account rate-limit windows
- Cursor Agent: authentication state and included monthly usage

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

The uNotch code does not make its own network requests and does not run a local
server or listen on a port. It includes no analytics, telemetry, advertising,
tracking pixels, or third-party crash-reporting SDKs.

The provider CLIs launched by uNotch may contact their respective services and
may maintain their own authentication records, caches, or logs. Those behaviors
are controlled by the provider tools and their privacy terms, not by uNotch.

macOS may collect system diagnostics according to the user's operating-system
settings. uNotch does not add a separate diagnostics service.

## Credentials

uNotch never requests or reads API keys directly. It relies on the normal
authentication state of each installed CLI. Signing and notarization credentials
used to build a release remain in the release operator's Keychain and are not
stored in this repository or bundled with the app.
