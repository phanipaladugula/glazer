#!/usr/bin/env bash
# Runs the test suite.
#
# With only the Command Line Tools installed (no Xcode), Swift Testing lives outside the
# compiler's default search paths, so this script adds them. With Xcode it is the same
# as `swift test`.
set -euo pipefail

cd "$(dirname "$0")/.."

flags=()
developer_dir="$(xcode-select --print-path)"
if [[ "$developer_dir" == */CommandLineTools ]]; then
    frameworks="$developer_dir/Library/Developer/Frameworks"
    libraries="$developer_dir/Library/Developer/usr/lib"
    flags+=(
        -Xswiftc -F -Xswiftc "$frameworks"
        -Xlinker -F -Xlinker "$frameworks"
        -Xlinker -rpath -Xlinker "$frameworks"
        -Xlinker -rpath -Xlinker "$libraries"
    )
fi

swift test ${flags[@]+"${flags[@]}"} "$@"
