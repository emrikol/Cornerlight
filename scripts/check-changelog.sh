#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${CORNERLIGHT_PROJECT_ROOT:-${0:A:h:h}}"
MODE="${1:-}"
VALUE="${2:-}"

usage() {
    print -u2 -- "Usage: $0 --staged | --range <base>..<head>"
    exit 2
}

case "$MODE" in
    --staged)
        (( $# == 1 )) || usage
        changed_files="$(git -C "$PROJECT_ROOT" diff --cached --name-only --diff-filter=ACMR)"
        ;;
    --range)
        (( $# == 2 )) || usage
        changed_files="$(git -C "$PROJECT_ROOT" diff --name-only --diff-filter=ACMR "$VALUE")"
        ;;
    *)
        usage
        ;;
esac

[[ -n "$changed_files" ]] || exit 0

requires_changelog=false
local_path=""
for local_path in ${(f)changed_files}; do
    case "$local_path" in
        Sources/*|PrivateModules/*|Resources/*|Package.swift|build.sh|verify.sh|hooks/*|scripts/*.sh|.github/workflows/*.yml)
            requires_changelog=true
            break
            ;;
    esac
done

[[ "$requires_changelog" == true ]] || exit 0

# The repository's root commit is the v0.1.0 source snapshot, so there is no
# earlier release to describe. Once the first version tag exists, the normal
# changelog policy applies permanently.
if [[ ! -e "$PROJECT_ROOT/CHANGELOG.md" ]] \
    && [[ -z "$(git -C "$PROJECT_ROOT" tag --list 'v[0-9]*.[0-9]*.[0-9]*')" ]]; then
    print -- "Changelog gate skipped for the initial release snapshot ($MODE)"
    exit 0
fi

if ! print -r -- "$changed_files" | grep -Fx -- "CHANGELOG.md" >/dev/null; then
    print -u2 -- "CHANGELOG.md must accompany product or release-workflow changes."
    print -u2 -- "Add a concise entry under [Unreleased], then stage it with the change."
    exit 1
fi

print -- "Changelog gate passed ($MODE)"
