# Security and static analysis

Cornerlight has no inbound network surface, parser for user documents, or product subprocess execution path. Its sensitive boundaries are local filesystem enumeration, dynamic loading of Apple private frameworks, Objective-C runtime dispatch, Input Monitoring, Sparkle's outbound update channel, signing, and atomic bundle deployment.

## Controls

- Application discovery is limited to three explicit roots and produces bundle records only.
- Deployment stages into validated task-specific directories and refuses to replace a running target.
- Ad-hoc signing requires an explicit override.
- Automated tests do not synthesize input or change privacy settings.
- Sparkle is pinned exactly to 2.9.6. Updates require both the app's Developer ID continuity and the Cornerlight-specific Ed25519 key; the private seed is stored in the owner's login Keychain and as an encrypted Actions secret.
- GitHub Actions are pinned to immutable commit SHAs, and the signing job runs on a fresh runner that never installs Homebrew packages.
- Strict SwiftLint, SwiftFormat, warnings-as-errors builds, and CodeQL supplement the story tests.

## CodeQL

The 2026-08-30 release audit builds a traced Swift database from the real SwiftPM compilation and runs the official Swift security-and-quality and security-experimental suites with local threat sources enabled. No custom data-extension model is warranted: Cornerlight defines no wrapper around HTTP input, SQL, shell execution, template rendering, deserialization, or another CodeQL source/sink API. Sparkle's fixed update-feed transport is inside its pinned binary dependency rather than Cornerlight's Swift source.

Generated SARIF and databases stay local and are not committed. CodeQL 2.26.0 resolved 31 official Swift queries and reported **0 alerts**. Database validation reported 6,480 baseline lines across the product source and two SwiftPM manifests with **0 extractor errors** and **0 unresolved AST nodes**. The scan record is retained locally in `static_analysis_codeql_2/`.

## Reporting

Issues are disabled. Collaborators should report a suspected vulnerability to the owner through an existing private channel and must not publish exploit details for unreleased code.
