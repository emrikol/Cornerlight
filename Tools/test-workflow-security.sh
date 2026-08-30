#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"

fail() {
    print -u2 -- "workflow security test failed: $*"
    exit 1
}

while IFS= read -r action; do
    [[ "$action" =~ '@[0-9a-f]{40}$' ]] \
        || fail "mutable or invalid action reference: $action"
done < <(grep -RhoE 'uses:[[:space:]]+[^[:space:]]+' .github/workflows | awk '{print $2}')

grep -Fq 'pull_request_target:' .github/workflows/allow-collab-prs.yml \
    || fail "collaborator gate lost its pull_request_target trigger"
if grep -Fq 'actions/checkout@' .github/workflows/allow-collab-prs.yml; then
    fail "pull_request_target workflow must never check out contributor code"
fi
grep -Fq 'git merge-base "$BASE_SHA" "$GITHUB_SHA"' .github/workflows/ci.yml \
    || fail "changelog gate must tolerate a history rewrite without a merge base"

print -- "Workflow security tests passed"
