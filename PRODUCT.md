# Product

## Purpose

Cornerlight is a personal macOS 26.6+ application launcher that always finds installed apps without depending on Spotlight indexing.

## Product boundary

Cornerlight owns only:

- one asynchronous enumeration of `/Applications`, `/System/Applications`, and `$HOME/Applications`, followed only by FSEvents-triggered rescans;
- deterministic, in-memory name filtering;
- persistent ordered app pins plus a bounded MRU list of activated application bundle identifiers for Spotlight's native seven-slot suggestion row;
- persistent hidden-app paths and a persistent Show Hidden Apps preference;
- adapting those bundle URLs into Spotlight's native app-section model;
- an event-driven, user-selected Hot Corner whose corresponding macOS Hot Corner is unassigned;
- an optional native Launch at Login registration;
- an optional, signed Sparkle update channel;
- a minimal native Settings window for Launch at Login, automatic update checks, available corners, and hidden apps;
- the platform glue needed for Spotlight's nonactivating focus lease in a third-party process.

Spotlight's installed launcher owns the visible product: panel, placement, 844 × 576 size, seven-column grid, glass, animation, search field, result collection, scrolling, selection, options, keyboard behavior, accessibility, dismissal, and application execution.

The category model is deliberately omitted. Categories are not required for the owner's launcher workflow.

## Priorities

1. Reliable focus acquisition and release.
2. Complete, index-free app discovery.
3. Native Spotlight behavior without a parallel lookalike implementation.
4. Near-zero idle CPU and small resident memory.
5. KISS: no polling, persistent application index, telemetry, multi-page preferences UI, or unrelated search features; Sparkle is the sole third-party package and update checks are the sole network path.

## Development constraints

- Default to the top-left Hot Corner while the existing bottom-left Spotlight corner remains untouched.
- Never move the pointer or automate a foreground acceptance test.
- Keep a stable signed app identity so Input Monitoring persists across builds.
- Treat private macOS APIs as version-pinned implementation details for this personal app.
- Keep the abandoned hand-wired UI implementation out of the public release history.
