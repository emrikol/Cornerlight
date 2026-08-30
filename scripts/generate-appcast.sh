#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATE_APPCAST="${CORNERLIGHT_GENERATE_APPCAST:-$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast}"

if [[ $# -lt 4 || $# -gt 5 ]]; then
    printf 'Usage: %s ARCHIVE RELEASE_NOTES OUTPUT DOWNLOAD_URL_PREFIX [EXISTING_APPCAST]\n' "$0" >&2
    exit 2
fi

ARCHIVE="$1"
RELEASE_NOTES="$2"
OUTPUT="$3"
DOWNLOAD_URL_PREFIX="$4"
EXISTING_APPCAST="${5:-}"

[[ -f "$ARCHIVE" ]] || { printf 'Missing update archive: %s\n' "$ARCHIVE" >&2; exit 1; }
[[ -f "$RELEASE_NOTES" ]] || { printf 'Missing release notes: %s\n' "$RELEASE_NOTES" >&2; exit 1; }
[[ -x "$GENERATE_APPCAST" ]] || { printf 'Missing generate_appcast tool: %s\n' "$GENERATE_APPCAST" >&2; exit 1; }
[[ -n "${SPARKLE_PRIVATE_KEY:-}" ]] || { printf 'Missing SPARKLE_PRIVATE_KEY\n' >&2; exit 1; }

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cornerlight-appcast.XXXXXX")"
cleanup() {
    rm -rf -- "$WORK_ROOT"
}
trap cleanup EXIT

cp -- "$ARCHIVE" "$WORK_ROOT/Cornerlight.zip"
cp -- "$RELEASE_NOTES" "$WORK_ROOT/Cornerlight.md"
if [[ -n "$EXISTING_APPCAST" && -f "$EXISTING_APPCAST" ]]; then
    cp -- "$EXISTING_APPCAST" "$WORK_ROOT/appcast.xml"
fi

printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    --link "https://emrikol.github.io/Cornerlight/" \
    --embed-release-notes \
    --maximum-versions 3 \
    --maximum-deltas 0 \
    "$WORK_ROOT"

[[ -s "$WORK_ROOT/appcast.xml" ]] || {
    printf 'generate_appcast did not produce an appcast\n' >&2
    exit 1
}
mkdir -p -- "$(dirname "$OUTPUT")"
mv -- "$WORK_ROOT/appcast.xml" "$OUTPUT"

