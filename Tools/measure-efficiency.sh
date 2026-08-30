#!/bin/zsh
set -euo pipefail

if (( $# < 1 || $# > 2 )); then
    print -u2 -- "Usage: $0 Cornerlight.app [RUNNING_PID]"
    exit 2
fi

BUNDLE="$1"
PID="${2:-}"
EXECUTABLE="$BUNDLE/Contents/MacOS/Cornerlight"
[[ -x "$EXECUTABLE" ]] || { print -u2 -- "Missing executable: $EXECUTABLE"; exit 2; }

print -- "bundle_kib=$(du -sk "$BUNDLE" | awk '{print $1}')"
print -- "executable_bytes=$(/usr/bin/stat -f '%z' "$EXECUTABLE")"
if [[ -n "$PID" ]]; then
    ps -p "$PID" -o pid=,pcpu=,rss=,etime=,command=
fi

MEASUREMENT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cornerlight-measure.XXXXXX")"
cleanup() {
    [[ "$MEASUREMENT_ROOT" == */cornerlight-measure.* ]] && rm -rf -- "$MEASUREMENT_ROOT"
}
trap cleanup EXIT INT TERM

/usr/bin/time -lp "$EXECUTABLE" --snapshot "$MEASUREMENT_ROOT/cornerlight.png" \
    2> "$MEASUREMENT_ROOT/time.txt"
print -- "snapshot_dimensions=$(sips -g pixelWidth -g pixelHeight "$MEASUREMENT_ROOT/cornerlight.png" 2>/dev/null | awk '/pixelWidth|pixelHeight/ { printf "%s%s", separator, $2; separator="x" }')"
sed -n '/^real /p; /maximum resident set size/p' "$MEASUREMENT_ROOT/time.txt"
