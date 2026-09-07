# uNotch security

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Use
[GitHub private vulnerability reporting](../../security/advisories/new) and
include the affected version, macOS version, reproduction steps, and potential
impact. Reports can be coordinated privately before disclosure.

## Supported versions

Security fixes are applied to the latest published release. Older builds should
be upgraded before reporting behavior that is no longer reproducible.

## Security model

uNotch is a local menu bar utility. It has no backend, listening socket, account
system, background updater, browser component, or third-party package dependency.

Release protections include:

- Developer ID signing with hardened runtime
- Apple notarization and stapling for both the app and DMG
- GitHub secret scanning, push protection, dependency alerts, and private
  vulnerability reporting
- a protected `main` branch: every change lands through a pull request that the
  maintainer reviews, with CI required to pass
- fixed command arguments, execution timeouts, and bounded Codex response
  capture
- in-memory parsing with raw CLI standard error discarded

## Update & Restart

Updating is manual: it runs only when you choose **Update & Restart**. The flow
is `AppUpdater` → `ReleaseInstaller` in `Sources/uNotch/AppUpdater.swift`:

1. Read the latest release from the GitHub REST API over HTTPS.
2. Compare its tag with the running `CFBundleShortVersionString`. If nothing is
   newer, uNotch simply relaunches.
3. Download the `-arm64.dmg` asset to a private temporary file and mount it
   read-only with `hdiutil`.
4. Refuse the update unless the mounted `uNotch.app` passes
   `SecStaticCodeCheckValidity`, is signed by the **same Team ID** as the running
   app, and is accepted by `spctl --assess --type execute` (Gatekeeper /
   notarization). Development builds without a Team ID cannot self-update.
5. Swap the bundle in place (copy → rename old → rename new → delete old) and
   relaunch. The old bundle is restored if the swap fails midway.

The updater never elevates privileges. If the app lives somewhere the current
user cannot write, the update fails with a message and the installed app is left
untouched.

## Trust boundaries

uNotch launches executable files named `claude`, `codex`, and `agent` from a
small set of standard local install locations. A local user or process able to
replace those executables already controls the same user account and can affect
what uNotch runs.

The Cursor usage reader opens Cursor Agent in a new, private temporary workspace
with `--trust`, sends only `/usage`, reads the usage screen, exits, and removes
the workspace. Paths are passed as environment values rather than interpolated
into a shell command.

The application is not App Sandbox-enabled because its core function requires
launching separately installed command-line tools. It does not request
Accessibility, Screen Recording, Full Disk Access, microphone, camera, contacts,
calendar, or location permission.

Provider CLIs remain responsible for their own authentication, networking,
updates, local caches, and security behavior.

## Verify a release

```sh
shasum -a 256 -c SHA256SUMS
xcrun stapler validate uNotch-arm64.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 \
  uNotch-arm64.dmg
```

After copying the app to Applications, its signature can also be checked:

```sh
codesign --verify --deep --strict --verbose=2 /Applications/uNotch.app
spctl --assess --type execute --verbose=2 /Applications/uNotch.app
```

The signer name and Apple Team ID shown by macOS are public certificate metadata
required for a Gatekeeper-approved Developer ID release. Private signing keys
and notarization credentials are not embedded in the app.
