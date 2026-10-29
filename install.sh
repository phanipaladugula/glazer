#!/usr/bin/env bash
#
# Installs Glazer, the macOS menu bar app that moves your pointer and keyboard focus to
# the display you look at.
#
#   curl -fsSL https://raw.githubusercontent.com/phanipaladugula/glazer/main/install.sh | bash
#
# It downloads Glazer.zip and its SHA-256 checksum from the latest GitHub release, checks
# both the checksum and the code signature, installs Glazer.app into /Applications (or
# ~/Applications when that isn't writable) and opens it. It never uses sudo and installs
# nothing else.
#
# Options (after `bash -s --` when piping):
#   --version X.Y.Z   Install a specific release instead of the latest.
#   --no-open         Don't open Glazer after installing.
#   --uninstall       Remove Glazer, its settings and its permissions.
#
# Environment:
#   GLAZER_INSTALL_DIR   Install here instead of /Applications.
#   GLAZER_RELEASE_URL   Download from here instead of GitHub (for mirrors and testing).
#   GLAZER_EXPECTED_SIGNER
#                        The certificate fingerprint to require instead of Glazer's (for
#                        testing); empty requires only the bundle ID.
#   NO_COLOR             Plain output, without colour or animation.
#
# Works with the bash that ships with macOS (3.2).

set -euo pipefail

readonly repository="phanipaladugula/glazer"
readonly bundle_id="io.github.phanipaladugula.glazer"
readonly minimum_macos=15

# Releases are signed with Glazer's own certificate. Its SHA-1 fingerprint is pinned here,
# so a download that was tampered with is rejected even if its checksum was replaced too.
# Tests set GLAZER_EXPECTED_SIGNER to install a build signed another way; empty checks only
# the bundle ID. (Whoever can set it could run anything anyway.)
readonly expected_signer="${GLAZER_EXPECTED_SIGNER-9A1C93ABCF0EBCD6D460CAA07AF82A9E960719E9}"

# Some networks can't reach every GitHub download server, or reach one that then stalls
# without sending anything. So every request has a short connect timeout, a time limit,
# and gives up when data stops arriving; `fetch` then tries again as a new curl process,
# which can pick another server (curl's own --retry keeps the one it has). A missing
# release (404) isn't retried.
readonly curl_options=(
    --fail --location --silent --show-error
    --proto "=https,file" --proto-redir "=https"
    --tlsv1.2 --connect-timeout 5 --speed-limit 1024 --speed-time 15
)
readonly fetch_attempts=4

# ---------------------------------------------------------------------------
# Options

usage() {
    cat <<'USAGE'
Installs Glazer, the macOS app that moves focus to the display you look at.

Usage: install.sh [--version X.Y.Z] [--no-open] [--uninstall]
  --version X.Y.Z   Install a specific release instead of the latest.
  --no-open         Don't open Glazer after installing.
  --uninstall       Remove Glazer, its settings and its permissions.
USAGE
}

version=latest
action=install
open_when_done=true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) version="${2:?--version needs a value, such as 0.1.1}"; version="${version#v}"; shift 2 ;;
        --no-open) open_when_done=false; shift ;;
        --uninstall) action=uninstall; shift ;;
        -h | --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
    esac
done

# ---------------------------------------------------------------------------
# Output

fancy=false
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
    fancy=true
fi

if $fancy; then
    bold=$'\033[1m' dim=$'\033[2m' red=$'\033[31m' green=$'\033[32m' blue=$'\033[34m' reset=$'\033[0m'
else
    bold="" dim="" red="" green="" blue="" reset=""
fi

step() { printf '%s==>%s %s%s%s\n' "$blue$bold" "$reset" "$bold" "$1" "$reset"; }
note() { printf '%s%s%s\n' "$dim" "$1" "$reset"; }
fail() {
    finish_animation
    printf '%sError:%s %s\n' "$red$bold" "$reset" "$1" >&2
    exit 1
}

