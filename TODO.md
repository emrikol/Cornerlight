# TODO

## Completed architecture

- [x] Remove the former extracted/lookalike implementation before the first public commit.
- [x] Load the installed macOS 26.6 Spotlight executable and its required private frameworks dynamically.
- [x] Instantiate Spotlight's actual `MainWindowController`, `SPSpotlightPanel`, `SearchViewController`, `SearchField`, and `SearchResultsViewController`.
- [x] Remove Cornerlight's custom panel, search field/editor, result controller, collection layout, navigation, options menu, material, positioning, and animation implementation from the production path.
- [x] Convert enumerated bundle URLs to native `ATXAppIdentity` and `SPUISAppBrowseSectionBuilder` sections.
- [x] Keep Spotlight's indexed section proposals from replacing Cornerlight's enumerated inventory.
- [x] Read queries from Spotlight's native field and filter the inventory in memory.
- [x] Observe AppKit's public field-editor change notification for Spotlight's native search field and keep indexed `setSections:` proposals as a firewall only.
- [x] Feed a bounded local MRU list into Spotlight's native suggestion row.
- [x] Persist up to seven ordered app pins, place them before recents in Spotlight's native suggestion row, and expose Pin/Unpin through Spotlight's app context menu.
- [x] Reorder native pinned tiles with SearchUI's actual item frames and icon view, a mouse-only local pointer monitor, and no replacement collection, row, cell, or global input capture.
- [x] Pre-filter persistently hidden bundle paths before building Spotlight sections.
- [x] Extend Spotlight's native app context and overflow menus with Hide, Unhide, and Show Hidden Apps commands.
- [x] Persist Show Hidden Apps and apply hidden-app filtering before browse and search section construction.
- [x] Add a native Settings list for reviewing and unhiding persisted hidden apps.
- [x] Add a native Settings window that offers only Hot Corners not assigned by macOS.
- [x] Add an optional native Launch at Login setting using `SMAppService.mainApp`.
- [x] Add Sparkle 2.9.6 with a Cornerlight-specific Ed25519 key, lazy manual checks, optional automatic checks, signed appcast generation, and Pages publication.
- [x] Scan once asynchronously at startup, retain the catalog in memory, and rescan only after coalesced FSEvents changes.
- [x] Remove live prediction requests from presentation and use local MRU plus Apple's cached suggestions.
- [x] Omit the category model and keep Spotlight's category strip hidden.
- [x] Keep Spotlight's native metadata-index status ineligible because Cornerlight's inventory is enumerated rather than indexed.
- [x] Retain the event-driven WindowServer top-left Hot Corner.
- [x] Parity-queue rapid Hot Corner entries until Spotlight's active native transition completes.
- [x] Forward click-outside focus loss after native visibility changes and serialize until Spotlight's lifecycle dismissal completes.
- [x] Retain the paired key-focus lease required by Spotlight's nonactivating panel.
- [x] Use `SPSpotlightPanel.orderOut:` as the single native dismissal boundary, and forward reasoned dismissal completion through Spotlight's native asynchronous close before `SPApplication` releases focus.
- [x] Isolate the hosted `SPSpotlightMenuItem` from the system-wide Spotlight toggle and make a best-effort native focus yield if stock Spotlight is invoked. Concurrent use remains unsupported because WindowServer can restore a focus lease owned by the other process.
- [x] Preserve Input Monitoring across builds with staged deployment and a stable signing identity.
- [x] Add native-host contract tests and keep focus/hot-corner/inventory failure-path tests headless.

## Before manual acceptance

- [x] Run the complete test, format, lint, build-workflow, and native-host snapshot checks.
- [x] Sign, install, and restart Cornerlight quietly without presenting the panel.
- [x] Confirm two independent final-name builds have the same designated requirement.
- [x] Run CodeQL's official Swift security-and-quality and security-experimental suites against a traced product build with zero extraction errors.
- [x] Add the canonical verification command, tracked Git hooks, CI, build/release/privacy/security documentation, and changelog.
- [x] Create and push the `emrikol/Cornerlight` GitHub repository.
- [x] Add changelog-gated commits, validated release tags, signed and notarized release CI, checksums, and GitHub Release artifacts.

## Owner acceptance

Run focus acceptance with the stock Spotlight Applications Hot Corner disabled; concurrent use is a documented incompatibility.

- [ ] Verify top-left open, toggle-close, and reopen.
- [ ] Verify native placement and opening/closing animation against Spotlight.
- [ ] Verify immediate keyboard focus and native caret.
- [ ] Verify enumerated search, Return launch, and click launch.
- [ ] Verify Hide/Unhide, persisted Show Hidden Apps, and hidden-app search filtering.
- [ ] Verify Pin/Unpin, seven-slot persistence, recent-app backfill, and native drag reordering.
- [ ] Verify Settings offers only unassigned macOS Hot Corners and the selection survives relaunch.
- [ ] Verify manual and automatic Sparkle update checks against the published `v0.1.0` appcast.
- [ ] Verify Escape, outside click, app launch, and corner toggle always return keyboard input.
- [ ] Grant Input Monitoring once for the final `com.emrikol.Cornerlight` identity.
- [ ] Verify no repeated Input Monitoring prompt after a same-identity rebuild.
- [ ] Record visible and post-dismissal efficiency samples without running stock Spotlight concurrently.

## OS update maintenance

- [ ] On any macOS update, rerun the class/selector contract tests before installing.
- [ ] If Apple changes the private controller or section boundary, fail closed and re-audit that boundary rather than restoring a second UI implementation.
