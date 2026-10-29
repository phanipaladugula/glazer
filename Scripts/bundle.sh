#!/usr/bin/env bash
# Builds Glazer and packages it as dist/Glazer.app.
#
# Usage: Scripts/bundle.sh [--debug] [--universal] [--open]
#   --debug      Build the debug configuration instead of release.
#   --universal  Build for both Apple silicon and Intel, as releases are.
#   --open       Launch the app when done, quitting a running copy first.
#   -h, --help   Show this help.
#
# The app is signed with the hardened runtime and Resources/Glazer.entitlements. With a
# signing identity (see Scripts/signing.sh), every build has the same identity, so macOS
# keeps its permissions and Keychain access across builds. Without one it's signed ad hoc,
# and macOS treats each build as a new app.
#
# Environment:
#   GLAZER_SIGNING_IDENTITY, GLAZER_SIGNING_KEYCHAIN, GLAZER_SIGNING_KEYCHAIN_PASSWORD
#       The identity to sign with. Read from ~/.config/glazer/signing.env when not set.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

configuration=release
universal=false
open_when_done=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) configuration=debug; shift ;;
        --universal) universal=true; shift ;;
        --open) open_when_done=true; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage_error "Unknown option: $1" ;;
    esac
done

require_macos
require swift codesign lipo plutil git

readonly bundle_id="io.github.phanipaladugula.glazer"
readonly app="dist/Glazer.app"

for required in Resources/Info.plist Resources/Glazer.entitlements Resources/Glazer.icns; do
    [[ -f "$required" ]] || die "Missing $required." "$EX_NOINPUT"
done

# The version comes from the latest tag and the build number from the commit count, so
# neither is edited by hand.
version="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
version="${version:-0.0.0}"
build="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "The latest tag gives version '$version'; expected X.Y.Z." "$EX_DATAERR"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

if $universal; then
    # Building several architectures in one `swift build` needs Xcode's build system.
    # Building each on its own and joining them with lipo also works with only the
    # Command Line Tools.
    step "Building Glazer $version ($build), $configuration, universal"
    binaries=()
    for architecture in arm64 x86_64; do
        swift build --configuration "$configuration" --arch "$architecture" --product Glazer
        binaries+=("$(swift build --configuration "$configuration" --arch "$architecture" --show-bin-path)/Glazer")
    done
    lipo -create -output "$app/Contents/MacOS/Glazer" "${binaries[@]}"
else
    step "Building Glazer $version ($build), $configuration"
    swift build --configuration "$configuration" --product Glazer
    cp "$(swift build --configuration "$configuration" --show-bin-path)/Glazer" "$app/Contents/MacOS/Glazer"
fi

cp Resources/Glazer.icns "$app/Contents/Resources/Glazer.icns"
sed -e "s/\$(VERSION)/${version}/" -e "s/\$(BUILD)/${build}/" Resources/Info.plist >"$app/Contents/Info.plist"
plutil -lint -s "$app/Contents/Info.plist" || die "The generated Info.plist is invalid." "$EX_SOFTWARE"

# --- Signing -----------------------------------------------------------------------------

if [[ -z "${GLAZER_SIGNING_IDENTITY:-}" && -f "$HOME/.config/glazer/signing.env" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.config/glazer/signing.env"
fi

signing_options=(--force --options runtime --entitlements Resources/Glazer.entitlements)
if [[ -n "${GLAZER_SIGNING_IDENTITY:-}" ]]; then
    if [[ -n "${GLAZER_SIGNING_KEYCHAIN:-}" ]]; then
        security unlock-keychain -p "${GLAZER_SIGNING_KEYCHAIN_PASSWORD:-}" "$GLAZER_SIGNING_KEYCHAIN"
        signing_options+=(--keychain "$GLAZER_SIGNING_KEYCHAIN")
    fi
    step "Signing with identity $GLAZER_SIGNING_IDENTITY"
    codesign "${signing_options[@]}" --sign "$GLAZER_SIGNING_IDENTITY" "$app"
else
    note "Signing ad hoc. Each build will look like a new app to macOS; see Scripts/signing.sh."
    codesign "${signing_options[@]}" --sign - "$app"
fi

# --- Checks ------------------------------------------------------------------------------

step "Checking the bundle"
codesign --verify --strict "$app" || die "The signature doesn't verify." "$EX_SOFTWARE"
codesign --verify -R="identifier \"$bundle_id\"" "$app" 2>/dev/null ||
    die "The app isn't signed as $bundle_id." "$EX_SOFTWARE"
codesign -d --entitlements - "$app" 2>/dev/null | grep -q com.apple.security.device.camera ||
    die "The camera entitlement is missing; the hardened runtime would block the camera." "$EX_SOFTWARE"
[[ "$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")" == "$version" ]] ||
    die "The bundle's version doesn't match $version." "$EX_SOFTWARE"
[[ "$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")" == "$bundle_id" ]] ||
    die "The bundle identifier isn't $bundle_id." "$EX_SOFTWARE"
architectures="$(lipo -archs "$app/Contents/MacOS/Glazer")"
if $universal && [[ "$architectures" != *arm64* || "$architectures" != *x86_64* ]]; then
    die "A universal build has only $architectures." "$EX_SOFTWARE"
fi

success "Built $app $version ($build) for $architectures"

if $open_when_done; then
    pkill -x Glazer 2>/dev/null || true
    open "$app"
fi
