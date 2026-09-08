#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h}"
version="${VERSION:-1.2.0}"
build_number="${BUILD_NUMBER:-1}"
target_arch="${ARCH:-arm64}"
developer_id="${APPLE_SIGNING_IDENTITY:-}"
notary_profile="${NOTARY_PROFILE:-}"
app_name="uNotch"

cd "$repo_root"
swift build -c release --arch "$target_arch"
binary_dir="$(swift build -c release --arch "$target_arch" --show-bin-path)"

release_root="$repo_root/.build/release-bundle"
app_bundle="$release_root/$app_name.app"
iconset="$release_root/AppIcon.iconset"
disk_root="$release_root/disk"
dmg_path="$repo_root/dist/$app_name-$version-$target_arch.dmg"
checksum_path="$repo_root/dist/SHA256SUMS"

rm -rf "$release_root"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources" "$iconset" "$disk_root" "$repo_root/dist"

cp "$binary_dir/$app_name" "$app_bundle/Contents/MacOS/$app_name"
cp "$repo_root/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app_bundle/Contents/Info.plist"

swift "$repo_root/scripts/generate-icon.swift" "$iconset"
iconutil -c icns "$iconset" -o "$app_bundle/Contents/Resources/AppIcon.icns"

if [[ -z "$developer_id" ]]; then
    developer_id="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
        | sed -n '1p')"
fi
if [[ -z "$developer_id" ]]; then
    developer_id="-"
fi

codesign --force --deep --options runtime --timestamp --sign "$developer_id" "$app_bundle"
codesign --verify --deep --strict --verbose=2 "$app_bundle"

if [[ -n "$notary_profile" ]]; then
    if [[ "$developer_id" == "-" ]]; then
        echo "A Developer ID Application identity is required for notarization." >&2
        exit 1
    fi
    app_archive="$release_root/$app_name-app.zip"
    ditto -c -k --keepParent "$app_bundle" "$app_archive"
    xcrun notarytool submit "$app_archive" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$app_bundle"
    xcrun stapler validate "$app_bundle"
    rm -f "$app_archive"
fi

cp -R "$app_bundle" "$disk_root/$app_name.app"
ln -s /Applications "$disk_root/Applications"
rm -f "$dmg_path"
hdiutil create \
    -volname "$app_name" \
    -srcfolder "$disk_root" \
    -ov \
    -format UDZO \
    "$dmg_path"
codesign --force --timestamp --sign "$developer_id" "$dmg_path"
codesign --verify --verbose=2 "$dmg_path"

if [[ -n "$notary_profile" ]]; then
    xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
fi

# A stable-named copy lets the website link to
# releases/latest/download/uNotch-arm64.dmg without a version in the URL.
stable_dmg_path="$repo_root/dist/$app_name-$target_arch.dmg"
cp "$dmg_path" "$stable_dmg_path"

(cd "$repo_root/dist" && shasum -a 256 "${dmg_path:t}" "${stable_dmg_path:t}") > "$checksum_path"

echo "$dmg_path"
echo "$stable_dmg_path"
