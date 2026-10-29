#!/usr/bin/env bash
# Formats every Swift file with swift-format, or checks the formatting.
#
# Usage: Scripts/format.sh [--check]
#   --check     Change nothing; fail if any file isn't formatted. CI runs this.
#   -h, --help  Show this help.
#
# The rules are in .swift-format.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

check=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) check=true; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage_error "Unknown option: $1" ;;
    esac
done

require swift
swift format --version >/dev/null 2>&1 || die "This Swift toolchain has no swift-format (Swift 6 or later needed)." "$EX_UNAVAILABLE"

paths=(Package.swift Sources Tests)

if $check; then
    step "Checking Swift formatting"
    swift format lint --strict --recursive --parallel "${paths[@]}" ||
        die "Some files aren't formatted. Run Scripts/format.sh to fix them." "$EX_DATAERR"
    success "Swift formatting is clean."
else
    step "Formatting Swift files"
    swift format format --in-place --recursive --parallel "${paths[@]}"
fi
