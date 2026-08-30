#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
    print -u2 -- "Usage: $0 PREVIOUS/Cornerlight.app REBUILT/Cornerlight.app"
    exit 2
fi

PREVIOUS="$1"
REBUILT="$2"
for BUNDLE in "$PREVIOUS" "$REBUILT"; do
    [[ -d "$BUNDLE" ]] || { print -u2 -- "Missing bundle: $BUNDLE"; exit 2; }
    codesign --verify --deep --strict "$BUNDLE"
done

requirement() {
    codesign -d -r- "$1" 2>&1 | sed -n 's/^designated => //p'
}

identifier() {
    codesign -d --verbose=4 "$1" 2>&1 | sed -n 's/^Identifier=//p'
}

PREVIOUS_REQUIREMENT="$(requirement "$PREVIOUS")"
REBUILT_REQUIREMENT="$(requirement "$REBUILT")"
PREVIOUS_IDENTIFIER="$(identifier "$PREVIOUS")"
REBUILT_IDENTIFIER="$(identifier "$REBUILT")"

[[ -n "$PREVIOUS_REQUIREMENT" && "$PREVIOUS_REQUIREMENT" == "$REBUILT_REQUIREMENT" ]] || {
    print -u2 -- "TCC identity failure: designated requirement changed"
    exit 1
}
[[ -n "$PREVIOUS_IDENTIFIER" && "$PREVIOUS_IDENTIFIER" == "$REBUILT_IDENTIFIER" ]] || {
    print -u2 -- "TCC identity failure: bundle identifier changed"
    exit 1
}

print -- "bundle_identifier=$REBUILT_IDENTIFIER"
print -- "designated_requirement=$REBUILT_REQUIREMENT"
print -- "identity_stable=yes"
print -- "Next manual check: grant Input Monitoring once, invoke Cornerlight, rebuild with the same identity, restart, and invoke again. macOS must not prompt a second time."

