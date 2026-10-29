#!/usr/bin/env bash
# Tests install.sh the way people run it, against a locally built package.
#
# Usage: Tests/Install/run.sh [PACKAGE_DIR]
#   PACKAGE_DIR  A folder with Glazer.zip and Glazer.zip.sha256. Default: dist, as made by
#                Scripts/bundle.sh and Scripts/package.sh.
#   -h, --help   Show this help.
#
# Everything installs into scratch folders; nothing touches /Applications. Tests that would
# change this Mac's real settings (uninstall, running under sudo) only run on CI.

source "$(dirname "${BASH_SOURCE[0]}")/../../Scripts/lib/common.sh"

case "${1:-}" in
    -h | --help) usage; exit 0 ;;
esac
package=${1:-dist}
package="$(cd "$package" 2>/dev/null && pwd)" || die "No package folder at ${1:-dist}." "$EX_NOINPUT"
[[ -f "$package/Glazer.zip" && -f "$package/Glazer.zip.sha256" ]] ||
    die "$package needs Glazer.zip and Glazer.zip.sha256. Run Scripts/bundle.sh and Scripts/package.sh." "$EX_NOINPUT"

require_macos
require python3 ditto shasum codesign plutil

readonly installer="$GLAZER_ROOT/install.sh"
readonly pty_run="$GLAZER_ROOT/Tests/Install/pty_run.py"
make_workspace

passed=0
failed=0
check() {
    local name=$1
    shift
    if "$@"; then
        printf '%sPASS%s %s\n' "$_green$_bold" "$_reset" "$name" >&2
        passed=$((passed + 1))
    else
        printf '%sFAIL%s %s\n' "$_red$_bold" "$_reset" "$name" >&2
        failed=$((failed + 1))
    fi
}

# Runs the installer with output captured, from a release at $1, into the folder $2.
install_from() {
    local release=$1 destination=$2
    shift 2
    GLAZER_RELEASE_URL="file://$release" GLAZER_INSTALL_DIR="$destination" NO_COLOR=1 \
        /bin/bash "$installer" --no-open "$@" >"$workspace/out.txt" 2>&1
}
output_contains() { grep -qF -- "$1" "$workspace/out.txt"; }
# Succeeds when the command fails. Runs in this shell, so it can call the helpers above.
fails() { ! "$@"; }
not_installed() { [[ ! -e "$1/Glazer.app" ]]; }

# --- Options -----------------------------------------------------------------------------

check "--help prints usage and succeeds" bash -c '"$0" --help | grep -q "Usage: install.sh"' "$installer"
check "an unknown option exits 64" bash -c '"$0" --frobnicate >/dev/null 2>&1; [[ $? -eq 64 ]]' "$installer"
check "--version needs a value" bash -c '! "$0" --version >/dev/null 2>&1' "$installer"

# --- Installing --------------------------------------------------------------------------

expected_version="$(ditto -x -k "$package/Glazer.zip" "$workspace/expected" && plutil -extract CFBundleShortVersionString raw "$workspace/expected/Glazer.app/Contents/Info.plist")"

fresh="$workspace/fresh"
check "a fresh install succeeds" install_from "$package" "$fresh"
check "the app is installed with the release's version" \
    bash -c '[[ "$(plutil -extract CFBundleShortVersionString raw "$0/Glazer.app/Contents/Info.plist")" == "$1" ]]' "$fresh" "$expected_version"
check "the installed app's signature verifies" codesign --verify --strict "$fresh/Glazer.app"
check "the installed app carries no quarantine flag" bash -c '! xattr "$0/Glazer.app" | grep -q quarantine' "$fresh"
check "installing again updates in place" install_from "$package" "$fresh"
check "the success message names the version" output_contains "Glazer $expected_version is installed"

# --- Refusals ----------------------------------------------------------------------------

forged="$workspace/forged"
mkdir -p "$forged"
cp "$package/Glazer.zip" "$forged/"
printf 'x' >"$forged/decoy"
(cd "$forged" && shasum -a 256 decoy >Glazer.zip.sha256)
check "a checksum naming another file is rejected" fails install_from "$forged" "$workspace/forged-out"
check "...and nothing is installed" not_installed "$workspace/forged-out"

