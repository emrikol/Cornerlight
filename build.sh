#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h}"
APP_NAME="Cornerlight"
EXECUTABLE_NAME="Cornerlight"
OUTPUT_ROOT="${CORNERLIGHT_OUTPUT_ROOT:-$PROJECT_ROOT/dist}"
INSTALL_ROOT="${CORNERLIGHT_INSTALL_ROOT:-$HOME/Applications}"
OUTPUT_BUNDLE="$OUTPUT_ROOT/$APP_NAME.app"
INSTALL_BUNDLE="$INSTALL_ROOT/$APP_NAME.app"

APPLE_DEVELOPMENT_PREFIX="Apple Development:"
DEVELOPER_ID_PREFIX="Developer ID Application:"

CONFIGURATION="release"
COMPILE_ONLY=false
INSTALL=false
RUN_MODE="none"
RESTART_BACKGROUND=false
ALLOW_ADHOC=false
SIGN_IDENTITY="${CORNERLIGHT_SIGN_IDENTITY:-}"
PREFER_DEVELOPER_ID=false
FOR_DISTRIBUTION=false
COMPARE_REQUIREMENT_BUNDLE=""

usage() {
    cat <<'EOF'
Usage: ./build.sh [options]

Build options:
  --debug                         Build without release stripping.
  --compile-only                  Compile without creating or replacing an app bundle.
  --sign-identity IDENTITY        Override the signing identity.
  --developer-id                  Prefer the installed Developer ID identity.
  --distribution                  Create a Developer ID build with hardened runtime and timestamp.
  --allow-adhoc                   Allow ad-hoc signing when no stable identity is available.
  --compare-requirement BUNDLE    Require the new bundle to have BUNDLE's designated requirement.

Deployment and launch options:
  --install                       Install to ~/Applications without opening the app.
  --run                           Explicitly open the newly built or installed app.
  --run-background                Install and explicitly open it quietly with --background.
  --restart-background            Stop resident copies, install, and relaunch quietly.
EOF
}

fail() {
    print -u2 -- "Cornerlight build: $*"
    exit 1
}

