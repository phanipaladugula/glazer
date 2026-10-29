# shellcheck shell=bash
#
# Shared by Glazer's developer scripts. Source it first thing:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# It turns on strict mode, reports the failing line and command when a script stops on an
# error, moves to the repository root, and provides logging, usage and dependency helpers.
#
# Exit codes follow sysexits(3), so callers such as CI can tell failures apart:
#   64 usage error     65 bad data      66 missing input   69 tool unavailable
#   70 internal error  73 can't create  77 not permitted

set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true # Not in macOS's bash 3.2; harmless there.

# Used by the scripts that source this file.
# shellcheck disable=SC2034
readonly EX_USAGE=64 EX_DATAERR=65 EX_NOINPUT=66 EX_UNAVAILABLE=69 EX_SOFTWARE=70 EX_CANTCREAT=73 EX_NOPERM=77

GLAZER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly GLAZER_ROOT
cd "$GLAZER_ROOT"

# The script that sourced this file.
script_path="${BASH_SOURCE[1]:-$0}"
script_name="$(basename "$script_path")"
readonly script_path script_name

# --- Output ------------------------------------------------------------------------------

# shellcheck disable=SC2034 # Some colours are only used by the sourcing scripts.
if [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    readonly _bold=$'\033[1m' _dim=$'\033[2m' _red=$'\033[31m' _yellow=$'\033[33m' _green=$'\033[32m' _blue=$'\033[34m' _reset=$'\033[0m'
else
    readonly _bold="" _dim="" _red="" _yellow="" _green="" _blue="" _reset=""
fi

# Progress and results go to stderr, so a script's stdout stays clean for its real output.
step() { printf '%s==>%s %s%s%s\n' "$_blue$_bold" "$_reset" "$_bold" "$*" "$_reset" >&2; }
info() { printf '%s\n' "$*" >&2; }
note() { printf '%s%s%s\n' "$_dim" "$*" "$_reset" >&2; }
success() { printf '%s%s%s\n' "$_green$_bold" "$*" "$_reset" >&2; }
warn() {
    printf '%sWarning:%s %s\n' "$_yellow$_bold" "$_reset" "$*" >&2
    # Surface warnings on the GitHub Actions summary, too.
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then printf '::warning title=%s::%s\n' "$script_name" "$*"; fi
}

# Prints an error and exits. die MESSAGE [EXIT_CODE]
die() {
    printf '%sError:%s %s\n' "$_red$_bold" "$_reset" "$1" >&2
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then printf '::error title=%s::%s\n' "$script_name" "$1"; fi
    exit "${2:-1}"
}

# --- Errors ------------------------------------------------------------------------------

# Reports where a script stopped when a command fails, instead of exiting silently.
_on_error() {
    local status=$? line=${BASH_LINENO[0]} command=${BASH_COMMAND}
    printf '%sError:%s %s stopped at line %s (exit %s): %s\n' \
        "$_red$_bold" "$_reset" "$script_name" "$line" "$status" "$command" >&2
    exit "$status"
}
trap _on_error ERR

# --- Usage -------------------------------------------------------------------------------

# Prints the comment block at the top of the script, after the shebang, as its help text.
usage() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$script_path" >&2
}

# Exits with a usage error. usage_error MESSAGE
usage_error() {
    printf '%sError:%s %s\n\n' "$_red$_bold" "$_reset" "$1" >&2
    usage
    exit "$EX_USAGE"
}

# --- Requirements -----------------------------------------------------------------------

# Exits unless every named command is available, saying how to get the missing ones.
require() {
    local missing=() command
    for command in "$@"; do
        command -v "$command" >/dev/null 2>&1 || missing+=("$command")
    done
    ((${#missing[@]} == 0)) && return
    local hint="Install the Command Line Tools: xcode-select --install"
    case " ${missing[*]} " in
        *" shellcheck "* | *" actionlint "*) hint="Install with Homebrew: brew install ${missing[*]}" ;;
        *" node "*) hint="Install Node.js 22 or later" ;;
    esac
    die "Missing ${missing[*]}. $hint" "$EX_UNAVAILABLE"
}

# Exits unless running on macOS.
require_macos() {
    [[ "$(uname -s)" == Darwin ]] || die "$script_name runs on macOS only." "$EX_UNAVAILABLE"
}

# Creates a scratch directory in $workspace, removed when the script exits however it
# exits. Call it directly, not in $(...), or the cleanup would run straight away.
workspace=""
make_workspace() {
    workspace=$(mktemp -d "${TMPDIR:-/tmp}/glazer.XXXXXX")
    trap 'rm -rf "$workspace"' EXIT
}
