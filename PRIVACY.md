# uNotch privacy

uNotch is designed to show local usage data without creating another account or
data service.

## Data uNotch reads

When it starts, refreshes on its timer, or receives a hover/manual refresh,
uNotch launches installed provider command-line tools and reads their usage
output:

- Claude Code: 5-hour, weekly, and Fable plan usage. When a read returns no
  limits, uNotch also runs `claude auth status` and uses only its signed-in flag.
- Codex: available account rate-limit windows and banked reset counts. When a
  read fails, uNotch also runs `codex login status` and uses only its exit code.
- Additional Claude Code and Codex sign-ins: uNotch lists the names in your home
  folder and in `~/.config`, and checks whether each folder there contains the
  files that CLI leaves in its home (`.claude.json` for Claude Code; `auth.json`
  beside `config.toml`, `version.json`, or `installation_id` for Codex). It checks that the files exist and never opens
  them. It goes no deeper, and it never looks inside Desktop, Documents,
  Downloads, Library, Movies, Music, Pictures, Public, or Applications. Each
  sign-in found is read by launching the same CLI with `CLAUDE_CONFIG_DIR` or
  `CODEX_HOME` set to that folder; the CLI may update its own files there, as it
  does whenever you run it. A sign-in that reports signed out is hidden from the
  HUD.
- Cursor: authentication state, then Cursor Models and Other Models usage. The
  preferred source is Cursor's dashboard usage RPC (`GetCurrentPeriodUsage` on
  `api2.cursor.sh`). The default sign-in is authenticated with the existing
  `cursor-access-token` keychain item created by Cursor Agent. A second sign-in
  is the folder `CURSOR_CONFIG_DIR` pointed at. Its token is read from that
  folder's `auth.json`, from the keychain item named after the folder, or from
  `~/.cursor/auth.json` when that token is the account named in the folder.
  The token is read into
  memory for that request and is not stored. Account ids are used only to tell
  two sign-ins apart and are not shown. If the default token cannot be read,
  uNotch falls back to scraping Agent CLI `/usage`.
- Grok Bot: its allowance, through the same Cursor sign-in
  (`GetSandUsageStatus` on `api2.cursor.sh`, with the same token handling). A
  plan without Grok Bot reports no allowance, and nothing is shown.

The output can contain usage percentages, reset times, and provider account
metadata. uNotch extracts only the values needed for the HUD. Raw standard error
is discarded. Standard output exists only in process memory while it is parsed.

## Data uNotch stores

uNotch stores three preferences through macOS `UserDefaults`:

- selected screen edge
- vertical position on the screen
- the favourite subscription per provider, if you have set one: the provider's
  name and, for an extra sign-in, the path of its config folder (for example
  `~/.claude-dev`)

It does not persist usage output, account identifiers, prompts, projects,
credentials, or command history.

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
