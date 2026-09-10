#!/bin/sh
# Raster favicon exports all derive from the canonical SVG. Requires ImageMagick.
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source="$repo_root/brand/logo/favicon.svg"
for size in 16 32 180 192; do
  case "$size" in
    16|32) name="favicon-$size.png" ;;
    180) name="apple-touch-icon.png" ;;
    192) name="icon-192.png" ;;
  esac
  magick -background none -density 384 "$source" -resize "${size}x${size}" \
    -set comment 'Source: brand/logo/favicon.svg, uNotch screen-and-side-notch mark.' \
    "$repo_root/site/$name"
done
magick -background none -density 384 "$source" -define icon:auto-resize=48,32,16 "$repo_root/site/favicon.ico"
