#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cornerlight-appcast-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM

fail() {
    print -u2 -- "appcast workflow test failed: $*"
    exit 1
}

print -r -- "archive" > "$TEST_ROOT/Cornerlight.zip"
print -r -- "Release notes" > "$TEST_ROOT/release-notes.md"
print -r -- "<rss><channel><item>old</item></channel></rss>" > "$TEST_ROOT/existing.xml"

cat > "$TEST_ROOT/generate_appcast" <<'EOF'
#!/bin/zsh
set -euo pipefail
key="$(cat)"
[[ "$key" == "test-private-key" ]]
print -r -- "$*" > "$CORNERLIGHT_TEST_APPCAST_ARGUMENTS"
work_root="${@[-1]}"
[[ -f "$work_root/Cornerlight.zip" ]]
[[ -f "$work_root/Cornerlight.md" ]]
grep -Fq '<item>old</item>' "$work_root/appcast.xml"
print -r -- '<rss><channel><item>signed</item></channel></rss>' > "$work_root/appcast.xml"
EOF
chmod +x "$TEST_ROOT/generate_appcast"

SPARKLE_PRIVATE_KEY="test-private-key" \
CORNERLIGHT_GENERATE_APPCAST="$TEST_ROOT/generate_appcast" \
CORNERLIGHT_TEST_APPCAST_ARGUMENTS="$TEST_ROOT/arguments" \
    "$PROJECT_ROOT/scripts/generate-appcast.sh" \
    "$TEST_ROOT/Cornerlight.zip" \
    "$TEST_ROOT/release-notes.md" \
    "$TEST_ROOT/output/appcast.xml" \
    "https://github.com/emrikol/Cornerlight/releases/download/v0.1.0/" \
    "$TEST_ROOT/existing.xml"

grep -Fq '<item>signed</item>' "$TEST_ROOT/output/appcast.xml" \
    || fail "signed appcast was not promoted"
grep -Fq -- '--ed-key-file -' "$TEST_ROOT/arguments" \
    || fail "private key was not supplied through standard input"
grep -Fq -- '--maximum-deltas 0' "$TEST_ROOT/arguments" \
    || fail "delta generation was not disabled"
grep -Fq 'releases/download/v0.1.0/' "$TEST_ROOT/arguments" \
    || fail "release download prefix was not forwarded"

[[ "$(plutil -extract SUFeedURL raw "$PROJECT_ROOT/Resources/Info.plist")" == \
    "https://emrikol.github.io/Cornerlight/appcast.xml" ]] \
    || fail "bundle feed URL is incorrect"
[[ "$(plutil -extract SUPublicEDKey raw "$PROJECT_ROOT/Resources/Info.plist")" == \
    "j+l1c/yrbicRS/m4HSkKiQUo1BMHYffdHXIPbyr57Wo=" ]] \
    || fail "bundle update key is incorrect"

print -- "Appcast workflow tests passed"
