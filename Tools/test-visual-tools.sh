#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cornerlight-visual-tools.XXXXXX")"
cleanup() {
    [[ "$TEST_ROOT" == */cornerlight-visual-tools.* ]] && rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT INT TERM

xcrun actool "$ROOT/Resources/AppIcon.icon" \
    --compile "$TEST_ROOT" \
    --platform macosx \
    --minimum-deployment-target 26.6 \
    --target-device mac \
    --app-icon AppIcon \
    --output-partial-info-plist "$TEST_ROOT/AppIcon-Info.plist" \
    >/dev/null
[[ -s "$TEST_ROOT/Assets.car" ]] || {
    print -u2 -- "actool did not compile the Icon Composer asset catalog"
    exit 1
}

iconutil -c iconset "$TEST_ROOT/AppIcon.icns" -o "$TEST_ROOT/AppIcon.iconset"
for icon in \
    icon_16x16.png icon_16x16@2x.png \
    icon_128x128.png icon_128x128@2x.png; do
    [[ -s "$TEST_ROOT/AppIcon.iconset/$icon" ]] || {
        print -u2 -- "app icon is missing required representation: $icon"
        exit 1
    }
done

CORNERLIGHT_ICON_PREVIEW_OUTPUT="$TEST_ROOT/AppIcon.png" \
    "$ROOT/scripts/export-app-icon-preview.sh" >/dev/null
[[ -s "$TEST_ROOT/AppIcon.png" ]] || {
    print -u2 -- "Icon Composer did not export the app icon preview"
    exit 1
}

print -- "visual tool tests passed"
