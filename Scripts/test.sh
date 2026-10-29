#!/usr/bin/env bash
# Runs Glazer's tests.
#
# Usage: Scripts/test.sh [options] [-- swift-test-arguments]
#   --coverage              Measure code coverage and report it for each source file.
#   --min-coverage PERCENT  Fail unless GlazerCore's line coverage is at least PERCENT.
#                           Implies --coverage.
#   --warnings-as-errors    Fail on any compiler warning.
#   -h, --help              Show this help.
#
# With only the Command Line Tools installed (no Xcode), Swift Testing lives outside the
# compiler's default search paths, so this script adds them. On GitHub Actions the coverage
# report is also written to the job summary.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

coverage=false
minimum_coverage=""
build_flags=()
passthrough=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --coverage) coverage=true; shift ;;
        --min-coverage)
            [[ "${2:-}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || usage_error "--min-coverage needs a percentage, such as 95."
            minimum_coverage=$2
            coverage=true
            shift 2
            ;;
        --warnings-as-errors) build_flags+=(-Xswiftc -warnings-as-errors); shift ;;
        -h | --help) usage; exit 0 ;;
        --) shift; passthrough+=("$@"); break ;;
        *) usage_error "Unknown option: $1" ;;
    esac
done

require_macos
require swift xcrun

developer_dir="$(xcode-select --print-path)"
if [[ "$developer_dir" == */CommandLineTools ]]; then
    frameworks="$developer_dir/Library/Developer/Frameworks"
    libraries="$developer_dir/Library/Developer/usr/lib"
    build_flags+=(
        -Xswiftc -F -Xswiftc "$frameworks"
        -Xlinker -F -Xlinker "$frameworks"
        -Xlinker -rpath -Xlinker "$frameworks"
        -Xlinker -rpath -Xlinker "$libraries"
    )
fi
if $coverage; then
    build_flags+=(--enable-code-coverage)
fi

step "Running tests"
swift test ${build_flags[@]+"${build_flags[@]}"} ${passthrough[@]+"${passthrough[@]}"}

$coverage || exit 0

# --- Coverage ----------------------------------------------------------------------------

bin_path="$(swift build --show-bin-path)"
binary="$bin_path/GlazerPackageTests.xctest/Contents/MacOS/GlazerPackageTests"
profile="$bin_path/codecov/default.profdata"
[[ -f "$binary" && -f "$profile" ]] || die "No coverage data found in $bin_path." "$EX_NOINPUT"

report="$(xcrun llvm-cov report "$binary" -instr-profile="$profile" \
    -ignore-filename-regex='(Tests|\.build)/|Sources/(GlazerApp|GlazerCameraCheck)/')"
core_coverage="$(xcrun llvm-cov report "$binary" -instr-profile="$profile" \
    -ignore-filename-regex='(Tests|\.build)/|Sources/(GlazerApp|GlazerCameraCheck|GlazerSystem)/' |
    awk '/^TOTAL/ { sub(/%/, "", $10); print $10 }')"

step "Coverage"
printf '%s\n' "$report" | awk '/^(Glazer|TOTAL)/ { printf "  %-52s %8s\n", $1, $10 }' >&2
info "  GlazerCore line coverage: ${core_coverage}%"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "### Test coverage"
        echo
        echo "GlazerCore line coverage: **${core_coverage}%**${minimum_coverage:+ (minimum ${minimum_coverage}%)}"
        echo
        echo "| File | Lines |"
        echo "|---|---:|"
        printf '%s\n' "$report" | awk '/^Glazer/ { printf "| `%s` | %s |\n", $1, $10 }'
    } >>"$GITHUB_STEP_SUMMARY"
fi

if [[ -n "$minimum_coverage" ]]; then
    if awk -v actual="$core_coverage" -v minimum="$minimum_coverage" 'BEGIN { exit !(actual + 0 >= minimum + 0) }'; then
        success "GlazerCore coverage ${core_coverage}% meets the ${minimum_coverage}% minimum."
    else
        die "GlazerCore coverage ${core_coverage}% is below the ${minimum_coverage}% minimum." "$EX_DATAERR"
    fi
fi
