#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
git -C "$PROJECT_ROOT" config core.hooksPath hooks
print -- "Installed tracked Cornerlight hooks from $PROJECT_ROOT/hooks"
