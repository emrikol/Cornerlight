#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
ICON_DOCUMENT="$PROJECT_ROOT/Resources/AppIcon.icon"
OUTPUT_FILE="${CORNERLIGHT_ICON_PREVIEW_OUTPUT:-$PROJECT_ROOT/Resources/AppIcon.png}"
STANDALONE_ICTOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"
XCODE_ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

if [[ -x "$STANDALONE_ICTOOL" ]]; then
    ICTOOL="$STANDALONE_ICTOOL"
elif [[ -x "$XCODE_ICTOOL" ]]; then
    ICTOOL="$XCODE_ICTOOL"
else
    print -u2 -- "Icon Composer's ictool is required to export the icon preview."
    exit 1
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cornerlight-icon-preview.XXXXXX")"
cleanup() {
    [[ "$TEMP_ROOT" == */cornerlight-icon-preview.* ]] && rm -rf -- "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "${OUTPUT_FILE:h}"
"$ICTOOL" "$ICON_DOCUMENT" \
    --export-image \
    --output-file "$TEMP_ROOT/AppIcon.png" \
    --platform macOS \
    --rendition Default \
    --width 1024 \
    --height 1024 \
    --scale 1 \
    >/dev/null
if command -v magick >/dev/null 2>&1; then
    magick "$TEMP_ROOT/AppIcon.png" -depth 8 -strip \
        -define png:compression-level=9 "$TEMP_ROOT/AppIcon-Preview.png"
    mv "$TEMP_ROOT/AppIcon-Preview.png" "$OUTPUT_FILE"
else
    mv "$TEMP_ROOT/AppIcon.png" "$OUTPUT_FILE"
fi
print -- "Exported $OUTPUT_FILE from $ICON_DOCUMENT"
