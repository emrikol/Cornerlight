#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cornerlight-visual-tools.XXXXXX")"
cleanup() {
    [[ "$TEST_ROOT" == */cornerlight-visual-tools.* ]] && rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT INT TERM

iconutil -c iconset "$ROOT/Resources/AppIcon.icns" -o "$TEST_ROOT/AppIcon.iconset"
for icon in \
    icon_16x16.png icon_16x16@2x.png \
    icon_32x32.png icon_32x32@2x.png \
    icon_128x128.png icon_128x128@2x.png \
    icon_256x256.png icon_256x256@2x.png \
    icon_512x512.png icon_512x512@2x.png; do
    [[ -s "$TEST_ROOT/AppIcon.iconset/$icon" ]] || {
        print -u2 -- "app icon is missing required representation: $icon"
        exit 1
    }
done

magick -size 16x16 xc:black "$TEST_ROOT/reference.png"
magick -size 16x16 xc:black "$TEST_ROOT/equal.png"
magick -size 16x16 xc:white "$TEST_ROOT/different.png"

"$ROOT/Tools/compare-golden.sh" \
    "$TEST_ROOT/reference.png" "$TEST_ROOT/equal.png" "$TEST_ROOT/equal.diff.png" >/dev/null
if "$ROOT/Tools/compare-golden.sh" \
    "$TEST_ROOT/reference.png" "$TEST_ROOT/different.png" "$TEST_ROOT/different.diff.png" \
    >/dev/null 2>&1; then
    print -u2 -- "compare-golden accepted a pixel mismatch"
    exit 1
fi

print -- "visual tool tests passed"
