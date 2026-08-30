#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cornerlight-release-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM

fail() {
    print -u2 -- "release workflow test failed: $*"
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -F -- "$expected" "$file" >/dev/null || fail "missing '$expected' in $file"
}

BOOTSTRAP_REPOSITORY="$TEST_ROOT/bootstrap-repository"
mkdir -p "$BOOTSTRAP_REPOSITORY/Sources" "$BOOTSTRAP_REPOSITORY/Resources"
git -C "$BOOTSTRAP_REPOSITORY" init -q
git -C "$BOOTSTRAP_REPOSITORY" config user.name "Cornerlight Tests"
git -C "$BOOTSTRAP_REPOSITORY" config user.email "cornerlight-tests@example.invalid"
cp "$PROJECT_ROOT/Resources/Info.plist" "$BOOTSTRAP_REPOSITORY/Resources/Info.plist"
print -r -- "initial" > "$BOOTSTRAP_REPOSITORY/Sources/main.swift"
git -C "$BOOTSTRAP_REPOSITORY" add .
git -C "$BOOTSTRAP_REPOSITORY" commit -q -m "Initial release"

CORNERLIGHT_PROJECT_ROOT="$BOOTSTRAP_REPOSITORY" \
    "$PROJECT_ROOT/scripts/validate-release.sh" v0.1.0 --revision HEAD \
    > "$TEST_ROOT/bootstrap-validation.log"
CORNERLIGHT_PROJECT_ROOT="$BOOTSTRAP_REPOSITORY" \
    "$PROJECT_ROOT/scripts/extract-release-notes.sh" v0.1.0 \
    > "$TEST_ROOT/bootstrap-notes.md"
assert_contains "$TEST_ROOT/bootstrap-notes.md" "Initial public release."

print -r -- "changed" > "$BOOTSTRAP_REPOSITORY/Sources/main.swift"
git -C "$BOOTSTRAP_REPOSITORY" add Sources/main.swift
CORNERLIGHT_PROJECT_ROOT="$BOOTSTRAP_REPOSITORY" \
    "$PROJECT_ROOT/scripts/check-changelog.sh" --staged \
    > "$TEST_ROOT/bootstrap-gate.log"
assert_contains "$TEST_ROOT/bootstrap-gate.log" "initial release snapshot"

git -C "$BOOTSTRAP_REPOSITORY" tag -a v0.1.0 -m "Cornerlight 0.1.0"
CORNERLIGHT_PROJECT_ROOT="$BOOTSTRAP_REPOSITORY" \
    "$PROJECT_ROOT/scripts/check-changelog.sh" --staged \
    > "$TEST_ROOT/post-bootstrap-gate.log" 2>&1 \
    && fail "product change without a changelog passed after v0.1.0"
assert_contains "$TEST_ROOT/post-bootstrap-gate.log" "CHANGELOG.md must accompany"

plutil -replace CFBundleShortVersionString -string 0.2.0 \
    "$BOOTSTRAP_REPOSITORY/Resources/Info.plist"
CORNERLIGHT_PROJECT_ROOT="$BOOTSTRAP_REPOSITORY" \
    "$PROJECT_ROOT/scripts/validate-release.sh" v0.2.0 \
    > "$TEST_ROOT/post-bootstrap-validation.log" 2>&1 \
    && fail "later release without a changelog unexpectedly passed"
assert_contains "$TEST_ROOT/post-bootstrap-validation.log" "CHANGELOG.md is required"

REPOSITORY="$TEST_ROOT/repository"
mkdir -p "$REPOSITORY/Sources" "$REPOSITORY/Resources"
git -C "$REPOSITORY" init -q
git -C "$REPOSITORY" config user.name "Cornerlight Tests"
git -C "$REPOSITORY" config user.email "cornerlight-tests@example.invalid"
cp "$PROJECT_ROOT/Resources/Info.plist" "$REPOSITORY/Resources/Info.plist"
print -r -- "initial" > "$REPOSITORY/Sources/main.swift"
cat > "$REPOSITORY/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [0.1.0] - 2026-08-29

### Added

- First private release.
EOF
git -C "$REPOSITORY" add .
git -C "$REPOSITORY" commit -q -m "Initial release"

CORNERLIGHT_PROJECT_ROOT="$REPOSITORY" "$PROJECT_ROOT/scripts/validate-release.sh" v0.1.0 \
    > "$TEST_ROOT/valid.log"
CORNERLIGHT_PROJECT_ROOT="$REPOSITORY" "$PROJECT_ROOT/scripts/validate-release.sh" v0.1.0 \
    --revision HEAD > "$TEST_ROOT/revision.log"
CORNERLIGHT_PROJECT_ROOT="$REPOSITORY" "$PROJECT_ROOT/scripts/extract-release-notes.sh" v0.1.0 \
    > "$TEST_ROOT/notes.md"
assert_contains "$TEST_ROOT/notes.md" "First private release."

