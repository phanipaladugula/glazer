#!/usr/bin/env bash
# Renders the app icon from Resources/Icon/AppIcon.svg.
#
# Usage: Scripts/icon.sh
#
# Writes Resources/Glazer.icns (every size macOS uses, from 16 pt to 512 pt @2x) and
# docs/images/icon.png (for the README). Both are committed, so building the app doesn't
# need this script; run it only after changing the SVG.
#
# Needs Google Chrome or Chromium to render the SVG (set CHROME_PATH to use another), and
# iconutil and sips, which come with macOS.
set -euo pipefail

cd "$(dirname "$0")/.."

chrome="${CHROME_PATH:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [[ ! -x "$chrome" ]]; then
    echo "Chrome not found at $chrome. Set CHROME_PATH." >&2
    exit 69
fi

source_svg="$PWD/Resources/Icon/AppIcon.svg"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

# Render the SVG at 1024 × 1024 on a transparent background.
cat > "$workspace/render.html" <<EOF
<!doctype html>
<html><body style="margin:0;background:transparent">
<img src="file://$source_svg" width="1024" height="1024" style="display:block">
</body></html>
EOF
"$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size=1024,1024 \
    --screenshot="$workspace/icon-1024.png" "file://$workspace/render.html" 2>/dev/null

# Every size in a macOS icon set: each point size at 1x and 2x.
iconset="$workspace/Glazer.iconset"
mkdir -p "$iconset"
for points in 16 32 128 256 512; do
    sips -z "$points" "$points" "$workspace/icon-1024.png" --out "$iconset/icon_${points}x${points}.png" >/dev/null
    pixels=$((points * 2))
    sips -z "$pixels" "$pixels" "$workspace/icon-1024.png" --out "$iconset/icon_${points}x${points}@2x.png" >/dev/null
done

iconutil --convert icns --output Resources/Glazer.icns "$iconset"
sips -z 256 256 "$workspace/icon-1024.png" --out docs/images/icon.png >/dev/null

echo "Wrote Resources/Glazer.icns and docs/images/icon.png"
