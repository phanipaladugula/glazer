#!/usr/bin/env bash
# Prints the release notes for a version: install instructions, then the version's section
# of CHANGELOG.md.
#
# Usage: Scripts/release-notes.sh v0.1.0
set -euo pipefail

cd "$(dirname "$0")/.."

tag="${1:?Usage: Scripts/release-notes.sh vX.Y.Z}"
version="${tag#v}"

# The lines between "## [X.Y.Z]" and the next "## [" heading or the link definitions.
changes="$(awk -v version="$version" '
    index($0, "## [" version "]") == 1 { found = 1; next }
    found && (/^## \[/ || /^\[[^]]+\]: /) { exit }
    found { print }
' CHANGELOG.md)"

if [[ -z "${changes//[[:space:]]/}" ]]; then
    echo "CHANGELOG.md has no section for ${version}. Add \"## [${version}]\" before tagging." >&2
    exit 65
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
