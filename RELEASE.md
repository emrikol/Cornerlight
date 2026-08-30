# Release process

Tagged Cornerlight releases are distributed through GitHub as signed and notarized macOS applications. Cornerlight is not an App Store product; it intentionally loads version-pinned Apple Spotlight implementation code.

## One-time GitHub setup

Export the Developer ID Application identity and private key as a password-protected `.p12`, create an Apple app-specific password, then run:

```sh
./scripts/configure-release-secrets.sh /path/to/developer-id-certificate.p12
```

The script writes seven encrypted Actions secrets without printing their values: `SIGNING_CERTIFICATE`, `SIGNING_PASSWORD`, `KEYCHAIN_PASSWORD`, `NOTARIZATION_APPLE_ID`, `NOTARIZATION_TEAM_ID`, `NOTARIZATION_PASSWORD`, and `SPARKLE_PRIVATE_KEY`. The Cornerlight-specific Sparkle seed is exported from the `com.emrikol.Cornerlight` account in the login Keychain. Never reuse TwinKley's update key or remove this Keychain backup after publishing a release; existing clients trust the corresponding public key embedded in Cornerlight.

After configuring the secrets, run `gh workflow run Release --ref main` once. This manual preflight exercises certificate import, nested Sparkle signing, hardened signing, app and DMG notarization, stapling, Gatekeeper, and packaging without publishing a release.

## Prepare a release

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist`.
2. Move every `[Unreleased]` bullet into `## [X.Y.Z] - YYYY-MM-DD` in `CHANGELOG.md`. The unreleased section must be empty at the tagged commit.
3. Run `./audit.sh` and review the CodeQL record in `SECURITY.md`.
4. Build and install without opening the panel with `./build.sh --install`.
5. For an existing installation, compare the old and rebuilt designated requirements with `Tools/check-tcc-identity.sh` before promotion.
6. Restart quietly with `./build.sh --restart-background`, then complete the owner-acceptance list in `TODO.md`.
7. Commit and push `main`. The release helper requires a clean `main` exactly equal to `origin/main`.
8. Create and push the annotated tag:

   ```sh
   ./scripts/create-release-tag.sh vX.Y.Z
   git push origin vX.Y.Z
   ```

The tag push revalidates the plist, build number, changelog date, release notes, and empty unreleased section. GitHub Actions then verifies the source, signs with Developer ID and hardened runtime, notarizes the app and DMG, staples both, generates checksums and a signed Sparkle appcast, and creates the GitHub Release. A failure leaves no partial GitHub Release.

After the Release workflow succeeds, the Pages workflow rebuilds the project website, points its primary action directly at the latest published `Cornerlight.dmg`, and publishes that release's `appcast.xml`. Pages can also be deployed manually without publishing an app release.

## Identity transition

The rename from the development codename changed the final identifier to `com.emrikol.Cornerlight`. macOS therefore requires one fresh Input Monitoring grant. Builds signed with the same identity and identifier must not prompt again.

Do not switch between Apple Development, Developer ID, and ad-hoc signatures for the installed copy. A changed designated requirement is a different privacy identity.
