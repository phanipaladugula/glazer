#!/usr/bin/env bash
# Builds Glazer and packages it as dist/Glazer.app.
#
# Usage: Scripts/bundle.sh [--debug] [--universal] [--open]
#   --debug      Build the debug configuration instead of release.
#   --universal  Build for both Apple silicon and Intel, as releases are.
#   --open       Launch the app when done (quits a running copy first).
#
# The app is signed with the hardened runtime. With a signing identity (see
# Scripts/signing.sh), every build has the same identity, so macOS keeps its permissions
# and Keychain access across builds. Without one it's signed ad hoc, and macOS treats
# each build as a new app.
set -euo pipefail

cd "$(dirname "$0")/.."

configuration=release
universal=false
open_when_done=false
for argument in "$@"; do
    case "$argument" in
        --debug) configuration=debug ;;
        --universal) universal=true ;;
        --open) open_when_done=true ;;
        *) echo "Unknown option: $argument" >&2; exit 64 ;;
    esac
done

version="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
version="${version:-0.0.0}"
build="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

app="dist/Glazer.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

if $universal; then
    # Building several architectures in one `swift build` needs Xcode's build system.
    # Building each on its own and joining them with lipo works with only the Command
    # Line Tools too.
    echo "Building Glazer ${version} (${build}), ${configuration}, universal…"
    binaries=()
    for architecture in arm64 x86_64; do
        swift build --configuration "$configuration" --arch "$architecture" --product Glazer
        binaries+=("$(swift build --configuration "$configuration" --arch "$architecture" --show-bin-path)/Glazer")
    done
    lipo -create -output "$app/Contents/MacOS/Glazer" "${binaries[@]}"
else
    echo "Building Glazer ${version} (${build}), ${configuration}…"
    swift build --configuration "$configuration" --product Glazer
    cp "$(swift build --configuration "$configuration" --show-bin-path)/Glazer" "$app/Contents/MacOS/Glazer"
fi

cp Resources/Glazer.icns "$app/Contents/Resources/Glazer.icns"
sed -e "s/\$(VERSION)/${version}/" -e "s/\$(BUILD)/${build}/" \
    Resources/Info.plist > "$app/Contents/Info.plist"
plutil -lint -s "$app/Contents/Info.plist"

# A signing identity comes from the environment (CI), or from Scripts/signing.sh install.
if [[ -z "${GLAZER_SIGNING_IDENTITY:-}" && -f "$HOME/.config/glazer/signing.env" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.config/glazer/signing.env"
fi

if [[ -n "${GLAZER_SIGNING_IDENTITY:-}" ]]; then
    keychain_options=()
    if [[ -n "${GLAZER_SIGNING_KEYCHAIN:-}" ]]; then
        security unlock-keychain -p "${GLAZER_SIGNING_KEYCHAIN_PASSWORD:-}" "$GLAZER_SIGNING_KEYCHAIN"
        keychain_options=(--keychain "$GLAZER_SIGNING_KEYCHAIN")
    fi
    echo "Signing with identity ${GLAZER_SIGNING_IDENTITY}"
    codesign --force ${keychain_options[@]+"${keychain_options[@]}"} --sign "$GLAZER_SIGNING_IDENTITY" \
        --options runtime --entitlements Resources/Glazer.entitlements "$app"
else
    echo "Signing ad hoc (no signing identity; see Scripts/signing.sh)"
    codesign --force --sign - --options runtime --entitlements Resources/Glazer.entitlements "$app"
fi
codesign --verify --strict "$app"

echo "Built $app ($(lipo -archs "$app/Contents/MacOS/Glazer"))"

if $open_when_done; then
    pkill -x Glazer 2>/dev/null || true
    open "$app"
fi
