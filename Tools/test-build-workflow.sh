#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cornerlight-build-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT INT TERM

FAKE_BIN="$TEST_ROOT/bin"
FAKE_BUILD_BIN="$TEST_ROOT/swift-bin"
COMMAND_LOG="$TEST_ROOT/commands.log"
mkdir -p "$FAKE_BIN" "$FAKE_BUILD_BIN"
print -r -- '#!/bin/zsh' > "$FAKE_BUILD_BIN/Cornerlight"
chmod +x "$FAKE_BUILD_BIN/Cornerlight"
FAKE_SPARKLE="$FAKE_BUILD_BIN/Sparkle.framework/Versions/B"
mkdir -p \
    "$FAKE_SPARKLE/XPCServices/Downloader.xpc" \
    "$FAKE_SPARKLE/XPCServices/Installer.xpc" \
    "$FAKE_SPARKLE/Updater.app"
print -r -- '#!/bin/zsh' > "$FAKE_SPARKLE/Autoupdate"
chmod +x "$FAKE_SPARKLE/Autoupdate"
print -r -- "Sparkle test license" > "$TEST_ROOT/Sparkle-LICENSE"

cat > "$FAKE_BIN/swift" <<'EOF'
#!/bin/zsh
if [[ "$*" == *"--show-bin-path"* ]]; then
    print -r -- "$CORNERLIGHT_TEST_SWIFT_BIN"
fi
EOF

cat > "$FAKE_BIN/security" <<'EOF'
#!/bin/zsh
[[ "${CORNERLIGHT_TEST_NO_IDENTITIES:-false}" == true ]] && exit 0
if [[ "${CORNERLIGHT_TEST_ONLY_DEVELOPER_ID:-false}" == true ]]; then
    print -r -- '  1) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Developer ID Application: Derrick Tennant (3T9RX85H44)"'
    exit 0
fi
cat <<'IDENTITIES'
  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: Derrick Tennant (8VA8WSH6G4)"
  2) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Developer ID Application: Derrick Tennant (3T9RX85H44)"
     2 valid identities found
IDENTITIES
EOF

cat > "$FAKE_BIN/codesign" <<'EOF'
#!/bin/zsh
print -r -- "codesign $*" >> "$CORNERLIGHT_TEST_COMMAND_LOG"
if [[ "$*" == *" -r- "* ]]; then
    print -u2 -- 'designated => identifier "com.emrikol.Cornerlight" and anchor apple generic'
fi
EOF

cat > "$FAKE_BIN/ps" <<'EOF'
#!/bin/zsh
print -r -- "${CORNERLIGHT_TEST_PS_OUTPUT:-}"
EOF

cat > "$FAKE_BIN/open" <<'EOF'
#!/bin/zsh
print -r -- "open $*" >> "$CORNERLIGHT_TEST_COMMAND_LOG"
EOF

cat > "$FAKE_BIN/strip" <<'EOF'
#!/bin/zsh
exit 0
EOF

cat > "$FAKE_BIN/install_name_tool" <<'EOF'
#!/bin/zsh
print -r -- "install_name_tool $*" >> "$CORNERLIGHT_TEST_COMMAND_LOG"
EOF

