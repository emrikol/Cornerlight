# Cornerlight user stories

Each automated story is headless. Stories involving the actual pointer, WindowServer composition, TCC, or another foreground application also require the manual acceptance pass listed at the end.

## Open and close

- **US-OPEN-01:** A login/background launch remains invisible.  
  Test: `a background login launch stays hidden`
- **US-OPEN-02:** An explicit application launch requests presentation.  
  Test: `an explicit application launch opens the launcher`
- **US-OPEN-03:** One genuine top-left region entry invokes once; further events cannot retrigger until the pointer leaves.  
  Tests: `entering the hot corner invokes once until the pointer exits`, `an exit event only rearms after the pointer really leaves the region`
- **US-OPEN-04:** Every genuine corner entry reaches Spotlight's actual app-browse toggle; a second entry dismisses the retained launcher instead of creating another. Entries received while a native open or close transition is unfinished are parity-queued and replayed only after Spotlight's completion.
  Tests: `the hot corner toggles the retained launcher`, `a second hot corner entry dismisses a visible launcher even if permission changed`, `a toggle waits for the active native transition to finish`, `two queued toggles cancel by parity`, `dismissal supersedes an opening transition and ignores its stale completion`, `a toggle during dismissal starts only after dismissal completion`
- **US-OPEN-05:** Repeated show requests and later reopenings reuse one native Spotlight controller and panel.
  Tests: `repeated open requests reuse the visible launcher`, `closing retains Spotlights controller and can open it again`
- **US-OPEN-06:** When a reopen is queued during Spotlight's native close transition, the completed dismissal cannot clear content already prepared for that reopen.
  Test: `a completed dismissal cannot clear content prepared for a queued reopen`
- **US-CLOSE-01:** Escape, outside click, focus loss, and native launch dismissal are owned by Spotlight's `SPAppDelegate` and `MainWindowController`.  
  Tests: `spotlights main controller owns the launcher window`, `application focus loss reaches the visible launcher`, `application focus loss reaches the launcher until native dismissal is confirmed`, `click outside dismissal becomes idle only after native lifecycle completion`, `launching an app completes the native invocation lifecycle lease`; manual WindowServer acceptance required.
- **US-CLOSE-02:** A dismissed launcher reports Spotlight's own native visibility. Native panel `orderOut:` is the single final-cleanup boundary, and every genuine WindowServer corner entry clears Spotlight's Dock-only launch suppression before re-entering `SPAppDelegate.launchAppsBrowsingWithCompletion:`.
  Tests: `native app browse invocation is owned by Spotlights actual app delegate`, `a WindowServer corner entry cannot be consumed by Spotlights Dock suppression flag`, `native orderOut reports dismissal without a duplicate presentation state machine`, `the hot corner toggles the retained launcher`, `closing retains Spotlights controller and can open it again`, `application focus loss reaches the visible launcher`, `application focus loss reaches the launcher until native dismissal is confirmed`

## Native UI ownership

- **US-UI-01:** The visible window is an actual `SPSpotlightPanel` controlled by `SpotlightAppMacOS.MainWindowController`.  
  Test: `launch hosts Spotlights controller tree rather than a lookalike`
- **US-UI-02:** The search surface is the actual `SpotlightAppMacOS.SearchViewController`, `SearchField`, and `SearchResultsViewController`.  
  Tests: `launch hosts Spotlights controller tree rather than a lookalike`, `enumerated applications cross only Spotlights native result section boundary`
- **US-UI-03:** Spotlight owns the stock 844 × 576 platter and seven-column grid, saved placement, material, edge, shadow, opening/closing animation, typography, caret, options, scrolling, selection, accessibility, and launch commands. Cornerlight contains no parallel UI or geometry implementation.
  Automated contract: native class/selector tests; manual visual acceptance required.
- **US-UI-04:** The category strip is intentionally hidden because Cornerlight supplies no category model.
  Test: `enumerated applications cross only Spotlights native result section boundary`
- **US-UI-05:** Recent apps and the catalog are consecutive native sections in one scrolling results surface. The catalog has no text header; SearchUI supplies the native separator between the rows.
  Test: `recent apps and catalog share Spotlights scrolling results surface`
