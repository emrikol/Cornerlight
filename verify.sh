#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h}"
MODE="full"

if (( $# > 1 )); then
    print -u2 -- "Usage: $0 [--quick]"
    exit 2
fi
if (( $# == 1 )); then
    [[ "$1" == "--quick" ]] || { print -u2 -- "Usage: $0 [--quick]"; exit 2; }
    MODE="quick"
fi

require_tool() {
    command -v "$1" >/dev/null 2>&1 || {
        print -u2 -- "Missing required tool: $1"
        exit 1
    }
}

cd "$PROJECT_ROOT"
require_tool swift
require_tool swiftformat
require_tool swiftlint
require_tool plutil
require_tool actionlint
require_tool shellcheck

plutil -lint Resources/Info.plist >/dev/null
zsh -n build.sh verify.sh hooks/* scripts/*.sh Tools/*.sh
actionlint
swiftformat --lint .
swiftlint lint --strict
swift test -Xswiftc -warnings-as-errors
Tools/test-build-workflow.sh
Tools/test-appcast-workflow.sh
Tools/test-release-workflow.sh
Tools/test-pages-workflow.sh
Tools/test-workflow-security.sh

if [[ "$MODE" == "full" ]]; then
    swift build -c release -Xswiftc -warnings-as-errors
    Tools/test-visual-tools.sh
fi

git diff HEAD --check
print -- "Cornerlight verification passed ($MODE)"
