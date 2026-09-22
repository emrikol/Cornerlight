# Changelog

## [Unreleased]

## [0.1.12] - 2026-09-22

- Keep macOS 27, including Siri AI Beta, on Spotlight's applications-only window state while restoring CornerLight's live results container and collection snapshot after the native transition, preventing the header-only placeholder without initializing unrelated providers such as Photos.

## [0.1.11] - 2026-09-22

- Prewarm macOS 27's applications-only window state before the first Hot Corner invocation so Spotlight cannot replace CornerLight's populated results surface with its empty 87-point placeholder.
- Retry bounded notarization uploads during release packaging so a stalled Apple connection cannot consume the entire release job.

## [0.1.10] - 2026-09-22

- Superseded before publication.

## [0.1.9] - 2026-09-22

- Superseded before publication.

## [0.1.8] - 2026-09-22

- Keep macOS 27 on Spotlight's applications-only presentation path so CornerLight never initializes unrelated providers such as Photos, while supplying the rounded material background that path no longer draws itself.

## [0.1.7] - 2026-09-22

- Present macOS 27's launcher through the native Spotlight window state and clear its query model before each invocation, restoring the rounded background and preventing a previous search from leaving the launcher expanded.

## [0.1.6] - 2026-09-21

- Initialize macOS 27's dynamic Spotlight results host on the first app-browser presentation so a cold launch no longer collapses the application grid to zero height.
- Run Sparkle independently after compatible launcher services start, while retaining updater-first recovery when a future macOS version changes the private Spotlight runtime.

## [0.1.5] - 2026-09-21

- Keep Cornerlight's updater available when a future macOS release changes the private Spotlight runtime, automatically checking when permitted and otherwise offering an explicit recovery update check.

## [0.1.4] - 2026-09-21

- Restore native Hot Corner app browsing on macOS 27 after Spotlight moved its window and search controllers into SpotlightUIInternal.

## [0.1.3] - 2026-09-20

- Prevent focus loss during presentation from permanently wedging Hot Corner toggles when Spotlight omits a transition callback.

## [0.1.2] - 2026-09-15

- Prevent a crash when another menu opens after Cornerlight rebuilds its launcher for a display configuration change.

## [0.1.1] - 2026-09-08

- Rebuild the launcher after display configuration changes so its application grid fits the active screen after docking or leaving clamshell mode.

## [0.1.0] - 2026-08-30

- Initial public release.
