#!/usr/bin/env bash
# Packages dist/Glazer.app for release: dist/Glazer.zip and its SHA-256 checksum.
#
# Usage: Scripts/package.sh
#
# Run Scripts/bundle.sh --universal first. The zip is made with ditto, which keeps the
# app's code signature and extended attributes intact, unlike zip.
set -euo pipefail

cd "$(dirname "$0")/../dist"

if [[ ! -d Glazer.app ]]; then
    echo "dist/Glazer.app not found. Run Scripts/bundle.sh --universal first." >&2
    exit 66
fi

rm -f Glazer.zip Glazer.zip.sha256
ditto -c -k --sequesterRsrc --keepParent Glazer.app Glazer.zip
shasum -a 256 Glazer.zip > Glazer.zip.sha256

echo "Packaged dist/Glazer.zip ($(du -h Glazer.zip | cut -f1))"
cat Glazer.zip.sha256