chmod +x "$FAKE_BIN"/*

export PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
export CORNERLIGHT_TEST_SWIFT_BIN="$FAKE_BUILD_BIN"
export CORNERLIGHT_TEST_COMMAND_LOG="$COMMAND_LOG"
export CORNERLIGHT_SPARKLE_LICENSE="$TEST_ROOT/Sparkle-LICENSE"
unset CORNERLIGHT_SIGN_IDENTITY

fail() {
    print -u2 -- "build workflow test failed: $*"
    exit 1
}

grep -q '<key>LSUIElement</key>' "$PROJECT_ROOT/Resources/Info.plist" \
    || fail "source bundle metadata must retain Spotlight's LSUIElement lifecycle"
! grep -q '<key>LSMultipleInstancesProhibited</key>' "$PROJECT_ROOT/Resources/Info.plist" \
    || fail "source bundle metadata must not prohibit the overlapping process used by Quit & Reopen"
[[ -s "$PROJECT_ROOT/Resources/AppIcon.icns" ]] || fail "source app icon is missing"
[[ "$(plutil -extract CFBundleIconFile raw "$PROJECT_ROOT/Resources/Info.plist")" == "AppIcon" ]] \
    || fail "source bundle metadata does not name the app icon"

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -F -- "$expected" "$file" >/dev/null || fail "missing '$expected' in $file"
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    ! grep -F -- "$unexpected" "$file" >/dev/null || fail "unexpected '$unexpected' in $file"
}

OUTPUT_ONE="$TEST_ROOT/output-one"
INSTALL_ONE="$TEST_ROOT/install-one"
CORNERLIGHT_OUTPUT_ROOT="$OUTPUT_ONE" CORNERLIGHT_INSTALL_ROOT="$INSTALL_ONE" \
    "$PROJECT_ROOT/build.sh" --debug --install > "$TEST_ROOT/install.log"

[[ -d "$OUTPUT_ONE/Cornerlight.app" ]] || fail "output bundle was not promoted"
[[ -d "$INSTALL_ONE/Cornerlight.app" ]] || fail "installed bundle was not promoted"
[[ -s "$INSTALL_ONE/Cornerlight.app/Contents/Resources/AppIcon.icns" ]] \
    || fail "installed bundle lost its app icon"
[[ -d "$INSTALL_ONE/Cornerlight.app/Contents/Frameworks/Sparkle.framework" ]] \
    || fail "installed bundle lost Sparkle.framework"
[[ -s "$INSTALL_ONE/Cornerlight.app/Contents/Resources/Licenses/Sparkle.txt" ]] \
    || fail "installed bundle lost Sparkle's license"
[[ "$(plutil -extract LSUIElement raw "$INSTALL_ONE/Cornerlight.app/Contents/Info.plist")" == true ]] \
    || fail "installed bundle lost Spotlight's LSUIElement lifecycle"
! plutil -extract LSMultipleInstancesProhibited raw "$INSTALL_ONE/Cornerlight.app/Contents/Info.plist" \
    >/dev/null 2>&1 \
    || fail "installed bundle unexpectedly prohibits overlapping Quit & Reopen processes"
assert_contains "$COMMAND_LOG" 'codesign --force --sign Apple Development: Derrick Tennant (8VA8WSH6G4)'
assert_contains "$COMMAND_LOG" \
    'install_name_tool -add_rpath @executable_path/../Frameworks'
assert_contains "$COMMAND_LOG" \
    'codesign --force --preserve-metadata=identifier,entitlements,requirements --sign Apple Development: Derrick Tennant (8VA8WSH6G4)'
assert_not_contains "$COMMAND_LOG" 'open '
[[ -z "$(find "$OUTPUT_ONE" "$INSTALL_ONE" -maxdepth 1 -name '.cornerlight-*' -print)" ]] || fail "staging directory leaked"

OUTPUT_TWO="$TEST_ROOT/output-two"
CORNERLIGHT_OUTPUT_ROOT="$OUTPUT_TWO" CORNERLIGHT_INSTALL_ROOT="$TEST_ROOT/install-two" \
    "$PROJECT_ROOT/build.sh" --debug --compare-requirement "$OUTPUT_ONE/Cornerlight.app" > "$TEST_ROOT/compare.log"

OUTPUT_DEVELOPER_ID="$TEST_ROOT/output-developer-id"
CORNERLIGHT_OUTPUT_ROOT="$OUTPUT_DEVELOPER_ID" CORNERLIGHT_INSTALL_ROOT="$TEST_ROOT/install-developer-id" \
    "$PROJECT_ROOT/build.sh" --debug --developer-id > "$TEST_ROOT/developer-id.log"
assert_contains "$COMMAND_LOG" 'codesign --force --sign Developer ID Application: Derrick Tennant (3T9RX85H44)'

OUTPUT_DISTRIBUTION="$TEST_ROOT/output-distribution"
CORNERLIGHT_OUTPUT_ROOT="$OUTPUT_DISTRIBUTION" CORNERLIGHT_INSTALL_ROOT="$TEST_ROOT/install-distribution" \
    "$PROJECT_ROOT/build.sh" --distribution > "$TEST_ROOT/distribution.log"
assert_contains "$COMMAND_LOG" \
    'codesign --force --options runtime --timestamp --sign Developer ID Application: Derrick Tennant (3T9RX85H44)'

CORNERLIGHT_OUTPUT_ROOT="$TEST_ROOT/invalid-distribution" \
    CORNERLIGHT_INSTALL_ROOT="$TEST_ROOT/invalid-distribution-install" \
    "$PROJECT_ROOT/build.sh" --debug --distribution > "$TEST_ROOT/invalid-distribution.log" 2>&1 \
    && fail "debug distribution build unexpectedly succeeded"
assert_contains "$TEST_ROOT/invalid-distribution.log" '--distribution requires a release build'

OUTPUT_OVERRIDE="$TEST_ROOT/output-override"
CORNERLIGHT_SIGN_IDENTITY='Developer ID Application: Derrick Tennant (3T9RX85H44)' \
    CORNERLIGHT_OUTPUT_ROOT="$OUTPUT_OVERRIDE" CORNERLIGHT_INSTALL_ROOT="$TEST_ROOT/install-override" \
    "$PROJECT_ROOT/build.sh" --debug > "$TEST_ROOT/override.log"
assert_contains "$TEST_ROOT/override.log" 'Signed with: Developer ID Application: Derrick Tennant (3T9RX85H44)'

COMPILE_ONLY_OUTPUT="$TEST_ROOT/compile-only-output"
CORNERLIGHT_OUTPUT_ROOT="$COMPILE_ONLY_OUTPUT" CORNERLIGHT_INSTALL_ROOT="$TEST_ROOT/compile-only-install" \
    "$PROJECT_ROOT/build.sh" --debug --compile-only > "$TEST_ROOT/compile-only.log"
[[ ! -e "$COMPILE_ONLY_OUTPUT/Cornerlight.app" ]] || fail "compile-only created an app bundle"

FOREGROUND_OUTPUT="$TEST_ROOT/foreground-output"
FOREGROUND_INSTALL="$TEST_ROOT/foreground-install"
CORNERLIGHT_OUTPUT_ROOT="$FOREGROUND_OUTPUT" CORNERLIGHT_INSTALL_ROOT="$FOREGROUND_INSTALL" \
    "$PROJECT_ROOT/build.sh" --debug --run > "$TEST_ROOT/foreground.log"
assert_contains "$COMMAND_LOG" "open $FOREGROUND_OUTPUT/Cornerlight.app --args --show"

BACKGROUND_OUTPUT="$TEST_ROOT/background-output"
BACKGROUND_INSTALL="$TEST_ROOT/background-install"
CORNERLIGHT_OUTPUT_ROOT="$BACKGROUND_OUTPUT" CORNERLIGHT_INSTALL_ROOT="$BACKGROUND_INSTALL" \
    "$PROJECT_ROOT/build.sh" --debug --run-background > "$TEST_ROOT/background.log"
assert_contains "$COMMAND_LOG" "open -g $BACKGROUND_INSTALL/Cornerlight.app --args --background"
assert_not_contains "$COMMAND_LOG" "open -g $BACKGROUND_OUTPUT/Cornerlight.app --args --background"

INSTALLED_BACKGROUND_OUTPUT="$TEST_ROOT/installed-background-output"
INSTALLED_BACKGROUND_ROOT="$TEST_ROOT/installed-background-root"
CORNERLIGHT_OUTPUT_ROOT="$INSTALLED_BACKGROUND_OUTPUT" CORNERLIGHT_INSTALL_ROOT="$INSTALLED_BACKGROUND_ROOT" \
    "$PROJECT_ROOT/build.sh" --debug --install --restart-background > "$TEST_ROOT/installed-background.log"
assert_contains "$COMMAND_LOG" "open -g $INSTALLED_BACKGROUND_ROOT/Cornerlight.app --args --background"
assert_not_contains "$COMMAND_LOG" "open -g $INSTALLED_BACKGROUND_OUTPUT/Cornerlight.app --args --background"
assert_not_contains "$COMMAND_LOG" "open -n "
CORNERLIGHT_OUTPUT_ROOT="$INSTALLED_BACKGROUND_OUTPUT" CORNERLIGHT_INSTALL_ROOT="$INSTALLED_BACKGROUND_ROOT" \
    "$PROJECT_ROOT/build.sh" --debug --restart-background > "$TEST_ROOT/installed-background-rebuild.log"
assert_contains "$COMMAND_LOG" "codesign -d -r- $INSTALLED_BACKGROUND_ROOT/Cornerlight.app"

LIVE_OUTPUT="${TEST_ROOT:A}/live-output"
mkdir -p "$LIVE_OUTPUT/Cornerlight.app/Contents/MacOS"
LIVE_EXECUTABLE="$LIVE_OUTPUT/Cornerlight.app/Contents/MacOS/Cornerlight"
print -r -- '#!/bin/zsh' > "$LIVE_EXECUTABLE"
CORNERLIGHT_TEST_PS_OUTPUT="4242 $LIVE_EXECUTABLE --background" \
    CORNERLIGHT_OUTPUT_ROOT="$LIVE_OUTPUT" CORNERLIGHT_INSTALL_ROOT="$TEST_ROOT/live-install" \
    "$PROJECT_ROOT/build.sh" --debug > "$TEST_ROOT/live.log" 2>&1 && fail "live target replacement unexpectedly succeeded"
assert_contains "$TEST_ROOT/live.log" 'refusing to replace live'
[[ -f "$LIVE_EXECUTABLE" ]] || fail "live target was modified"
[[ -z "$(find "$LIVE_OUTPUT" -maxdepth 1 -name '.cornerlight-*' -print)" ]] || fail "failed deployment leaked staging"

NO_IDENTITY_OUTPUT="$TEST_ROOT/no-identity-output"
CORNERLIGHT_TEST_NO_IDENTITIES=true CORNERLIGHT_OUTPUT_ROOT="$NO_IDENTITY_OUTPUT" \
    CORNERLIGHT_INSTALL_ROOT="$TEST_ROOT/no-identity-install" \
    "$PROJECT_ROOT/build.sh" --debug > "$TEST_ROOT/no-identity.log" 2>&1 && fail "missing stable identity unexpectedly succeeded"
assert_contains "$TEST_ROOT/no-identity.log" 'required signing identity is unavailable'

CORNERLIGHT_TEST_ONLY_DEVELOPER_ID=true CORNERLIGHT_OUTPUT_ROOT="$TEST_ROOT/no-fallback-output" \
    CORNERLIGHT_INSTALL_ROOT="$TEST_ROOT/no-fallback-install" \
    "$PROJECT_ROOT/build.sh" --debug > "$TEST_ROOT/no-fallback.log" 2>&1 \
    && fail "default signing silently fell back to Developer ID"
assert_contains "$TEST_ROOT/no-fallback.log" \
    'required signing identity is unavailable: Apple Development: Derrick Tennant (8VA8WSH6G4)'

CORNERLIGHT_TEST_NO_IDENTITIES=true CORNERLIGHT_OUTPUT_ROOT="$NO_IDENTITY_OUTPUT" \
    CORNERLIGHT_INSTALL_ROOT="$TEST_ROOT/no-identity-install" \
    "$PROJECT_ROOT/build.sh" --debug --allow-adhoc > "$TEST_ROOT/adhoc.log" 2>&1
assert_contains "$TEST_ROOT/adhoc.log" 'ad-hoc signing changes'

print -- "Build workflow tests passed"
