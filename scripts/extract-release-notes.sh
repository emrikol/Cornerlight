#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${CORNERLIGHT_PROJECT_ROOT:-${0:A:h:h}}"
TAG="${1:-}"
[[ "$TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]] || {
    print -u2 -- "Usage: $0 vX.Y.Z"
    exit 2
}

VERSION="${TAG#v}"
awk -v version="$VERSION" '
    index($0, "## [" version "] - ") == 1 { active = 1; next }
    active && $0 ~ "^## \\[" { exit }
    active { print }
' "$PROJECT_ROOT/CHANGELOG.md"
