# Spotlight parity contract — macOS 26.6

## Exact by construction

Cornerlight hosts Spotlight's actual `SPAppDelegate`, `MainWindowController`, `SPSpotlightPanel`, `SearchViewController`, `SearchField`, and `SearchResultsViewController`. The following are no longer copied or visually approximated:

- panel size, position, material, edge, shadow, and corner treatment;
- invocation and dismissal animation;
- search typography, caret, field editor, and focus behavior;
- options button and menu;
- result collection layout, scrolling, icon presentation, labels, selection, and accessibility;
- keyboard navigation and application execution;
- outside-click, Escape, and focus-loss dismissal handled by the native controller.

## Intentional difference

Spotlight normally proposes indexed result sections. Cornerlight replaces those proposals at the native `SearchResultsViewController.setSections:` boundary with sections built from directly enumerated bundle URLs. AppKit's public `NSText` field-editor change notification from Spotlight's native search field—not indexed section delivery—triggers local filtering. A bounded local MRU list leads Spotlight's system suggestions in the native style-1 suggestion section. The category model is not supplied, so the category strip is intentionally absent. Spotlight's native metadata-index progress view is also marked ineligible because Cornerlight has no indexing phase.

Cornerlight can also persistently hide an exact enumerated bundle path. That filter runs before browse or search sections are built, and the Show Hidden Apps override is itself persistent. The commands are appended at Spotlight's own `SearchUICollectionViewController.menuForItemAtIndexPath:` and `ViewOptionsMenu.update` callbacks; Cornerlight does not introduce a replacement menu or results surface. The clicked bundle URL comes from Spotlight's native Open-command `dictionaryRepresentation` (the row model deliberately leaves its public URL fields empty) and is accepted only when it matches the current enumerated inventory. The menu hook keeps one weak owner for Cornerlight's single native host rather than associating it with a disposable Spotlight collection-controller instance.

Opening Settings is a destination handoff after Spotlight's native dismissal completes. Cornerlight does not intervene in the native focus lease or deactivation sequence during normal operation. The sole coexistence exception is a stock Spotlight toggle, where Cornerlight makes a best-effort release of outstanding native claims before dismissal.

## Required third-party glue

- The actual `SPApplication` singleton is `NSApp`; its paired private key-focus selectors, mouse-only event tap, `sendEvent:`, and deactivation code run unchanged.
- Input Monitoring remains user-visible because that native mouse-only tap executes under Cornerlight's third-party process identity.
- Cornerlight stores no Spotlight UI geometry and does not mutate Spotlight preferences. The native controller reads its own normal state.
- Hot Corner toggles call the loaded Spotlight executable's actual `SPAppDelegate.launchAppsBrowsingWithCompletion:` implementation. Before that call, the WindowServer adapter clears `ignoreDockAppsLaunch`, a suppression bit native Spotlight uses only to consume Dock's paired launch message after dismissal. The adapter does not re-enter this method before its native completion; rapid entries are parity-queued and replayed afterward. The native method owns `isInvoked`, screen preparation, app-browse invocation reason `0x24`, visible-state toggling, animated dismissal reason `0x12`, and the final `SPSpotlightPanel.orderOut:` transition.
- Focus loss always calls the actual `SPAppDelegate.applicationLostFocus` implementation, even if Spotlight has already changed `spotlightIsVisible` during event delivery. Its internal reason-15 close remains transition-locked until Spotlight's own `SPSpotlightPanel.orderOut:` lifecycle confirms completion.
- Final cleanup observes only `SPSpotlightPanel.orderOut:` to release Cornerlight's inventory snapshot. A reasoned WindowServer dismissal forwards its original completion through `SPAppDelegate.dismissSpotlightWithReason:completion:`; only that native asynchronous completion returns to `SPApplication` for focus release and deactivation. Cornerlight never chooses or reactivates an application.
- Cornerlight constructs only `SPAppDelegate.applicationDidFinishLaunching:`'s app-browse ownership branch. It intentionally skips the complete startup method because that method momentarily orders the panel front and creates the unrelated general-search controller, neither of which belongs in a quiet background launcher.
- `SPSpotlightMenuItem.init` registers `_toggle` for the distributed `com.apple.spotlight.toggle` notification. That observer is correct in Apple's sole Spotlight process but would make stock Spotlight also invoke Cornerlight. Cornerlight unregisters only this inherited observer and installs a passive handler for the same event: hidden Cornerlight does nothing; visible or transitioning Cornerlight drains `SPApplication._releaseKeyFocus`, deactivates if a claim existed, and starts the native dismissal. This mitigation is event-driven and has no polling or idle timer, but it cannot serialize focus leases owned by two processes. Concurrent stock Spotlight and Cornerlight use is therefore unsupported.
- The top-left Hot Corner is registered through WindowServer region events because Dock's Hot Corner preferences cannot target arbitrary applications.

## Version risk

All private class names and selector contracts are pinned to macOS 26.6. Native-host tests fail closed when those entry points change. An OS update requires a fresh runtime/decompile audit before deployment.

## Recovery

The last complete hand-wired implementation was intentionally omitted from the first public commit. The shipped implementation hosts Spotlight's native controller tree instead.
