#!/bin/sh
# Render the share card from its template and the site's actual HUD.
# Requires Python 3, Playwright CLI + Chromium, and ImageMagick (magick).
# On macOS, Chromium uses the same installed system fonts as the site.
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:-$repo_root/site/assets/unotch-social-v2.png}"
work="$(mktemp -d "${TMPDIR:-/tmp}/unotch-social.XXXXXX")"
trap 'rm -rf "$work"' EXIT HUP INT TERM
"$repo_root/scripts/build-site.sh" "$work/site" >/dev/null
python3 - "$repo_root" "$work/site" <<'PY'
from pathlib import Path
import re
import sys
root, out = map(Path, sys.argv[1:])
site = (root / 'site/index.html').read_text()
styles = re.search(r'<style>(.*?)</style>', site, re.S).group(1)
start = site.index('        <div class="hud-wrap">')
end = site.index('        <p class="hint">', start)
card = (root / 'brand/social/card.html').read_text()
card = card.replace('{{SITE_STYLES}}', styles).replace('{{HUD}}', site[start:end])
(out / 'social.html').write_text(card)
PY
npx --no-install playwright screenshot --browser chromium --viewport-size='1200,630' \
  --wait-for-timeout=500 "file://$work/site/social.html" "$work/card.png"
mkdir -p "$(dirname "$output")"
# Save an opaque RGB PNG; no runtime rendering is required on the server.
magick "$work/card.png" -alpha off -define png:color-type=2 \
  -set comment 'Source: brand/social/card.html; HUD from site/index.html; backdrop from the existing Aetheria emerald render, seed 805214.' "$output"
printf '%s\n' "$output"
