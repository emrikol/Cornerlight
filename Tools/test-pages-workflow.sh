#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cornerlight-pages-test.XXXXXX")"

cleanup() {
    rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

cd "$PROJECT_ROOT"

grep -Fq 'actions/configure-pages@983d7736d9b0ae728b81ab479565c72886d7745b # v5' .github/workflows/pages.yml
grep -Fq 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4' .github/workflows/pages.yml
grep -Fq -- '--directory _site' .github/workflows/pages.yml
grep -Fq 'name: github-pages' .github/workflows/pages.yml
grep -Fq 'actions/deploy-pages@d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e # v4' .github/workflows/pages.yml
grep -Fq 'workflow_run:' .github/workflows/pages.yml
grep -Fq 'mkdir -p -- "$OUTPUT_ROOT/assets"' scripts/build-pages.sh
if grep -Fq 'peaceiris/actions-gh-pages' .github/workflows/pages.yml; then
    printf '%s\n' "Obsolete Pages action found" >&2
    exit 1
fi

CORNERLIGHT_PAGES_OUTPUT="$TEST_ROOT/site" \
CORNERLIGHT_RELEASE_FIXTURE="$PROJECT_ROOT/Tests/Fixtures/latest-release.json" \
CORNERLIGHT_APPCAST_FIXTURE="$PROJECT_ROOT/Tests/Fixtures/appcast.xml" \
    scripts/build-pages.sh >/dev/null

test -f "$TEST_ROOT/site/index.html"
test -f "$TEST_ROOT/site/assets/app-icon.png"
grep -q 'class="source-roots"' "$TEST_ROOT/site/index.html"
grep -q 'class="convergence"' "$TEST_ROOT/site/index.html"
grep -q 'class="native-system"' "$TEST_ROOT/site/index.html"
if grep -q 'system-handoff-.*\.webp' "$TEST_ROOT/site/index.html"; then
  echo "Pages must render the handoff as HTML/CSS, not a flattened image" >&2
  exit 1
fi
test ! -e "$TEST_ROOT/site/assets/system-handoff-desktop.webp"
test ! -e "$TEST_ROOT/site/assets/system-handoff-mobile.webp"
test -f "$TEST_ROOT/site/fonts/OFL.txt"
test -f "$TEST_ROOT/site/appcast.xml"
cmp Resources/AppIcon.png "$TEST_ROOT/site/assets/app-icon.png"
grep -Fq '/System/Applications' "$TEST_ROOT/site/index.html"
grep -Fq '~/Applications' "$TEST_ROOT/site/index.html"
grep -Fq 'Cornerlight inventory' "$TEST_ROOT/site/index.html"
grep -Fq 'Native macOS UI' "$TEST_ROOT/site/index.html"
grep -Fq 'https://github.com/emrikol/Cornerlight/releases/download/v0.1.0/Cornerlight.dmg' "$TEST_ROOT/site/release.json"
grep -Fq '"tag": "v0.1.0"' "$TEST_ROOT/site/release.json"
grep -Fq 'Cornerlight Updates' "$TEST_ROOT/site/appcast.xml"
if grep -Fq 'v1.0.0' "$TEST_ROOT/site/index.html"; then
    printf '%s\n' "Invented release number found in website" >&2
    exit 1
fi

python3 - "$TEST_ROOT/site/index.html" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

class Parser(HTMLParser):
    pass

Parser().feed(Path(sys.argv[1]).read_text(encoding="utf-8"))
PY

node --check "$TEST_ROOT/site/site.js"
printf '%s\n' "Pages workflow tests passed"
