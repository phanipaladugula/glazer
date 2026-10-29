#!/usr/bin/env bash
# Prints the release notes for a version: install instructions, then the version's section
# of CHANGELOG.md.
#
# Usage: Scripts/release-notes.sh vX.Y.Z
#   -h, --help  Show this help.
#
# Fails if CHANGELOG.md has no section for the version.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

case "${1:-}" in
    -h | --help) usage; exit 0 ;;
    v[0-9]*.[0-9]*.[0-9]*) tag=$1 ;;
    "") usage_error "Give the version tag, such as v0.1.0." ;;
    *) usage_error "Not a version tag: $1" ;;
esac
version="${tag#v}"

# The lines between "## [X.Y.Z]" and the next "## [" heading or the link definitions.
changes="$(awk -v version="$version" '
    index($0, "## [" version "]") == 1 { found = 1; next }
    found && (/^## \[/ || /^\[[^]]+\]: /) { exit }
    found { print }
' CHANGELOG.md)"

if [[ -z "${changes//[[:space:]]/}" ]]; then
    die "CHANGELOG.md has no section for ${version}. Add \"## [${version}]\" before tagging." "$EX_DATAERR"
fi

cat <<EOF
## Install

\`\`\`sh
curl -fsSL https://raw.githubusercontent.com/phanipaladugula/glazer/main/install.sh | bash
\`\`\`

Or download \`Glazer.zip\` below, unzip it and move Glazer to Applications. Glazer needs
macOS 15 or later and runs on Apple silicon and Intel Macs.

> [!NOTE]
> This build is signed ad hoc, not with an Apple Developer ID. The install command above
> works without warnings. If you download the zip in a browser instead, right-click
> Glazer and choose **Open** the first time.

## What's new
${changes}
EOF