# "1.9 MB", "640 KB"
human_size() {
    local bytes=$1
    if ((bytes >= 1048576)); then
        local tenths=$(((bytes * 10 + 524288) / 1048576))
        printf '%d.%d MB' $((tenths / 10)) $((tenths % 10))
    else
        printf '%d KB' $(((bytes + 1023) / 1024))
    fi
}

# ---------------------------------------------------------------------------
# The robot
#
# A small pixel-art robot walks along the top of the progress bar as Glazer downloads
# and installs, and jumps when it's done. It wears Glazer's colours: an indigo body and
# a lit cyan screen for a face. Each frame is 12 × 8 pixels, drawn two pixels per
# character with the half-block characters ▀ and ▄ in 256 colours, so it's 4 rows tall
# and looks the same in Terminal and iTerm on dark and light backgrounds.
# "." is transparent.

# shellcheck disable=SC2034 # Read by name in render_frame.
robot_walk_a=(
    "............"
    ".hhbbbbbbbb."
    ".hCcccccccb."
    "bbcecccceCbB"
    "bbcecccceCbB"
    ".bccccccccB."
    ".bbbbbbbbBB."
    ".b.B....b.B."
)
# shellcheck disable=SC2034 # Read by name in render_frame.
robot_walk_b=(
    "............"
    ".hhbbbbbbbb."
    ".hCcccccccb."
    "bbcecccceCbB"
    "bbcecccceCbB"
    ".bccccccccB."
    ".bbbbbbbbBB."
    "..b.B..b.B.."
)
# shellcheck disable=SC2034 # Read by name in render_frame.
robot_blink=(
    "............"
    ".hhbbbbbbbb."
    ".hCcccccccb."
    "bbccccccccbB"
    "bbceecceecbB"
    ".bccccccccB."
    ".bbbbbbbbBB."
    "..b.B..b.B.."
)
# shellcheck disable=SC2034 # Read by name in render_frame.
robot_jump=(
    "y..........y"
    ".hCcccccccb."
    "bbcecccceCbB"
    "bbcecccceCbB"
    ".bccccccccB."
    ".bbbbbbbbBB."
    "..b.B..b.B.."
    "............"
)

# Pixel letters and their xterm-256 colours.
readonly palette_keys="bBhcCey"
readonly palette_colours=(62 61 105 87 159 17 228)

# The track lights up in this cyan to blue gradient, left to right.
readonly bar_colours=(27 33 39 45 51 87)

readonly robot_width=12
readonly robot_rows=4 # 8 pixels, two per character row
readonly scene_rows=$((robot_rows + 2))

animate=false
terminal_width=80
bar_width=0
robot_x=0      # The robot's position along the bar, in thousandths.
target=0       # Where it's walking to, in thousandths.
tick=0
scene_drawn=false
status_text=""

