#!/usr/bin/env bash
# Installs Glazer from its GitHub releases.
#
#   curl -fsSL https://raw.githubusercontent.com/phanipaladugula/glazer/main/install.sh | bash
#
# Options (after `bash -s --` when piping):
#   --version X.Y.Z   Install a specific release instead of the latest.
#   --no-open         Don't open Glazer after installing.
#   --uninstall       Remove Glazer and its settings.
#
# Environment:
#   GLAZER_INSTALL_DIR   Install here instead of /Applications.
#   GLAZER_RELEASE_URL   Download from here instead of GitHub releases (for mirrors and testing).
#
# What it does: downloads Glazer.zip and its SHA-256 checksum from the release, checks
# that they match, installs Glazer.app into /Applications (or ~/Applications if that
# isn't writable), and opens it. Nothing else is downloaded and nothing runs as root.
set -euo pipefail

readonly repository="phanipaladugula/glazer"
readonly bundle_id="io.github.phanipaladugula.glazer"
readonly minimum_macos=15
workspace=""

usage() {
    cat <<'USAGE'
Installs Glazer, the macOS app that moves focus to the display you look at.

Usage: install.sh [--version X.Y.Z] [--no-open] [--uninstall]
  --version X.Y.Z   Install a specific release instead of the latest.
  --no-open         Don't open Glazer after installing.
  --uninstall       Remove Glazer and its settings.
USAGE
}

version=latest
action=install
open_when_done=true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) version="${2:?--version needs a value, such as 0.1.0}"; shift 2 ;;
        --no-open) open_when_done=false; shift ;;
        --uninstall) action=uninstall; shift ;;
        -h | --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
    esac
done

bold=$'\033[1m'; dim=$'\033[2m'; red=$'\033[31m'; green=$'\033[32m'; reset=$'\033[0m'
if [[ ! -t 1 ]]; then bold=""; dim=""; red=""; green=""; reset=""; fi

step() { printf '%s==>%s %s\n' "$bold" "$reset" "$1"; }
fail() { printf '%sError:%s %s\n' "$red" "$reset" "$1" >&2; exit 1; }

installed_app() {
    for directory in ${GLAZER_INSTALL_DIR:+"$GLAZER_INSTALL_DIR"} /Applications "$HOME/Applications"; do
        if [[ -d "$directory/Glazer.app" ]]; then
            echo "$directory/Glazer.app"
            return
        fi
    done
}

quit_glazer() {
    osascript -e 'tell application id "'"$bundle_id"'" to quit' >/dev/null 2>&1 || true
    pkill -x Glazer 2>/dev/null || true
}

uninstall() {
    local app
    app="$(installed_app)"
    quit_glazer
    if [[ -n "$app" ]]; then
        step "Removing $app"
        rm -rf "$app"
    fi
    step "Removing settings"
    defaults delete "$bundle_id" >/dev/null 2>&1 || true
    tccutil reset All "$bundle_id" >/dev/null 2>&1 || true
    printf '%sGlazer is uninstalled.%s\n' "$green" "$reset"
    printf '%sIf you set up face lock, delete the "Glazer face lock" item in Keychain Access.%s\n' "$dim" "$reset"
}

install() {
    [[ "$(uname -s)" == "Darwin" ]] || fail "Glazer runs on macOS only."
    local macos_major
    macos_major="$(sw_vers -productVersion | cut -d. -f1)"
    ((macos_major >= minimum_macos)) || fail "Glazer needs macOS ${minimum_macos} or later. This Mac has $(sw_vers -productVersion)."

    local base
    if [[ -n "${GLAZER_RELEASE_URL:-}" ]]; then
        base="$GLAZER_RELEASE_URL"
    elif [[ "$version" == latest ]]; then
        base="https://github.com/${repository}/releases/latest/download"
    else
        base="https://github.com/${repository}/releases/download/v${version#v}"
    fi

    workspace="$(mktemp -d)"
    trap 'rm -rf "$workspace"' EXIT

    step "Downloading Glazer ($version)"
    curl -fSL --progress-bar "$base/Glazer.zip" -o "$workspace/Glazer.zip" ||
        fail "Couldn't download Glazer. Check your connection$([[ "$version" == latest ]] || echo ", and that release $version exists")."
    curl -fsSL "$base/Glazer.zip.sha256" -o "$workspace/Glazer.zip.sha256" ||
        fail "Couldn't download the checksum for this release."

    step "Verifying checksum"
    (cd "$workspace" && shasum -a 256 -c -s Glazer.zip.sha256) ||
        fail "The download doesn't match its checksum. Nothing was installed."

    ditto -x -k "$workspace/Glazer.zip" "$workspace"
    codesign --verify --strict "$workspace/Glazer.app" 2>/dev/null ||
        fail "The app's code signature is invalid. Nothing was installed."

    local destination="${GLAZER_INSTALL_DIR:-/Applications}"
    mkdir -p "$destination" 2>/dev/null || true
    if [[ ! -w "$destination" ]]; then
        destination="$HOME/Applications"
        mkdir -p "$destination"
    fi

    quit_glazer
    step "Installing to $destination"
    rm -rf "$destination/Glazer.app"
    ditto "$workspace/Glazer.app" "$destination/Glazer.app"
    # curl doesn't quarantine downloads, but clear the flag in case the zip carried one.
    xattr -dr com.apple.quarantine "$destination/Glazer.app" 2>/dev/null || true

    local installed_version
    installed_version="$(defaults read "$destination/Glazer.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")"

    if $open_when_done; then
        step "Opening Glazer"
        open "$destination/Glazer.app"
    fi

    printf '\n%sGlazer %s is installed.%s\n' "$green" "$installed_version" "$reset"
    if $open_when_done; then
        printf 'Look for the eye in your menu bar. Setup will walk you through the rest.\n'
    else
        printf 'Open it from %s. Setup will walk you through the rest.\n' "$destination"
    fi
    printf '%sUninstall any time: curl -fsSL https://raw.githubusercontent.com/%s/main/install.sh | bash -s -- --uninstall%s\n' \
        "$dim" "$repository" "$reset"
}

"$action"
