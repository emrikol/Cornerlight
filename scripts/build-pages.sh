#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="${CORNERLIGHT_PAGES_OUTPUT:-$PROJECT_ROOT/_site}"
REPOSITORY="${GITHUB_REPOSITORY:-emrikol/Cornerlight}"
RELEASE_FIXTURE="${CORNERLIGHT_RELEASE_FIXTURE:-}"
APPCAST_FIXTURE="${CORNERLIGHT_APPCAST_FIXTURE:-}"
RELEASE_INPUT="$(mktemp "${TMPDIR:-/tmp}/cornerlight-release.XXXXXX")"
APPCAST_URL_INPUT="$(mktemp "${TMPDIR:-/tmp}/cornerlight-appcast-url.XXXXXX")"

cleanup() {
    rm -f -- "$RELEASE_INPUT" "$APPCAST_URL_INPUT"
}
trap cleanup EXIT

if [[ -z "$OUTPUT_ROOT" || "$OUTPUT_ROOT" == "/" || "$OUTPUT_ROOT" == "$PROJECT_ROOT" ]]; then
    printf 'Refusing unsafe Pages output path: %s\n' "$OUTPUT_ROOT" >&2
    exit 1
fi

rm -rf -- "$OUTPUT_ROOT"
mkdir -p -- "$OUTPUT_ROOT"
cp -R "$PROJECT_ROOT/docs/." "$OUTPUT_ROOT/"

if [[ -n "$RELEASE_FIXTURE" ]]; then
    cp -- "$RELEASE_FIXTURE" "$RELEASE_INPUT"
elif [[ -n "${GH_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
    if ! gh api "repos/$REPOSITORY/releases/latest" > "$RELEASE_INPUT" 2>/dev/null; then
        printf '%s\n' "No published Cornerlight release; keeping the releases-page fallback"
        exit 0
    fi
else
    printf '%s\n' "No release credentials or fixture; keeping the releases-page fallback"
    exit 0
fi

python3 - "$RELEASE_INPUT" "$OUTPUT_ROOT/release.json" "$APPCAST_URL_INPUT" <<'PY'
import json
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
appcast_destination = pathlib.Path(sys.argv[3])
release = json.loads(source.read_text(encoding="utf-8"))
assets = release.get("assets", [])
dmg = next((asset for asset in assets if asset.get("name") == "Cornerlight.dmg"), None)
appcast = next((asset for asset in assets if asset.get("name") == "appcast.xml"), None)
if dmg is None:
    raise SystemExit("Latest release does not contain Cornerlight.dmg")
if appcast is None:
    raise SystemExit("Latest release does not contain appcast.xml")

metadata = {
    "available": True,
    "tag": release["tag_name"],
    "downloadUrl": dmg["browser_download_url"],
    "releaseUrl": release["html_url"],
    "publishedAt": release.get("published_at"),
}
destination.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
appcast_destination.write_text(appcast["browser_download_url"] + "\n", encoding="utf-8")
PY

if [[ -n "$APPCAST_FIXTURE" ]]; then
    cp -- "$APPCAST_FIXTURE" "$OUTPUT_ROOT/appcast.xml"
else
    curl --fail --silent --show-error --location \
        "$(tr -d '\n' < "$APPCAST_URL_INPUT")" \
        --output "$OUTPUT_ROOT/appcast.xml"
fi

printf 'Built Cornerlight Pages site at %s\n' "$OUTPUT_ROOT"
