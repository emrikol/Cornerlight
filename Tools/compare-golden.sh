#!/bin/zsh
set -euo pipefail

if (( $# < 2 || $# > 3 )); then
    print -u2 -- "Usage: $0 REFERENCE.png ACTUAL.png [DIFF.png]"
    exit 2
fi

REFERENCE="$1"
ACTUAL="$2"
DIFF="${3:-${ACTUAL:r}.diff.png}"
MAX_RMSE="${CORNERLIGHT_GOLDEN_MAX_NORMALIZED_RMSE:-0}"
MAGICK="${CORNERLIGHT_MAGICK:-$(command -v magick)}"

[[ -f "$REFERENCE" ]] || { print -u2 -- "Missing reference: $REFERENCE"; exit 2; }
[[ -f "$ACTUAL" ]] || { print -u2 -- "Missing actual image: $ACTUAL"; exit 2; }
[[ -n "$MAGICK" ]] || { print -u2 -- "ImageMagick 'magick' is required"; exit 2; }

REFERENCE_SIZE="$($MAGICK identify -format '%wx%h' "$REFERENCE")"
ACTUAL_SIZE="$($MAGICK identify -format '%wx%h' "$ACTUAL")"
if [[ "$REFERENCE_SIZE" != "$ACTUAL_SIZE" ]]; then
    print -u2 -- "Golden geometry mismatch: reference=$REFERENCE_SIZE actual=$ACTUAL_SIZE"
    exit 1
fi

mkdir -p "${DIFF:h}"
$MAGICK compare \
    -compose src \
    -highlight-color '#ff2d55' \
    -lowlight-color '#00000000' \
    "$REFERENCE" "$ACTUAL" "$DIFF" 2>/dev/null || true

METRIC="$($MAGICK compare -metric RMSE "$REFERENCE" "$ACTUAL" null: 2>&1 || true)"
NORMALIZED="$(print -r -- "$METRIC" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
[[ -n "$NORMALIZED" ]] || { print -u2 -- "Could not parse ImageMagick RMSE: $METRIC"; exit 2; }

print -- "size=$REFERENCE_SIZE"
print -- "rmse=$METRIC"
print -- "normalized_rmse=$NORMALIZED"
print -- "diff=$DIFF"

awk -v actual="$NORMALIZED" -v maximum="$MAX_RMSE" \
    'BEGIN { exit !(actual <= maximum) }' || {
        print -u2 -- "Golden pixel mismatch: normalized RMSE $NORMALIZED exceeds $MAX_RMSE"
        exit 1
    }