print -r -- "changed" > "$REPOSITORY/Sources/main.swift"
git -C "$REPOSITORY" add Sources/main.swift
CORNERLIGHT_PROJECT_ROOT="$REPOSITORY" "$PROJECT_ROOT/scripts/check-changelog.sh" --staged \
    > "$TEST_ROOT/missing-changelog.log" 2>&1 \
    && fail "product change without a changelog unexpectedly passed"
assert_contains "$TEST_ROOT/missing-changelog.log" "CHANGELOG.md must accompany"

print -r -- "- A staged product change." >> "$REPOSITORY/CHANGELOG.md"
git -C "$REPOSITORY" add CHANGELOG.md
CORNERLIGHT_PROJECT_ROOT="$REPOSITORY" "$PROJECT_ROOT/scripts/check-changelog.sh" --staged \
    > "$TEST_ROOT/staged-changelog.log"

git -C "$REPOSITORY" reset -q --hard HEAD
awk '/^## \[Unreleased\]/ { print; print "\n- Not released yet."; next } { print }' \
    "$REPOSITORY/CHANGELOG.md" > "$TEST_ROOT/changelog-with-unreleased.md"
cp "$TEST_ROOT/changelog-with-unreleased.md" "$REPOSITORY/CHANGELOG.md"
CORNERLIGHT_PROJECT_ROOT="$REPOSITORY" "$PROJECT_ROOT/scripts/validate-release.sh" v0.1.0 \
    > "$TEST_ROOT/unreleased.log" 2>&1 \
    && fail "nonempty Unreleased section unexpectedly passed"
assert_contains "$TEST_ROOT/unreleased.log" "still contains changes"
CORNERLIGHT_PROJECT_ROOT="$REPOSITORY" "$PROJECT_ROOT/scripts/validate-release.sh" v0.1.0 \
    --revision HEAD > "$TEST_ROOT/immutable-revision.log"

git -C "$REPOSITORY" reset -q --hard HEAD
plutil -replace CFBundleShortVersionString -string 0.2.0 "$REPOSITORY/Resources/Info.plist"
CORNERLIGHT_PROJECT_ROOT="$REPOSITORY" "$PROJECT_ROOT/scripts/validate-release.sh" v0.1.0 \
    > "$TEST_ROOT/version-mismatch.log" 2>&1 \
    && fail "mismatched bundle version unexpectedly passed"
assert_contains "$TEST_ROOT/version-mismatch.log" "does not match tag version"

git -C "$REPOSITORY" reset -q --hard HEAD
sed 's/2026-08-29/2026-02-31/' "$REPOSITORY/CHANGELOG.md" > "$TEST_ROOT/invalid-date.md"
cp "$TEST_ROOT/invalid-date.md" "$REPOSITORY/CHANGELOG.md"
CORNERLIGHT_PROJECT_ROOT="$REPOSITORY" "$PROJECT_ROOT/scripts/validate-release.sh" v0.1.0 \
    > "$TEST_ROOT/invalid-date.log" 2>&1 \
    && fail "invalid calendar date unexpectedly passed"
assert_contains "$TEST_ROOT/invalid-date.log" "invalid release date"

RELEASE_WORKFLOW="$PROJECT_ROOT/.github/workflows/release.yml"
assert_contains "$RELEASE_WORKFLOW" 'tags:'
assert_contains "$RELEASE_WORKFLOW" 'workflow_dispatch:'
assert_contains "$RELEASE_WORKFLOW" 'needs: verify'
assert_contains "$RELEASE_WORKFLOW" 'permissions:'
assert_contains "$RELEASE_WORKFLOW" 'contents: read'
assert_contains "$RELEASE_WORKFLOW" 'contents: write'
assert_contains "$RELEASE_WORKFLOW" './scripts/validate-release.sh'
assert_contains "$RELEASE_WORKFLOW" './build.sh --distribution'
assert_contains "$RELEASE_WORKFLOW" 'Developer ID Application:'
assert_contains "$RELEASE_WORKFLOW" 'CORNERLIGHT_SIGN_IDENTITY=$SIGN_IDENTITY'
assert_contains "$RELEASE_WORKFLOW" 'SPARKLE_PRIVATE_KEY'
assert_contains "$RELEASE_WORKFLOW" './scripts/generate-appcast.sh'
assert_contains "$RELEASE_WORKFLOW" 'release/appcast.xml'
assert_contains "$RELEASE_WORKFLOW" 'xcrun notarytool submit'
assert_contains "$RELEASE_WORKFLOW" 'gh release create'
assert_contains "$RELEASE_WORKFLOW" "if: github.ref_type == 'tag'"
assert_contains "$RELEASE_WORKFLOW" 'if: always()'
[[ "$(grep -c 'brew install' "$RELEASE_WORKFLOW")" == 1 ]] \
    || fail "signing workflow must isolate Homebrew tools to the verification runner"
assert_contains "$PROJECT_ROOT/hooks/pre-push" 'scripts/validate-release.sh'

print -- "Release workflow tests passed"