- **US-UI-06:** Spotlight renders every pinned tile. Cornerlight supplies persistent ordered paths and a pin symbol through Spotlight's inherited TLK badge-image path. A mouse-only local pointer path starts after SearchUI's native selection, uses its real item frames and icon image for the attached drag preview and insertion marker, and persists only a completed pinned reorder. It introduces no replacement row, cell, collection, global monitor, or keyboard capture. Recycled recent cells never retain the pin badge and recent tiles cannot start a drag.
  Tests: `native drag loop stays disabled so pointer reorder receives the complete gesture`, `a recent tile cannot enter the pinned pointer reorder`, `dragging a pin reorders only the persisted pinned sequence`, `native pinned tiles carry Spotlights TLK badge while recents do not`
- **US-UI-07:** Cornerlight's enumerated inventory never exposes Spotlight's metadata “Indexing” status. The actual `SPSpotlightIndexingView` remains ineligible and hidden even when Spotlight's native layout asks to show it.
  Test: `enumerated inventory never exposes Spotlights indexing status`
## Inventory and search

- **US-DISCOVER-01:** Scan exactly `/Applications`, `/System/Applications`, and `$HOME/Applications`.  
  Test: `default roots are the complete launcher search scope`
- **US-DISCOVER-02:** Find nested `.app` bundles, but never descend into an app bundle.  
  Tests: `scans nested application bundles and ignores other files`, `skips application bundle descendants`
- **US-DISCOVER-03:** Missing roots, hidden bundles, overlapping roots, and Cornerlight itself are handled safely.
  Tests: `missing application roots produce an empty catalog`, `hidden application bundles are ignored`, `overlapping roots do not duplicate an application`, `the launcher excludes its own application bundle`
- **US-DISCOVER-04:** Catalog order is deterministic and each bundle identifier comes directly from its Info.plist.  
  Tests: `catalog sorting is deterministic when application names match`, `application bundle identifier comes from its bundle information`
- **US-DISCOVER-05:** A native app context-menu command can persistently hide that exact enumerated bundle path. Hidden apps are removed before any sections cross into Spotlight, including the suggestion row.
  Tests: `hidden applications persist by their exact bundle path`, `hidden applications are prefiltered unless Show Hidden Apps is enabled`, `native application context menu toggles the selected app visibility`
- **US-DISCOVER-06:** Spotlight's native overflow menu offers a checked “Show Hidden Apps” command. While enabled, hidden apps remain in the enumerated inventory and their native context menu offers “Unhide This App.”
  Tests: `spotlights native overflow menu offers Show Hidden Apps`, `native application context menu toggles the selected app visibility`
- **US-DISCOVER-07:** Spotlight's native app context menu offers Pin/Unpin. Up to seven exact bundle paths persist in user-selected order, lead every recent item in the seven-slot row, and carry Spotlight's native TLK corner badge. Hidden pins remain persisted but do not appear in browse or search unless Show Hidden Apps is enabled.
  Tests: `native application menus pin and unpin the enumerated app`, `pins persist in order and cannot exceed the native row capacity`, `pinned apps lead the native seven item row and recents fill the remainder`, `native pinned tiles carry Spotlights TLK badge while recents do not`
- **US-SEARCH-01:** AppKit's public `NSText` field-editor change notification from Spotlight's native search field filters only Cornerlight's in-memory inventory. Indexed `setSections:` proposals never trigger filtering.
  Tests: `spotlights native query update reaches only the inventory adapter`, `filters case and diacritics and ranks prefixes first`
- **US-SEARCH-02:** Empty search preserves catalog order; no match yields no applications.  
  Tests: `empty query preserves catalog order`, `a search with no matches returns no applications`
- **US-SEARCH-03:** Enumerated URLs cross only the native `ATXAppIdentity`/`SPUISAppBrowseSectionBuilder` section boundary; indexed proposals cannot replace them.  
  Test: `enumerated applications cross only Spotlights native result section boundary`