while (( $# > 0 )); do
    case "$1" in
        --debug)
            CONFIGURATION="debug"
            ;;
        --compile-only)
            COMPILE_ONLY=true
            ;;
        --install)
            INSTALL=true
            ;;
        --run)
            RUN_MODE="foreground"
            ;;
        --run-background)
            RUN_MODE="background"
            INSTALL=true
            ;;
        --restart-background)
            RUN_MODE="background"
            RESTART_BACKGROUND=true
            INSTALL=true
            ;;
        --allow-adhoc)
            ALLOW_ADHOC=true
            ;;
        --developer-id)
            PREFER_DEVELOPER_ID=true
            ;;
        --distribution)
            FOR_DISTRIBUTION=true
            PREFER_DEVELOPER_ID=true
            ;;
        --sign-identity)
            (( $# >= 2 )) || fail "--sign-identity requires a value"
            SIGN_IDENTITY="$2"
            shift
            ;;
        --compare-requirement)
            (( $# >= 2 )) || fail "--compare-requirement requires a bundle path"
            COMPARE_REQUIREMENT_BUNDLE="$2"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "unknown option: $1"
            ;;
    esac
    shift
done

if [[ "$COMPILE_ONLY" == true && ("$INSTALL" == true || "$RUN_MODE" != "none" || "$RESTART_BACKGROUND" == true) ]]; then
    fail "--compile-only cannot install, run, or restart the app"
fi
if [[ "$FOR_DISTRIBUTION" == true && "$CONFIGURATION" != "release" ]]; then
    fail "--distribution requires a release build"
fi
if [[ "$FOR_DISTRIBUTION" == true && "$ALLOW_ADHOC" == true ]]; then
    fail "--distribution cannot use ad-hoc signing"
fi

canonical_executable() {
    local bundle="$1"
    local parent="${bundle:h}"
    local name="${bundle:t}"
    mkdir -p "$parent"
    print -r -- "${parent:A}/$name/Contents/MacOS/$EXECUTABLE_NAME"
}

running_pids() {
    local executable
    executable="$(canonical_executable "$1")"
    ps -axo pid=,args= | awk -v executable="$executable" '
        {
            pid = $1
            sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", $0)
            if ($0 == executable || index($0, executable " ") == 1) {
                print pid
            }
        }
    '
}

refuse_live_target() {
    local bundle="$1"
    local pids
    pids="$(running_pids "$bundle")"
    [[ -z "$pids" ]] || fail "refusing to replace live $bundle (PIDs: ${(j:, :)${(f)pids}})"
}

stop_live_target() {
    local bundle="$1"
    local pids
    pids="$(running_pids "$bundle")"
    [[ -n "$pids" ]] || return 0

    print -- "Stopping $bundle (PIDs: ${(j:, :)${(f)pids}})"
    local pid
    for pid in ${(f)pids}; do
        kill -TERM "$pid"
    done
    for pid in ${(f)pids}; do
        local attempts=0
        while kill -0 "$pid" 2>/dev/null; do
            (( attempts += 1 ))
            (( attempts < 50 )) || fail "PID $pid did not exit after SIGTERM"
            sleep 0.1
        done
    done
}

available_identities() {
    security find-identity -v -p codesigning 2>/dev/null || true
}

resolve_signing_identity() {
    local identities
    identities="$(available_identities)"

    if [[ -n "$SIGN_IDENTITY" ]]; then
        if [[ "$SIGN_IDENTITY" == "-" ]]; then
            [[ "$ALLOW_ADHOC" == true ]] || fail "ad-hoc identity requires --allow-adhoc"
            print -r -- "-"
            return
        fi
        [[ "$identities" == *\"$SIGN_IDENTITY\"* ]] || fail "signing identity is not installed: $SIGN_IDENTITY"
        print -r -- "$SIGN_IDENTITY"
        return
    fi

    local preferred_prefix="$APPLE_DEVELOPMENT_PREFIX"
    if [[ "$PREFER_DEVELOPER_ID" == true ]]; then
        preferred_prefix="$DEVELOPER_ID_PREFIX"
    fi

    local preferred
    preferred="$(
        print -r -- "$identities" \
            | sed -n 's/^[^\"]*\"\([^\"]*\)\".*/\1/p' \
            | grep -m 1 "^${preferred_prefix}" \
            || true
    )"
    if [[ -n "$preferred" ]]; then
        print -r -- "$preferred"
    elif [[ "$ALLOW_ADHOC" == true ]]; then
        print -u2 -- "Cornerlight build: warning: ad-hoc signing changes the app's TCC identity after every rebuild"
        print -r -- "-"
    else
        fail "required signing identity is unavailable: $preferred_prefix; use an explicit --sign-identity or --allow-adhoc"
    fi
}

designated_requirement() {
    local bundle="$1"
    codesign -d -r- "$bundle" 2>&1 | sed -n 's/^designated => //p'
}

verify_matching_requirement() {
    local previous="$1"
    local next="$2"
    [[ -d "$previous" ]] || fail "requirement comparison bundle does not exist: $previous"
    local previous_requirement next_requirement
    previous_requirement="$(designated_requirement "$previous")"
    next_requirement="$(designated_requirement "$next")"
    [[ -n "$previous_requirement" && -n "$next_requirement" ]] || fail "could not read both designated requirements"
    [[ "$previous_requirement" == "$next_requirement" ]] || fail "designated requirement changed across builds"
}

cleanup_roots=()
cleanup() {
    local root
    for root in $cleanup_roots; do
        if [[ -n "$root" && ("$root" == "$OUTPUT_ROOT"/.cornerlight-stage.* || "$root" == "$INSTALL_ROOT"/.cornerlight-install.*) ]]; then
            rm -rf -- "$root"
        fi
    done
}
trap cleanup EXIT INT TERM

promote_bundle() {
    local staged_bundle="$1"
    local target_bundle="$2"
    local backup_bundle="${target_bundle}.previous.$$"
    refuse_live_target "$target_bundle"

    if [[ -e "$target_bundle" ]]; then
        mv "$target_bundle" "$backup_bundle"
    fi
    if mv "$staged_bundle" "$target_bundle"; then
        if [[ -e "$backup_bundle" ]]; then
            rm -rf -- "$backup_bundle"
        fi
    else
        if [[ -e "$backup_bundle" ]]; then
            mv "$backup_bundle" "$target_bundle"
        fi
        fail "could not promote staged bundle to $target_bundle"
    fi
}

cd "$PROJECT_ROOT"
swift build -c "$CONFIGURATION"

if [[ "$COMPILE_ONLY" == true ]]; then
    print -- "Compiled Cornerlight ($CONFIGURATION); no app bundle was replaced."
    exit 0
fi

mkdir -p "$OUTPUT_ROOT"
STAGE_ROOT="$(mktemp -d "$OUTPUT_ROOT/.cornerlight-stage.XXXXXX")"
cleanup_roots+=("$STAGE_ROOT")
STAGED_BUNDLE="$STAGE_ROOT/$APP_NAME.app"
mkdir -p \
    "$STAGED_BUNDLE/Contents/MacOS" \
    "$STAGED_BUNDLE/Contents/Frameworks" \
    "$STAGED_BUNDLE/Contents/Resources" \
    "$STAGED_BUNDLE/Contents/Resources/Licenses"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
cp "$BIN_DIR/$EXECUTABLE_NAME" "$STAGED_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
[[ -d "$BIN_DIR/Sparkle.framework" ]] || fail "SwiftPM did not produce Sparkle.framework"
ditto "$BIN_DIR/Sparkle.framework" "$STAGED_BUNDLE/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$STAGED_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_ROOT/Resources/Info.plist" "$STAGED_BUNDLE/Contents/Info.plist"
ICON_PARTIAL_INFO="$STAGE_ROOT/AppIcon-Info.plist"
xcrun actool "$PROJECT_ROOT/Resources/AppIcon.icon" \
    --compile "$STAGED_BUNDLE/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.6 \
    --target-device mac \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_PARTIAL_INFO" \
    > "$STAGE_ROOT/AppIcon-actool-result.plist"
[[ -s "$STAGED_BUNDLE/Contents/Resources/AppIcon.icns" ]] \
    || fail "actool did not produce AppIcon.icns"
[[ -s "$STAGED_BUNDLE/Contents/Resources/Assets.car" ]] \
    || fail "actool did not produce the Icon Composer asset catalog"
cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.md" \
    "$STAGED_BUNDLE/Contents/Resources/THIRD_PARTY_NOTICES.md"
SPARKLE_LICENSE="${CORNERLIGHT_SPARKLE_LICENSE:-$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/LICENSE}"
[[ -f "$SPARKLE_LICENSE" ]] || fail "Sparkle license is unavailable: $SPARKLE_LICENSE"
cp "$SPARKLE_LICENSE" "$STAGED_BUNDLE/Contents/Resources/Licenses/Sparkle.txt"

if [[ "$CONFIGURATION" == "release" ]]; then
    strip -S -x "$STAGED_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
fi

RESOLVED_SIGN_IDENTITY="$(resolve_signing_identity)"

sign_embedded_component() {
    local component="$1"
    if [[ "$FOR_DISTRIBUTION" == true ]]; then
        codesign --force --options runtime --timestamp \
            --preserve-metadata=identifier,entitlements,requirements \
            --sign "$RESOLVED_SIGN_IDENTITY" "$component"
    else
        codesign --force \
            --preserve-metadata=identifier,entitlements,requirements \
            --sign "$RESOLVED_SIGN_IDENTITY" "$component"
    fi
}

SPARKLE_FRAMEWORK="$STAGED_BUNDLE/Contents/Frameworks/Sparkle.framework"
SPARKLE_CONTENTS="$SPARKLE_FRAMEWORK/Versions/B"
sign_embedded_component "$SPARKLE_CONTENTS/Autoupdate"
sign_embedded_component "$SPARKLE_CONTENTS/XPCServices/Downloader.xpc"
sign_embedded_component "$SPARKLE_CONTENTS/XPCServices/Installer.xpc"
sign_embedded_component "$SPARKLE_CONTENTS/Updater.app"
sign_embedded_component "$SPARKLE_FRAMEWORK"

if [[ "$FOR_DISTRIBUTION" == true ]]; then
    [[ "$RESOLVED_SIGN_IDENTITY" == "Developer ID Application:"* ]] \
        || fail "distribution builds require a Developer ID Application identity"
    codesign --force --options runtime --timestamp --sign "$RESOLVED_SIGN_IDENTITY" "$STAGED_BUNDLE"
else
    codesign --force --sign "$RESOLVED_SIGN_IDENTITY" "$STAGED_BUNDLE"
fi
codesign --verify --deep --strict "$STAGED_BUNDLE"

if [[ -n "$COMPARE_REQUIREMENT_BUNDLE" ]]; then
    verify_matching_requirement "$COMPARE_REQUIREMENT_BUNDLE" "$STAGED_BUNDLE"
fi

if [[ "$INSTALL" == true && -d "$INSTALL_BUNDLE" ]]; then
    verify_matching_requirement "$INSTALL_BUNDLE" "$STAGED_BUNDLE"
fi

if [[ "$RESTART_BACKGROUND" == true ]]; then
    stop_live_target "$OUTPUT_BUNDLE"
fi
promote_bundle "$STAGED_BUNDLE" "$OUTPUT_BUNDLE"

DEPLOYED_BUNDLE="$OUTPUT_BUNDLE"
if [[ "$INSTALL" == true ]]; then
    if [[ "$RESTART_BACKGROUND" == true ]]; then
        stop_live_target "$INSTALL_BUNDLE"
    fi
    mkdir -p "$INSTALL_ROOT"
    INSTALL_STAGE_ROOT="$(mktemp -d "$INSTALL_ROOT/.cornerlight-install.XXXXXX")"
    cleanup_roots+=("$INSTALL_STAGE_ROOT")
    STAGED_INSTALL_BUNDLE="$INSTALL_STAGE_ROOT/$APP_NAME.app"
    ditto "$OUTPUT_BUNDLE" "$STAGED_INSTALL_BUNDLE"
    codesign --verify --deep --strict "$STAGED_INSTALL_BUNDLE"
    promote_bundle "$STAGED_INSTALL_BUNDLE" "$INSTALL_BUNDLE"
    DEPLOYED_BUNDLE="$INSTALL_BUNDLE"
fi

print -- "Built $OUTPUT_BUNDLE"
print -- "Signed bundle with the configured identity."
if [[ "$INSTALL" == true ]]; then
    print -- "Installed $INSTALL_BUNDLE (not launched)"
fi

case "$RUN_MODE" in
    foreground)
        open "$DEPLOYED_BUNDLE" --args --show
        ;;
    background)
        open -g "$DEPLOYED_BUNDLE" --args --background
        ;;
esac