# Turns frame `$1` (the name of a pixel array) into terminal rows in `rendered_<name>`.
render_frame() {
    local name=$1 y x top bottom top_colour bottom_colour prefix line
    local -a pixels
    eval "pixels=(\"\${robot_${name}[@]}\")"
    for ((y = 0; y < robot_rows; y++)); do
        line=""
        for ((x = 0; x < robot_width; x++)); do
            top=${pixels[y * 2]:x:1}
            bottom=${pixels[y * 2 + 1]:x:1}
            if [[ $top == . && $bottom == . ]]; then
                line+=" "
                continue
            fi
            if [[ $top != . ]]; then prefix=${palette_keys%%"$top"*}; top_colour=${palette_colours[${#prefix}]}; fi
            if [[ $bottom != . ]]; then prefix=${palette_keys%%"$bottom"*}; bottom_colour=${palette_colours[${#prefix}]}; fi
            if [[ $bottom == . ]]; then
                line+=$'\033[38;5;'"${top_colour}m▀"
            elif [[ $top == . ]]; then
                line+=$'\033[38;5;'"${bottom_colour}m▄"
            elif [[ $top_colour == "$bottom_colour" ]]; then
                line+=$'\033[38;5;'"${top_colour}m█"
            else
                line+=$'\033[38;5;'"${top_colour};48;5;${bottom_colour}m▀"$'\033[49m'
            fi
        done
        eval "rendered_${name}[y]=\"\${line}\"\$'\\033[0m'"
    done
}

start_animation() {
    $fancy || return 0
    [[ -z "${CI:-}" ]] || return 0
    # Ask the terminal itself: when piped from curl, $COLUMNS isn't set and tput can't see it.
    local size rows=0 columns=0
    size=$(stty size </dev/tty 2>/dev/null || true)
    if [[ "$size" =~ ^([0-9]+)\ ([0-9]+)$ ]]; then
        rows=${BASH_REMATCH[1]}
        columns=${BASH_REMATCH[2]}
    fi
    ((columns >= 60 && rows >= scene_rows + 4)) || return 0

    terminal_width=$columns
    bar_width=$((columns - 16))
    ((bar_width > 60)) && bar_width=60
    local frame
    for frame in walk_a walk_b blink jump; do
        render_frame "$frame"
    done
    animate=true
    printf '\033[?25l' # Hide the cursor while drawing.
}

finish_animation() {
    if $animate; then
        printf '\033[?25h'
        animate=false
    fi
}

# Draws the robot, the bar and the status line over the previous drawing.
#
# Every line must fit the terminal: a line that wraps pushes the next frame down a row.
# The whole frame goes out in one write, inside a synchronised update where the terminal
# supports one, so it never shows half drawn.
draw_scene() {
    local frame=$1 percent=$2 offset row filled i colour line bar="" text scene=""
    scene+=$'\033[?2026h'
    $scene_drawn && scene+=$'\033['"${scene_rows}A"
    scene_drawn=true

    offset=$((robot_x * (bar_width - robot_width) / 1000))
    printf -v line '%*s' "$offset" ""
    local indent="  $line"
    for ((row = 0; row < robot_rows; row++)); do
        eval "line=\"\${rendered_${frame}[row]}\""
        scene+=$'\r\033[2K'"$indent$line"$'\n'
    done

    # The track: lit up to the robot's feet in a cyan to blue gradient.
    filled=$((offset + robot_width / 2))
    for ((i = 0; i < bar_width; i++)); do
        if ((i < filled)); then
            colour=${bar_colours[i * ${#bar_colours[@]} / bar_width]}
            bar+=$'\033[38;5;'"${colour}m━"
        else
            bar+=$'\033[38;5;245m─'
        fi
    done
    printf -v line '%3d%%' "$percent"
    scene+=$'\r\033[2K  '"$bar"$'\033[0m '"$bold$line$reset"$'\n'

    text=$status_text
    if ((${#text} > terminal_width - 4)); then
        text="${text:0:terminal_width - 5}…"
    fi
    scene+=$'\r\033[2K  '"$dim$text$reset"$'\n'
    scene+=$'\033[?2026l'
    printf '%s' "$scene"
}

# A path for display, with the home folder as ~.
display_path() {
    local path=$1
    [[ "$path" == "$HOME"/* ]] && path="~${path#"$HOME"}"
    printf '%s' "$path"
}

# Advances the animation by one frame, walking the robot towards `target`.
animation_tick() {
    $animate || return 0
    # The robot walks at most 4% of the bar per frame, so it crosses the whole bar in
    # about two seconds even when the download itself is instant.
    local frame distance step=40
    distance=$((target - robot_x))
    if ((distance > 0)); then
        ((distance < step)) && step=$distance
        robot_x=$((robot_x + step))
        if ((tick / 2 % 2)); then frame=walk_b; else frame=walk_a; fi
    else
        # Standing still, waiting: it blinks now and then.
        if ((tick % 24 < 2)); then frame=blink; else frame=walk_a; fi
    fi
    tick=$((tick + 1))
    draw_scene "$frame" $((robot_x / 10))
    sleep 0.08
}

# Walks the robot to `target` and waits until it arrives.
walk_to() {
    target=$1
    if $animate; then
        while ((robot_x < target)); do animation_tick; done
    fi
}

celebrate() {
    $animate || return 0
    local i
    for ((i = 0; i < 6; i++)); do
        if ((i % 2)); then draw_scene walk_a 100; else draw_scene jump 100; fi
        sleep 0.14
    done
    draw_scene walk_a 100
    finish_animation
}

# Sets the line under the bar, or prints it as a step when not animating.
status() {
    status_text=$1
    $animate || step "$1"
}

# ---------------------------------------------------------------------------
# Installing

workspace=""
background_pid=""

cleanup() {
    if [[ -n "$background_pid" ]]; then
        # The job is a subshell running curl: stop both.
        pkill -P "$background_pid" 2>/dev/null || true
        kill "$background_pid" 2>/dev/null || true
    fi
    if [[ -n "$workspace" ]]; then
        rm -rf "$workspace"
    fi
    finish_animation
}
trap cleanup EXIT
trap 'cleanup; printf "\n%sCancelled. Nothing was installed.%s\n" "$dim" "$reset"; exit 130' INT TERM

installed_app() {
    local directory
    for directory in ${GLAZER_INSTALL_DIR:+"$GLAZER_INSTALL_DIR"} /Applications "$HOME/Applications"; do
        if [[ -d "$directory/Glazer.app" ]]; then
            echo "$directory/Glazer.app"
            return
        fi
    done
}

# Quits a running Glazer and waits for it to exit. Replacing the app while the old copy is
# still shutting down makes macOS refuse to open the new one (error -600).
quit_glazer() {
    pgrep -x Glazer >/dev/null 2>&1 || return 0
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    pkill -x Glazer 2>/dev/null || true
    # Up to 25 checks, 0.2 seconds apart.
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
        pgrep -x Glazer >/dev/null 2>&1 || return 0
        sleep 0.2
    done
    # Still running after five seconds: it's stuck.
    pkill -9 -x Glazer 2>/dev/null || true
    sleep 0.5
}

# The release's base URL, its version (when known) and the zip's size, from one request
# that follows GitHub's redirects without downloading anything.
# Runs curl with `curl_options` and a time limit of $1 seconds, up to `fetch_attempts`
# times, each as a new process. Before each retry it writes the attempt number to
# $workspace/attempt, so the progress line can say it's trying again.
fetch() {
    local max_time=$1 attempt code=0
    shift
    for ((attempt = 1; attempt <= fetch_attempts; attempt++)); do
        if ((attempt > 1)); then
            printf '%s' "$attempt" >"$workspace/attempt"
            sleep 1
        fi
        code=0
        curl "${curl_options[@]}" --max-time "$max_time" "$@" || code=$?
        # Done, or an HTTP error such as 404 that asking again won't change.
        ((code == 0 || code == 22)) && return "$code"
    done
    return "$code"
}

# The attempt `fetch` last said it's on, once it has retried.
retry_attempt=""

# Says when `fetch` is trying again: on the progress line, or as a note in plain output.
report_retry() {
    local attempt
    attempt=$(cat "$workspace/attempt" 2>/dev/null || true)
    [[ -n "$attempt" && "$attempt" != "$retry_attempt" ]] || return 0
    retry_attempt=$attempt
    status_text="GitHub is slow to answer. Trying again ($attempt of $fetch_attempts)…"
    $animate || note "$status_text"
}

# Waits for the background job $1, keeping the robot moving and the progress line
# current, so a slow server never looks like a frozen installer. Returns the job's status.
wait_animated() {
    background_pid=$1
    while kill -0 "$background_pid" 2>/dev/null; do
        report_retry
        if $animate; then animation_tick; else sleep 0.2; fi
    done
    local code=0
    wait "$background_pid" || code=$?
    background_pid=""
    rm -f "$workspace/attempt"
    retry_attempt=""
    return "$code"
}

resolve_release() {
    if [[ -n "${GLAZER_RELEASE_URL:-}" ]]; then
        base_url=${GLAZER_RELEASE_URL%/}
    elif [[ "$version" == latest ]]; then
        base_url="https://github.com/${repository}/releases/latest/download"
    else
        base_url="https://github.com/${repository}/releases/download/v${version}"
    fi

    local headers code
    fetch 20 --head "$base_url/Glazer.zip" >"$workspace/headers" 2>/dev/null &
    if ! wait_animated $!; then
        # Ask once more, without --fail, to learn whether the release is missing or GitHub
        # is unreachable.
        local probe_options=() option
        for option in "${curl_options[@]}"; do
            [[ "$option" == --fail ]] || probe_options+=("$option")
        done
        code=$(curl "${probe_options[@]}" --max-time 20 --head --output /dev/null \
            --write-out '%{http_code}' "$base_url/Glazer.zip" 2>/dev/null || true)
        if [[ "$code" == 404 && "$version" != latest ]]; then
            fail "There's no Glazer release $version. See https://github.com/$repository/releases"
        elif [[ "$code" == 404 ]]; then
            fail "Glazer hasn't published a release yet."
        else
            fail "Couldn't reach GitHub to download Glazer. Check your connection and try again."
        fi
    fi
    headers=$(tr -d '\r' <"$workspace/headers")

    if [[ "$version" == latest ]]; then
        local tagged
        tagged=$(printf '%s\n' "$headers" | grep -io 'releases/download/v[0-9][^/]*' | head -1 || true)
        [[ -n "$tagged" ]] && version=${tagged##*/v}
    fi
    zip_size=$(printf '%s\n' "$headers" | awk 'tolower($1) == "content-length:" { size = $2 } END { print size + 0 }')
}

download_zip() {
    fetch 20 "$base_url/Glazer.zip.sha256" -o "$workspace/Glazer.zip.sha256" 2>/dev/null &
    wait_animated $! || fail "Couldn't download the checksum for this release."

    # Each attempt starts the file again; the robot doesn't walk back.
    fetch 600 "$base_url/Glazer.zip" -o "$workspace/Glazer.zip" 2>"$workspace/curl.log" &
    background_pid=$!

    if $animate; then
        local bytes
        while kill -0 "$background_pid" 2>/dev/null; do
            report_retry
            bytes=$(stat -f %z "$workspace/Glazer.zip" 2>/dev/null || echo 0)
            # Once data arrives, show progress again, saying which attempt it is.
            if ((zip_size > 0 && bytes > 0)); then
                target=$((bytes * 850 / zip_size))
                status_text="Downloading ${label%% (*}  ·  $(human_size "$bytes") of $(human_size "$zip_size")"
                [[ -z "$retry_attempt" ]] || status_text+="  ·  attempt $retry_attempt of $fetch_attempts"
            fi
            animation_tick
        done
    fi

    if ! wait_animated "$background_pid"; then
        fail "Couldn't download Glazer: $(grep -v '^$' "$workspace/curl.log" | tail -1 | sed 's/^curl: ([0-9]*) //')"
    fi
    status_text="Downloaded ${label%% (*}"
    walk_to 850
}

# Checks the app's signature is intact, that it really is Glazer, and that Glazer's
# certificate signed it.
verify_signature() {
    local app=$1 requirement="identifier \"$bundle_id\""
    if [[ -n "$expected_signer" ]]; then
        requirement+=" and certificate leaf = H\"$expected_signer\""
    fi
    codesign --verify --strict -R="$requirement" "$app" 2>/dev/null ||
        fail "The app isn't signed as Glazer. Nothing was installed."
}

install() {
    [[ "$(uname -s)" == Darwin ]] || fail "Glazer runs on macOS only."
    local macos_major
    macos_major=$(sw_vers -productVersion | cut -d. -f1)
    ((macos_major >= minimum_macos)) ||
        fail "Glazer needs macOS $minimum_macos or later. This Mac has $(sw_vers -productVersion)."

    workspace=$(mktemp -d)
    printf '\n'
    start_animation
    status "Finding the latest release"
    $animate && animation_tick
    resolve_release

    local label="Glazer"
    [[ "$version" == latest ]] || label+=" $version"
    ((zip_size > 0)) && label+=" ($(human_size "$zip_size"))"
    status "Downloading $label"
    download_zip

    status "Verifying checksum and signature"
    # Compare the hashes directly, rather than trusting the file name inside the .sha256.
    local expected_hash actual_hash
    expected_hash=$(awk 'NR == 1 { print tolower($1) }' "$workspace/Glazer.zip.sha256")
    actual_hash=$(shasum -a 256 "$workspace/Glazer.zip" | awk '{ print tolower($1) }')
    [[ ${#expected_hash} -eq 64 && "$expected_hash" == "$actual_hash" ]] ||
        fail "The download doesn't match its checksum. Nothing was installed."

    ditto -x -k "$workspace/Glazer.zip" "$workspace"
    verify_signature "$workspace/Glazer.app"
    walk_to 920

    local destination="${GLAZER_INSTALL_DIR:-/Applications}"
    mkdir -p "$destination" 2>/dev/null || true
    if [[ ! -w "$destination" ]]; then
        destination="$HOME/Applications"
        mkdir -p "$destination"
        if [[ -d /Applications/Glazer.app ]]; then
            note "An older Glazer is in /Applications and can't be replaced without admin rights. Delete it to avoid running both."
        fi
    fi

    status "Installing to $(display_path "$destination")"
    quit_glazer
    rm -rf "$destination/Glazer.app"
    ditto "$workspace/Glazer.app" "$destination/Glazer.app"
    # curl doesn't quarantine downloads, but clear the flag in case the zip carried one.
    xattr -dr com.apple.quarantine "$destination/Glazer.app" 2>/dev/null || true
    walk_to 1000

    local installed_version
    installed_version=$(defaults read "$destination/Glazer.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")
    status_text="Glazer $installed_version is installed"
    celebrate

    printf '\n%sGlazer %s is installed%s in %s\n' "$green$bold" "$installed_version" "$reset" "$(display_path "$destination")"
    if $open_when_done; then
        # The app is installed whatever happens here, so a failed launch is a note, not
        # an error.
        if open "$destination/Glazer.app" 2>/dev/null; then
            printf 'Look for it in your menu bar. Setup will walk you through the rest.\n'
        else
            printf 'Open it from %s. Setup will walk you through the rest.\n' "$(display_path "$destination")"
        fi
    else
        printf 'Open it from %s. Setup will walk you through the rest.\n' "$(display_path "$destination")"
    fi
    note "Update: run this command again.  Uninstall: add  bash -s -- --uninstall"
}

uninstall() {
    local app
    app=$(installed_app)
    quit_glazer
    if [[ -n "$app" ]]; then
        step "Removing $app"
        rm -rf "$app"
    fi
    step "Removing settings, permissions and face lock"
    defaults delete "$bundle_id" >/dev/null 2>&1 || true
    tccutil reset All "$bundle_id" >/dev/null 2>&1 || true
    security delete-generic-password -s "$bundle_id.face-lock" >/dev/null 2>&1 || true
    printf '%sGlazer is uninstalled.%s\n' "$green$bold" "$reset"
}

# Installing as root would leave a root-owned app and change root's settings, not the
# user's.
if [[ $EUID -eq 0 ]]; then
    echo "Run this without sudo: Glazer installs for your user and never needs root." >&2
    exit 77
fi

"$action"