- **US-SEARCH-04:** Persisted pins lead Spotlight's native seven-slot suggestion row. Cornerlight's bounded local MRU list and Spotlight's cached system suggestions fill the remaining slots. All sources are deduplicated, intersected with the visible enumerated inventory, and omitted from the following catalog section.
  Tests: `pinned apps lead the native seven item row and recents fill the remainder`, `browse mode does not duplicate suggested applications in the catalog`, `the suggestion row preserves Spotlight prediction order and contains at most seven apps`, `local recents lead system suggestions without duplicates`, `activating an application moves it to the front of the bounded recent history`, `recent application history persists across launcher controller lifetimes`, `duplicate bundle identifiers cannot crash the suggestion adapter`
- **US-LAUNCH-01:** Return, clicking, and keyboard movement are executed by Spotlight's native main/results controllers.  
  Test: `spotlights main controller owns the launcher window`; manual launch acceptance required.

## Focus and permission

- **US-FOCUS-01:** The process application is Spotlight's actual `SPApplication`, so its original paired focus claim, event tap, release, and deactivation code owns keyboard routing end to end.
  Test: `spotlights application class owns the complete focus lifecycle`
- **US-FOCUS-02:** Cornerlight never guesses or restores a previously frontmost application and keeps no parallel focus lease or dismissal state machine.
- **US-FOCUS-03:** A WindowServer focus-loss dismissal forwards its reason and completion through Spotlight's real asynchronous dismissal. Cornerlight never completes that callback while Spotlight may still acquire or release focus during its close animation.
  Test: `window server dismissal completion waits for Spotlights native close`
- **US-FOCUS-04:** Invoking stock Spotlight cannot also invoke Cornerlight through the hosted menu item's distributed toggle observer. Cornerlight makes a best-effort native focus yield if concurrent use occurs, but running both `SPApplication` processes concurrently is unsupported because WindowServer can restore the other process's hidden focus lease.
  Tests: `stock spotlight toggles cannot invoke the hosted native menu item`, `system spotlight preemption drains every native focus claim before deactivating`, `system spotlight preemption does not deactivate without a native focus claim`
- **US-PERMISSION-01:** When Input Monitoring is denied, present one explanatory prompt before the launcher and provide a direct link to the correct System Settings pane.  
  Tests: `a denied invocation explains Input Monitoring before presenting the launcher`, `repeated denied invocations cannot stack permission prompts`, `the permission button opens the macOS Input Monitoring pane after denial`
- **US-PERMISSION-02:** A stable designated requirement preserves the user's grant across rebuilt bundles.  
  Verification: `Tools/test-build-workflow.sh`, `Tools/check-tcc-identity.sh`, and manual TCC acceptance.

## Efficiency and safety

- **US-EFF-01:** Idle operation is event-driven: no polling timer, filesystem index, network, telemetry, or pointer control.
- **US-EFF-02:** Scan asynchronously once at startup, retain the small catalog in memory, and rescan only after coalesced application-directory FSEvents changes. Opening the launcher never scans.
- **US-EFF-03:** Construct Spotlight's hosted panel lazily on first use and retain that single native ownership graph for later reopenings. Never accumulate one private controller tree per invocation.
  Tests: `closing retains Spotlights controller and can open it again`, `a completed dismissal cannot clear content prepared for a queued reopen`
- **US-EFF-04:** A background process remains resident without appearing in Dock.
  Test: `the hot corner owner opts out of automatic process termination`
- **US-SAFE-01:** Automated verification must never order the launcher onscreen, activate it, move the cursor, or synthesize input.
- **US-SAFE-02:** A build never replaces a running bundle and never silently falls back to an unstable ad-hoc TCC identity.  
  Verification: `Tools/test-build-workflow.sh`

## Manual acceptance

After a signed background deployment, the owner verifies:

1. Top-left entry opens once and a second genuine entry closes it.
2. The panel appears at the same place and with the same native animation as Spotlight.
3. The search field is focused, has the native caret, and filters enumerated apps.
4. Return and click launch the intended app.
5. Escape, click-outside, launch, and corner-toggle all dismiss and immediately return keyboard input to the current application.
6. A later corner entry reopens the launcher.
7. Input Monitoring does not reprompt after a same-identity rebuild.
8. The native top row appears and recently activated enumerated apps move to its front.
9. Pin and Unpin appear in the native app context menu; pins persist, lead the top row, and can be reordered by dragging.
