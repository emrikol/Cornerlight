#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h}"
cd "$PROJECT_ROOT"

./verify.sh

print -- "\nDependency graph:"
swift package show-dependencies --format text

print -- "\nSource footprint:"
find Sources Tests Tools -type f \( -name '*.swift' -o -name '*.m' -o -name '*.sh' \) -print0 \
    | xargs -0 wc -l \
    | tail -n 1

print -- "\nExternal package dependencies: Sparkle 2.9.6 (exact SwiftPM pin)"
print -- "For the full interprocedural security scan, follow BUILD.md#static-analysis."
