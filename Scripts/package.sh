#!/usr/bin/env bash
# Packages dist/Glazer.app for release, as dist/Glazer.zip and dist/Glazer.zip.sha256.
#
# Usage: Scripts/package.sh
#   -h, --help  Show this help.
#
# Run Scripts/bundle.sh --universal first. The zip is made with ditto, which keeps the
# app's code signature and extended attributes intact, unlike zip.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help) usage; exit 0 ;;
        *) usage_error "Unknown option: $1" ;;
    esac
done

require_macos
require ditto shasum codesign

[[ -d dist/Glazer.app ]] || die "dist/Glazer.app not found. Run Scripts/bundle.sh --universal first." "$EX_NOINPUT"
codesign --verify --strict dist/Glazer.app || die "dist/Glazer.app's signature doesn't verify." "$EX_DATAERR"

cd dist
rm -f Glazer.zip Glazer.zip.sha256
step "Packaging Glazer.zip"
ditto -c -k --sequesterRsrc --keepParent Glazer.app Glazer.zip
shasum -a 256 Glazer.zip >Glazer.zip.sha256

# Check the package unpacks to an app that still verifies.
make_workspace
ditto -x -k Glazer.zip "$workspace"
codesign --verify --strict "$workspace/Glazer.app" || die "The packaged app's signature doesn't verify." "$EX_SOFTWARE"

success "Packaged dist/Glazer.zip ($(du -h Glazer.zip | cut -f1))"
cat Glazer.zip.sha256
