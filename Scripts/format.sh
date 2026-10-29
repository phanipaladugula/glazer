#!/usr/bin/env bash
# Formats every Swift file, or checks formatting with --check (used by CI).
set -euo pipefail

cd "$(dirname "$0")/.."

paths=(Package.swift Sources Tests)

if [[ "${1:-}" == "--check" ]]; then
    swift format lint --strict --recursive --parallel "${paths[@]}"
else
    swift format format --in-place --recursive --parallel "${paths[@]}"
fi
