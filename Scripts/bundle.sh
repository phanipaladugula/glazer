#!/usr/bin/env bash
# Builds Glazer and packages it as dist/Glazer.app.
#
# Usage: Scripts/bundle.sh [--debug] [--open]
#   --debug  Build the debug configuration instead of release.
#   --open   Launch the app when done (quits a running copy first).
#
# The app is signed ad hoc. That is enough to run it on this Mac and for macOS to
# remember its camera permission between builds.
set -euo pipefail

cd "$(dirname "$0")/.."

configuration=release
open_when_done=false
for argument in "$@"; do
    case "$argument" in
        --debug) configuration=debug ;;
        --open) open_when_done=true ;;
        *) echo "Unknown option: $argument" >&2; exit 64 ;;
    esac
done

version="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
version="${version:-0.0.0}"
build="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

echo "Building Glazer $version ($build), $configuration…"
swift build --configuration "$configuration" --product Glazer
binary="$(swift build --configuration "$configuration" --show-bin-path)/Glazer"

app="dist/Glazer.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$binary" "$app/Contents/MacOS/Glazer"
sed -e "s/\$(VERSION)/$version/" -e "s/\$(BUILD)/$build/" \
    Resources/Info.plist > "$app/Contents/Info.plist"
plutil -lint -s "$app/Contents/Info.plist"

codesign --force --sign - --options runtime "$app"

echo "Built $app"

if $open_when_done; then
    pkill -x Glazer 2>/dev/null || true
    open "$app"
fi
