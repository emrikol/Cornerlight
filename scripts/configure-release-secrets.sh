#!/bin/zsh
set -euo pipefail

REPOSITORY="${CORNERLIGHT_GITHUB_REPOSITORY:-emrikol/Cornerlight}"
CERTIFICATE_PATH="${1:-}"
PROJECT_ROOT="${0:A:h:h}"
SECRET_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cornerlight-release-secrets.XXXXXX")"

cleanup() {
    rm -rf -- "$SECRET_ROOT"
}
trap cleanup EXIT INT TERM

[[ -f "$CERTIFICATE_PATH" ]] || {
    print -u2 -- "Usage: $0 /path/to/developer-id-certificate.p12"
    exit 2
}

command -v gh >/dev/null || { print -u2 -- "Missing required tool: gh"; exit 1; }
gh auth status >/dev/null

if [[ -z "${SIGNING_PASSWORD:-}" ]]; then
    read -r -s "SIGNING_PASSWORD?Password used when exporting the Developer ID certificate: "
    print
fi
if [[ -z "${NOTARIZATION_APPLE_ID:-}" ]]; then
    read -r "NOTARIZATION_APPLE_ID?Apple ID used for notarization: "
fi
if [[ -z "${NOTARIZATION_PASSWORD:-}" ]]; then
    read -r -s "NOTARIZATION_PASSWORD?App-specific password used for notarization: "
    print
fi
if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    cd "$PROJECT_ROOT"
    swift package resolve >/dev/null
    GENERATE_KEYS="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
    [[ -x "$GENERATE_KEYS" ]] || {
        print -u2 -- "Sparkle's generate_keys tool is unavailable"
        exit 1
    }
    "$GENERATE_KEYS" --account com.emrikol.Cornerlight -x "$SECRET_ROOT/sparkle-private-key"
    SPARKLE_PRIVATE_KEY="$(< "$SECRET_ROOT/sparkle-private-key")"
fi

CERTIFICATE_BASE64="$(openssl base64 -A -in "$CERTIFICATE_PATH")"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"

print -rn -- "$CERTIFICATE_BASE64" | gh secret set SIGNING_CERTIFICATE -R "$REPOSITORY"
print -rn -- "$SIGNING_PASSWORD" | gh secret set SIGNING_PASSWORD -R "$REPOSITORY"
print -rn -- "$KEYCHAIN_PASSWORD" | gh secret set KEYCHAIN_PASSWORD -R "$REPOSITORY"
print -rn -- "$NOTARIZATION_APPLE_ID" | gh secret set NOTARIZATION_APPLE_ID -R "$REPOSITORY"
print -rn -- "3T9RX85H44" | gh secret set NOTARIZATION_TEAM_ID -R "$REPOSITORY"
print -rn -- "$NOTARIZATION_PASSWORD" | gh secret set NOTARIZATION_PASSWORD -R "$REPOSITORY"
print -rn -- "$SPARKLE_PRIVATE_KEY" | gh secret set SPARKLE_PRIVATE_KEY -R "$REPOSITORY"

unset CERTIFICATE_BASE64 KEYCHAIN_PASSWORD SIGNING_PASSWORD NOTARIZATION_APPLE_ID \
    NOTARIZATION_PASSWORD SPARKLE_PRIVATE_KEY
print -- "Configured Cornerlight signing, notarization, and Sparkle secrets in $REPOSITORY"
