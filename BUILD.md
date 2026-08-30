# Build and development

Cornerlight requires macOS 26.6 and Xcode 26.6. Its only runtime package dependency is Sparkle 2.9.6, pinned exactly in SwiftPM.

## Tooling

Install the local quality tools once:

```sh
brew install swiftformat swiftlint imagemagick actionlint shellcheck
./scripts/install-hooks.sh
```

## Canonical verification

```sh
./verify.sh          # format, lint, tests, release compile, workflow checks
./verify.sh --quick  # format, lint, tests, build-workflow checks
./audit.sh           # full verification plus dependency/source summary
```

These checks are headless. They never present the launcher, move the pointer, synthesize input, or take focus.

## Building the app

```sh
./build.sh                         # signed release bundle in dist/
./build.sh --debug
./build.sh --compile-only
./build.sh --install               # install without opening
./build.sh --restart-background    # explicitly replace and reopen quietly
./build.sh --distribution          # hardened Developer ID bundle for notarization
```

The default identity is `Apple Development: Derrick Tennant (8VA8WSH6G4)`. Override it with `CORNERLIGHT_SIGN_IDENTITY` or `--sign-identity`. Ad-hoc signing is rejected unless `--allow-adhoc` is explicit because it does not preserve Input Monitoring reliably. Distribution mode requires a Developer ID Application identity and adds Apple's hardened runtime and secure timestamp.

Every deployment is staged, signed, verified, and atomically promoted. A running target is never overwritten. Rebuilding never presents the panel unless a `--run` option is explicit.

## Static analysis

SwiftFormat, strict SwiftLint, Zsh syntax validation, Actionlint, and ShellCheck-backed workflow analysis run in every verification. The release audit additionally uses a local CodeQL Swift database built with the real SwiftPM build and an explicit run-all suite containing both `swift-security-and-quality.qls` and `swift-security-experimental.qls`. Generated databases and SARIF files are intentionally ignored.

The current reviewed scan is recorded in `SECURITY.md`. Re-run CodeQL after changing the private-framework boundary, Objective-C runtime dispatch, filesystem input handling, or deployment scripts.

## Continuous integration

GitHub Actions runs `./verify.sh` on the official `macos-26` image with Xcode 26.6. CI also enforces the changelog gate over each pushed or proposed change range.

Pushing a validated `vX.Y.Z` tag starts the release workflow. It imports the Developer ID certificate into an ephemeral keychain, creates a hardened signed app with its nested Sparkle components signed inside-out, notarizes and staples it, builds and notarizes a DMG, writes SHA-256 checksums, generates an Ed25519-signed Sparkle appcast, and publishes the ZIP, DMG, checksums, and appcast to a GitHub Release. Real WindowServer acceptance remains local because CI has no interactive desktop.

The same workflow can be dispatched manually against `main` to verify encrypted signing and notarization credentials end to end. A manual run performs every build, signing, Gatekeeper, and notarization check but cannot publish a GitHub Release.