corrupt="$workspace/corrupt"
mkdir -p "$corrupt"
cp "$package/Glazer.zip" "$package/Glazer.zip.sha256" "$corrupt/"
printf 'tampered' >>"$corrupt/Glazer.zip"
check "a corrupted download is rejected" fails install_from "$corrupt" "$workspace/corrupt-out"
check "...with the checksum error" output_contains "doesn't match its checksum"
check "...and nothing is installed" not_installed "$workspace/corrupt-out"

impostor="$workspace/impostor"
mkdir -p "$impostor"
ditto -x -k "$package/Glazer.zip" "$impostor"
plutil -replace CFBundleIdentifier -string com.example.impostor "$impostor/Glazer.app/Contents/Info.plist"
codesign --force --sign - "$impostor/Glazer.app" 2>/dev/null
(cd "$impostor" && ditto -c -k --keepParent Glazer.app Glazer.zip && shasum -a 256 Glazer.zip >Glazer.zip.sha256)
check "an app signed as another bundle is rejected" fails install_from "$impostor" "$workspace/impostor-out"
check "...with the signature error" output_contains "isn't signed as Glazer"
check "...and nothing is installed" not_installed "$workspace/impostor-out"

check "a missing release fails clearly" fails install_from "$workspace/no-such-release" "$workspace/missing-out"
check "...saying it couldn't download" output_contains "Couldn't"

# --- The animated terminal ---------------------------------------------------------------

# terminal_test COLUMNS ROWS EXPECT LABEL [pty_run options]: installs into tty-LABEL.
terminal_test() {
    local columns=$1 rows=$2 expect=$3 label=$4
    shift 4
    local result
    result="$(GLAZER_RELEASE_URL="file://$package" GLAZER_INSTALL_DIR="$workspace/tty-$label" \
        python3 "$pty_run" "$columns" "$rows" "$@" -- /bin/bash "$installer" --no-open)"
    python3 -c '
import json, sys
result, expect = json.loads(sys.argv[1]), sys.argv[2]
ok = result["utf8"] and result["cursor_hidden"] == result["cursor_shown"]
if expect == "animated":
    ok = ok and result["exit"] == 0 and result["frames"] > 10 and result["widest"] <= result["columns"] - 2
elif expect == "plain":
    ok = ok and result["exit"] == 0 and result["frames"] == 0
elif expect == "cancelled":
    ok = ok and result["exit"] == 130 and result["cancelled_message"]
if not ok:
    print("  " + json.dumps(result), file=sys.stderr)
sys.exit(0 if ok else 1)
' "$result" "$expect"
}

check "a 100-column terminal shows the robot, every frame fits, the cursor comes back" terminal_test 100 30 animated wide
check "...and installs the app" bash -c '[[ -d "$0/Glazer.app" ]]' "$workspace/tty-wide"
check "a 64-column terminal shows the robot and every frame fits" terminal_test 64 24 animated narrow
check "a 50-column terminal falls back to plain output" terminal_test 50 20 plain tiny
check "Ctrl-C cancels, restores the cursor and installs nothing" terminal_test 100 30 cancelled cancelled --interrupt-after 0.8
check "...and leaves no app behind" not_installed "$workspace/tty-cancelled"

# --- CI only: things that would change this Mac's real settings -----------------------------

if [[ -n "${CI:-}" ]]; then
    check "running under sudo is refused with exit 77" bash -c 'sudo -n /bin/bash "$0" --no-open >/dev/null 2>&1; [[ $? -eq 77 ]]' "$installer"
    uninstall_dir="$workspace/uninstall"
    install_from "$package" "$uninstall_dir"
    check "uninstall removes the app" bash -c \
        'GLAZER_INSTALL_DIR="$0" NO_COLOR=1 /bin/bash "$1" --uninstall >/dev/null 2>&1 && [[ ! -e "$0/Glazer.app" ]]' \
        "$uninstall_dir" "$installer"
else
    note "Skipping the sudo and uninstall tests: they only run on CI."
fi

info ""
if ((failed > 0)); then
    die "$failed installer test(s) failed, $passed passed." "$EX_SOFTWARE"
fi
success "All $passed installer tests passed."
