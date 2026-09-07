#!/bin/sh
# Assembles the static site into _site/ for GitHub Pages or local preview.
# The page consumes the brand canon directly, so tokens and logos are copied in.
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$repo_root/_site}"

rm -rf "$out"
mkdir -p "$out/brand/logo"
cp -R "$repo_root/site/." "$out/"
cp "$repo_root/brand/tokens.css" "$out/brand/tokens.css"
cp "$repo_root"/brand/logo/*.svg "$out/brand/logo/"
touch "$out/.nojekyll"

echo "$out"
