#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${CORNERLIGHT_PROJECT_ROOT:-${0:A:h:h}}"
TAG="${1:-}"
REVISION=""

usage() {
    print -u2 -- "Usage: $0 vX.Y.Z [--revision <git-revision>]"
    exit 2
}

[[ "$TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]] || usage
shift
if (( $# > 0 )); then
    [[ "$1" == "--revision" && $# == 2 ]] || usage
    REVISION="$2"
fi

cd "$PROJECT_ROOT"

read_at_revision() {
    local file_path="$1"
    if [[ -n "$REVISION" ]]; then
        git show "$REVISION:$file_path"
    else
        command cat "$file_path"
    fi
}

if [[ -n "$REVISION" ]]; then
    git cat-file -e "$REVISION^{commit}" 2>/dev/null || {
        print -u2 -- "Release revision does not resolve to a commit: $REVISION"
        exit 1
    }
fi

VERSION="${TAG#v}"
PLIST_COPY="$(mktemp "${TMPDIR:-/tmp}/cornerlight-release-plist.XXXXXX")"
CHANGELOG_COPY="$(mktemp "${TMPDIR:-/tmp}/cornerlight-release-changelog.XXXXXX")"
trap 'rm -f -- "$PLIST_COPY" "$CHANGELOG_COPY"' EXIT INT TERM

read_at_revision Resources/Info.plist > "$PLIST_COPY"

PLIST_VERSION="$(plutil -extract CFBundleShortVersionString raw "$PLIST_COPY")"
[[ "$PLIST_VERSION" == "$VERSION" ]] || {
    print -u2 -- "Info.plist version $PLIST_VERSION does not match tag version $VERSION"
    exit 1
}

BUILD_NUMBER="$(plutil -extract CFBundleVersion raw "$PLIST_COPY")"
[[ "$BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]] || {
    print -u2 -- "CFBundleVersion must be a positive integer, found: $BUILD_NUMBER"
    exit 1
}

if ! read_at_revision CHANGELOG.md > "$CHANGELOG_COPY" 2>/dev/null; then
    [[ "$TAG" == "v0.1.0" ]] || {
        print -u2 -- "CHANGELOG.md is required after the initial v0.1.0 release"
        exit 1
    }
    print -- "Release metadata validated for $TAG (build $BUILD_NUMBER; initial release)"
    exit 0
fi

REGEX_VERSION="${VERSION//./\\.}"
HEADER_PATTERN="^## \[$REGEX_VERSION\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$"
HEADER_COUNT="$(grep -Ec -- "$HEADER_PATTERN" "$CHANGELOG_COPY" || true)"
[[ "$HEADER_COUNT" == 1 ]] || {
    print -u2 -- "CHANGELOG.md must contain: ## [$VERSION] - YYYY-MM-DD"
    exit 1
}
RELEASE_DATE="$(grep -E -- "$HEADER_PATTERN" "$CHANGELOG_COPY" | sed -E 's/^.* - //')"
PARSED_DATE="$(/bin/date -j -f '%Y-%m-%d' "$RELEASE_DATE" '+%Y-%m-%d' 2>/dev/null)" || {
    print -u2 -- "CHANGELOG.md has an invalid release date: $RELEASE_DATE"
    exit 1
}
[[ "$PARSED_DATE" == "$RELEASE_DATE" ]] || {
    print -u2 -- "CHANGELOG.md has an invalid release date: $RELEASE_DATE"
    exit 1
}
[[ "$RELEASE_DATE" > "$(/bin/date '+%Y-%m-%d')" ]] && {
    print -u2 -- "CHANGELOG.md release date is in the future: $RELEASE_DATE"
    exit 1
}

SECTION="$(awk -v version="$VERSION" '
    index($0, "## [" version "] - ") == 1 { active = 1; next }
    active && $0 ~ "^## \\[" { exit }
    active { print }
' "$CHANGELOG_COPY")"
print -r -- "$SECTION" | grep -E -- '^- ' >/dev/null || {
    print -u2 -- "CHANGELOG.md release $VERSION has no release-note bullets"
    exit 1
}

UNRELEASED="$(awk '
    /^## \[Unreleased\]/ { active = 1; next }
    active && /^## \[/ { exit }
    active { print }
' "$CHANGELOG_COPY")"
if print -r -- "$UNRELEASED" | grep -E -- '^- ' >/dev/null; then
    print -u2 -- "CHANGELOG.md [Unreleased] still contains changes; move them into $VERSION before tagging"
    exit 1
fi

print -- "Release metadata validated for $TAG (build $BUILD_NUMBER)"
