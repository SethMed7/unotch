#!/bin/zsh
# Builds, notarizes, verifies, tags, and publishes a uNotch release in one step.
#
#   ./scripts/publish-release.sh [version]
#   NOTARY_PROFILE=<keychain profile> ./scripts/publish-release.sh [version]
#
# The version defaults to CFBundleShortVersionString in Resources/Info.plist and
# must have a matching "## [version]" section in CHANGELOG.md (used as the notes).
# Public releases are always notarized: the website's download button and the
# in-app updater both rely on Gatekeeper accepting the DMG. NOTARY_PROFILE names
# a notarytool keychain profile; the default is the one shared by Seth's Mac apps
# (rotli uses the same). Nothing secret lives in this file or the repo.
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
cd "$repo_root"

version="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
tag="v$version"
NOTARY_PROFILE="${NOTARY_PROFILE:-rotli-notary}"
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "No notarytool keychain profile named '$NOTARY_PROFILE'." >&2
    echo "Create one: xcrun notarytool store-credentials $NOTARY_PROFILE --key <AuthKey.p8> --key-id <id> --issuer <issuer-uuid>" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean; commit or stash first." >&2
    exit 1
fi
if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "Releases are cut from main." >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "Tag $tag already exists." >&2
    exit 1
fi

notes="$(awk -v v="$version" '
    $0 ~ "^## \\[" v "\\]" { on = 1; next }
    /^## \[/ { on = 0 }
    on { print }
' CHANGELOG.md | sed -e '/./,$!d')"
if [[ -z "$notes" ]]; then
    echo "CHANGELOG.md has no section for [$version]." >&2
    exit 1
fi

VERSION="$version" NOTARY_PROFILE="$NOTARY_PROFILE" ./scripts/build-dmg.sh

versioned="dist/uNotch-$version-arm64.dmg"
stable="dist/uNotch-arm64.dmg"
xcrun stapler validate "$versioned"
spctl --assess --type open --context context:primary-signature "$versioned"
(cd dist && shasum -a 256 -c SHA256SUMS)

git tag -a "$tag" -m "uNotch $version"
git push origin "$tag"
gh release create "$tag" "$versioned" "$stable" dist/SHA256SUMS \
    --title "uNotch $version" \
    --notes "$notes"

echo "Published $tag. The website's download button now serves uNotch $version."
