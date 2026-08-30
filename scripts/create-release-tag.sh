#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
TAG="${1:-}"
[[ "$TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]] || {
    print -u2 -- "Usage: $0 vX.Y.Z"
    exit 2
}

cd "$PROJECT_ROOT"
[[ -z "$(git status --porcelain)" ]] || { print -u2 -- "Working tree must be clean"; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { print -u2 -- "Release tags must be created from main"; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 && {
    print -u2 -- "Tag already exists locally: $TAG"
    exit 1
}
git fetch --quiet origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || {
    print -u2 -- "HEAD must exactly match origin/main before tagging"
    exit 1
}

./verify.sh
./scripts/validate-release.sh "$TAG" --revision HEAD
VERSION="${TAG#v}"
git tag -a "$TAG" -m "Cornerlight $VERSION"
print -- "Created $TAG; push it with: git push origin $TAG"
