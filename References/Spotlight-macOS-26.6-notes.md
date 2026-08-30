# Spotlight Applications reference notes

These values were recovered locally from the Spotlight implementation shipped with macOS 26.6 and checked against local reference captures that are not distributed with Cornerlight. They are implementation evidence, not reconstructed Apple source code.

## Binaries inspected

- `/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight`
- `/System/Library/PrivateFrameworks/SpotlightUIShared.framework/Versions/A/SpotlightUIShared`
- The dyld-cache images for `SpotlightUIServices` and `SearchUI`

The recovered Spotlight ARM64e image has MD5 `1cf9a4771663c882771099e0b23abf38`. Relevant entry points in that image are:

- `SPAppDelegate.launchAppsBrowsingWithCompletion:` — `0x10000c3ac`
- `SPAppDelegate.prepareForScreen:` — `0x10000bc50`
- `SPSpotlightPanel.setScreen:` — `0x1000116d8`
- `SPSpotlightPanel.constrainFrameRect:toScreen:` — `0x100012498`
- `SPSpotlightPanel.defaultPositionOriginForWindowSize:screen:` — `0x1000129d4`
- `MainWindowController.adjustedRectForCurrentPlatterBehaviorFromStandardRect:` — `0x10002fd00`
- `SPUIUtilities.screenContainingMousePointer` — `0x100014860`
- Applications invocation coordinator — `0x10002066c`
- invocation layer preparation — `0x100021c30`
- alpha-animation builder — `0x100027e84`
- main-window invocation caller — `0x10002fda0`

The Swift accessors in `SpotlightUIShared` report this `ResultPlatterBehavior.gridBrowse` contract:

- Width: 844 points
- Minimum height: 520 points
- Preferred height: none
- Maximum height: 5,000 points
- Include filter-bar height: true
- Persist height: false
- Animated: true

The standard Applications platter adds Spotlight's 56-point search band to the 520-point grid-browse minimum, producing the 844 × 576-point window used by Cornerlight.

## Search and platter constants

- Standard Applications browse height: 576 points
- Collapsed/search band height: 56 points
- Top-level filter content: 160 points
- Horizontal content inset: 20 points
- Separator height: 1 point
- Window corner radius: 28 points
- Invocation-only window padding: 40 points on every edge
- Token corner radius: 9 points

## Native glass and panel behavior

`SPVisualEffects.mainWindowVisualEffectView` selects the system appearance path at runtime. On macOS 26's Solarium appearance it constructs `NSGlassView`, sets a 28-point corner radius, and enables adaptive appearance. The older fallback is a `fullScreenUI` `NSVisualEffectView` with a material corner radius and continuous corners. Neither path adds a fixed dark overlay, layer mask, or custom perimeter stroke.

`SPSpotlightPanel.configureAppearanceAndBehavior` makes the window transparent and non-opaque, retains the standard panel shadow, and uses window level 23. `SPUIUtilities.screenContainingMousePointer` tests `NSEvent.mouseLocation` against each `NSScreen.frame`, falling back to the main screen.

The panel is constructed with style-mask raw value `0x98`: `resizable`, `utilityWindow`, and `nonactivatingPanel`. It is not constructed with `fullSizeContentView`. The initializer first sets level 19 and allows cursor rectangles while inactive; `configureAppearanceAndBehavior` then sets `becomesKeyOnlyIfNeeded`, disables release-on-close, sets level 23, clears opacity and background, keeps the panel visible while the app deactivates, disables ordinary window movement, and enables automatic key-view-loop recalculation. Its `collectionBehavior` getter returns raw value `0x14a`: `moveToActiveSpace`, `transient`, `ignoresCycle`, and `fullScreenAuxiliary`. The panel reports that it can become key and main. `acceptsFirstResponder` and `becomeFirstResponder` defer to `NSPanel` except while Spotlight marks the invocation as gesture-driven, when both return false. These panel and theme-frame choices are part of the animation surface contract, not incidental window chrome.

`SPApplication` pairs its `_stealKeyFocusWithOptions:` override at `0x10000cb74` with `_releaseKeyFocus` at `0x10000cb00`. The acquisition half maintains a process-wide claim count. On the first claim it calls `CPSModifyConnectionNotifications`, installs a read-only annotated-session `CGEventTap` with event mask `0x200000a` (left, right, and other mouse-down), adds the tap's Mach-port source to the run loop, then forwards `options | 0x800` to AppKit's implementation. A successful AppKit claim increments the count. The release override calls the superclass implementation, decrements the count after success, and tears down Spotlight's keyboard-focus-theft event state when the final claim is released. The ordinary animated dismissal's completion reaches `-[SPAppDelegate dismissSpotlightWindowController:immediatelyWithReason:]` at `0x10000b754`; that method calls `window.orderOut:` at `0x10000b804` and only then conditionally calls `NSApplication.hide:` at `0x10000b888`. `SPApplication.sendEvent:` also drains any outstanding claims before deactivation when WindowServer reports that Spotlight lost activation. Runtime probing confirms that loading Spotlight before requesting `sharedApplication` returns `SPApplication` as the process `NSApp`; Cornerlight now uses that singleton directly rather than reimplementing any part of this focus lifecycle.

Spotlight also asks WindowServer to set the connection property `SetsCursorInBackground`: immediately after panel configuration, `SPSpotlightPanel.configureAppearanceAndBehavior` calls `CGSMainConnectionID`, then `CGSSetConnectionProperty(connection, connection, @"SetsCursorInBackground", kCFBooleanTrue)`. Cornerlight mirrors that call. It changes cursor/event routing for the nonactivating key-focus panel but does not move or warp the pointer. Omitting it caused the first movement away from the Hot Corner to reach Spotlight's global `mouseMoved` focus-loss monitor and dismiss Cornerlight immediately.

The Applications hot-corner path calls the main-window invocation with `resetPosition = false`, which sets the panel's `shouldCenter` flag to false. When the user has not moved Spotlight, `SPSpotlightPanel.defaultPositionOriginForWindowSize:screen:` computes the Applications origin without integral rounding:

```text
x = screen.frame.origin.x + (screen.frame.width - window.width) / 2
y = screen.frame.origin.y + (screen.frame.height - 576) / 2 + 576 - window.height
```

For the 844 × 576 Applications platter, this is the exact center of the chosen screen's full frame. When `userHasMovedWindow` is true, however, `constrainFrameRect:toScreen:` restores `lastWindowPosition` from the `com.apple.Spotlight` preferences. `MainWindowController.adjustedRectForCurrentPlatterBehaviorFromStandardRect:` widens that stored standard-platter rectangle around its horizontal center, while the same-screen recomputation preserves its top edge for the new height.

On the reference Mac, the stored standard rect is `{{832, 373.82278481012668}, {640, 577}}` and `userHasMovedWindow` is true. The Applications origin is therefore derived as:

```text
x = storedRect.midX - 844 / 2
y = storedRect.maxY - 576
```

This saved-position path accounts for the observed approximately 14-point vertical difference from the full-screen center. It is not a hard-coded offset.

The former hand-wired implementation used this value as a read-only initial reference. The current
implementation instantiates Spotlight's actual `SPAppDelegate`, `MainWindowController`, and
`SPSpotlightPanel` and accepts Spotlight's stock 844 × 576 geometry unchanged.
Every Hot Corner toggle calls the
loaded executable's `SPAppDelegate.launchAppsBrowsingWithCompletion:` directly, so the native
delegate itself performs `prepareForScreen:` and the app-browse invocation/dismissal decision.

That entry point begins by reading `ignoreDockAppsLaunch`. When the flag is set, Spotlight clears it
and returns without opening. Native Spotlight uses the bit to consume Dock's paired launch message;
its animated-dismissal completion at `0x10000b69c` normally clears it after `orderOut:`. Cornerlight's
trigger is a separately edge-gated WindowServer region event, so its adapter clears the Dock-only bit
immediately before entering the native method. Otherwise an outside-click dismissal path can consume
the next genuine corner entry and make reopening require two trips.

The same adapter serializes calls at the native completion boundary. A WindowServer region can emit a
new genuine entry while Spotlight's roughly 0.7-second transition remains in flight; directly
re-entering `launchAppsBrowsingWithCompletion:` can replace an active reasoned-dismissal completion
before `SPApplication` drains its focus claim. Cornerlight parity-queues those entries and invokes the real
method again only after its completion returns. There is no time-based debounce and no Cornerlight-owned
focus release.

Panel drag alignment is also native rather than a hand-written distance check. `SPSpotlightPanel.sendEvent:` lazily creates `NSAlignmentFeedbackFilter`, forwards every event selected by `+[NSAlignmentFeedbackFilter inputEventMask]`, and the drag path requests horizontal or vertical alignment tokens from that filter. A returned token is passed to `performFeedback:performanceTime:` with performance time zero; `xSnap = 25` and `ySnap = 15` are the release thresholds after alignment has engaged.

The small lighter shapes outside the nominal rounded silhouette in the reference are therefore native glass edge/refraction pixels, not opaque corner fills to reproduce manually.

## Invocation animation

Spotlight's Applications invocation calls `makeKeyAndOrderFront`, selects the search text, and then passes `contentViewController.view.layer` to its window-animation coordinator. The controller root is a transparent `MainView`. It contains an `NSHostingView<MainWindowView>`, which in turn owns the native visual-effect/glass content. `MainView.setFrame:` deliberately substitutes its superview's frame before calling `NSView.setFrame:`. Animating this controller root is significant because it lets Core Animation composite and magnify the completed glass subtree as one surface instead of asking `NSGlassView` to transform its own backdrop layer.

The comparison recording `Untitled 2.mov` exposed why matching only the root class and spring constants was insufficient. Cornerlight's earlier `borderless + fullSizeContentView` panel held a fixed 844-point perimeter while the 1.12× controller-root contents enlarged and clipped inside it. In native Spotlight, the perimeter itself follows the root presentation transform. The mismatch came from Cornerlight's panel/theme-frame construction, not from a different spring curve.

The coordinator prepares the controller-root layer inside a `CATransaction` in a significant order: it first reads the layer's `frame`, then assigns anchor point `(0.5, 0.5)`, reads that anchor point back, and assigns the model transform `CATransform3DMakeTranslation(frame.width × anchor.x, frame.height × anchor.y, 0)`. Reading the frame before changing the anchor preserves the original AppKit root-layer geometry and compensates the move from its `(0, 0)` pivot to the platter center. It reads `WindowAnimationCoordinator.isVerticallyCollapsed` to select the transform variant. Applications browse is expanded, so it opens one outer `CATransaction`, removes the layer animation named `dismissal`, and adds this explicit group under the name `invocation`:

Spotlight's SwiftUI-hosted controller root retains that prepared anchor and translation while the group runs. A directly layer-backed AppKit `NSView` does not, which explained the earlier top-left animation regression in the former extracted implementation. The current native host invokes Spotlight's actual coordinator and carries no substitute animation code.

- `transform.scale.x`: 1.12 to 1.0, 0.28-second perceptual spring, 0.32 bounce
- `transform.scale.y`: 1.12 to 1.0, 0.28-second perceptual spring, 0.32 bounce
- `alphaValue`: 0 to 1, 0.28-second perceptual spring, 0.41 bounce

Before beginning those animations, the coordinator acquires an animation assertion. The transition from zero assertions to one obtains `SearchConstants.animationWindowPadding`, which is exactly 40 points on every edge, and sends it to the coordinator delegate. `MainWindowController` forwards that padding to `SPSpotlightPanel.setWindowPadding:`. The panel expands its transparent frame around the settled unpadded platter while the hosted glass content remains inset at its configured geometry—844 × 576 at the default 7 × 5 size. This gives the magnified presentation layer room to extend around its center instead of clipping inside the final window bounds. When the last animation assertion is released, the delegate restores zero padding and the transparent panel frame contracts around the visually unchanged settled glass.

Inside the same outer transaction, the coordinator installs a `CASpringAnimation(perceptualDuration: 0.28, bounce: 0.41)` in the panel's `animations` dictionary under `alphaValue`, sets the panel's `alphaValue` and private content-blur radius to zero, and assigns `animator().alphaValue = 1` inside `NSAnimationContext.runAnimationGroup`. The spring object itself does not receive manual `keyPath`, `fromValue`, or `toValue` assignments; AppKit supplies the property transition. The coordinator does not override the animation context's duration. It enters one `DispatchGroup` for the outer Core Animation transaction and one for the AppKit alpha animation, then runs the invocation completion on the main queue only after both have left. The apparent large, soft, translucent starting state comes from scaling that composited glass subtree while the panel fades in; Spotlight does not animate an additional invocation blur radius. The default settled platter remains 844 × 576 points, and Reduce Motion bypasses both springs.

The native 60 fps recording `Untitled.mov` independently validates that interpretation. Its first captured frame is already partway through the spring: the measured platter width is about 1.071× its settled width, then progresses through approximately 1.055, 1.042, 1.025, 1.012, and 1.000 before a small undershoot near 0.986 and the final rebound. Relative to the fully visible empty-glass state, the panel alpha is approximately 0.28 in the first captured frame, 0.70 one frame later, and visually saturated by the third frame. There is no separately observable invocation blur ramp; the softness follows the magnified composited surface and low alpha.

The same recording also distinguishes invocation from data loading. It contains Spotlight's live `Indexing…` status row from the first visible frame; that transient row expands the recorded platter beyond the idle 844 × 576 frame. The idle 11:25 reference screenshot confirms the standard platter remains exactly 844 × 576, and `SearchConstants.windowPadding` is `NSDirectionalEdgeInsetsZero`. Categories and application labels appear around 0.15 seconds, while app icons do not begin appearing until about 0.267 seconds. Those later changes belong to Spotlight's indexing and image-loading pipeline, not `WindowAnimationCoordinator`, and Cornerlight deliberately does not introduce equivalent artificial latency.

Runtime metadata and the executable decompile identify that row as `SPSpotlightIndexingView`, stored in `SpotlightAppMacOS.SearchNavigationBar.indexingView`. `setEligibleToView:` stores the eligibility byte and immediately calls `updateVisibility`. The latter hides the view whenever progress is complete; while progress is below one, it assigns `isHidden = !eligibleToView`. Spotlight's result-platter sizing path can set eligibility again as content changes, so a one-time hide is not durable. Cornerlight clamps the native view's `setEligibleToView:` input to `false` in its own process; the original setter and `updateVisibility` still perform the actual state and layout update. This removes metadata-index status from the enumerated launcher without creating a substitute view or touching stock Spotlight's separate process.

## Search field and insertion point

Spotlight's `SearchField` is an `NSSearchField`, and its `SearchFieldCell` is an `NSSearchFieldCell`. The cell owns and returns one persistent `DeleteHandlingTextView` field editor rather than using the window's shared editor. Its recovered contract includes:

- `searchTextRectForBounds:` returns the supplied bounds unchanged.
- `cancelButtonRectForBounds:` returns zero, and the search button cell is transparent.
- The editor is a field editor, allows undo and vibrancy, enables incremental search, and disables smart quotes and continuous spell checking. Its `typingAttributes` getter constructs a dictionary containing `NSFont.preferredFont(forTextStyle: .largeTitle)`, semantic `labelColor`, and a mutable copy of the default paragraph style with default tightening disabled; its setter is a no-op.
- Both the search field and its persistent editor report `clipsToBounds = false`; the setter is intentionally a no-op. The cell reports `wantsNotificationForMarkedText = true`.
- The cell rebuilds its placeholder as an attributed string using semantic `placeholderTextColor` and otherwise leaves AppKit responsible for rendering the text and insertion point.
- The editor caches and restores the default `insertionPointColor`; Spotlight does not replace it with a fixed color or custom caret renderer.

`SearchFieldCell.initTextCell:` obtains that persistent editor by sending the inherited `+[NSTextView fieldEditor]` factory to the `DeleteHandlingTextView` class. This detail is functional: directly constructing `NSTextView(frame:textContainer:nil)` leaves the editor without the text system AppKit expects and therefore without the native insertion point. Cornerlight now uses the same class factory; a local runtime check returns a `LauncherFieldEditor` with a live `NSTextContainer` and `System textInsertionPointColor`.

On macOS 26.6, that untouched AppKit value is the semantic `System textInsertionPointColor`. The blue caret, its native thickness, blink, and slight fade therefore come from `NSTextView`, not a Spotlight-specific animation.

The reference raster places the interior one point below the outer platter edge. At 2× scale, its separators occupy pixel rows 114–115, 204–205, and 438–439. The native 56-point header and 44-point category strip produce the first two positions. The third is SearchUI's one-point supplementary section boundary between the suggestion and alphabetic catalog sections; because both sections share the lower collection controller, that boundary scrolls with them.

## Query-filter tokens

The `QueryFilterToken.body` witness is at `0x10008655c` and resolves through `0x100085e34`; its button-label closure is `0x100087e7c`. The closure constructs the filter title with these exact SwiftUI operations:

- `Text(filterTitle).font(.title3)`
- `.padding(.vertical, 1)`
- `.padding(.horizontal, 8)`

On this macOS build, AppKit's corresponding preferred `.title3` font is 15-point SF regular. `QueryFilterButtonStyle.makeBody` is at `0x100083fb4` through `0x100083808`, with its material builder at `0x100083c30`. The exact material states are:

- pressed, or selected and focused: `SpotlightUIShared.SelectionMaterialView()`;
- selected but unfocused: `Rectangle().searchUIAppearance(TLKProminence(rawValue: 3))`;
- idle: `Rectangle().searchUIAppearance(TLKProminence(rawValue: 4))` under a forced dark color scheme.

The composed label uses `PlainButtonStyle`, clips the material with a continuous `RoundedRectangle` of literal radius `9.0`, applies `HierarchicalShapeStyle.secondary`, and forces the outer color scheme dark only for the active selection-material state. The token then applies `.focusable(false)`.

`SelectionMaterialView.makeNSView` is exported from `SpotlightUIShared` at `0x27144cc90`. The exact instruction stream sends `setMaterial:` with raw value 4 (`selection`), `setEmphasized:` with `true`, and `setState:` with raw value 1 (`active`) to a new `NSVisualEffectView`; it does not send `setBlendingMode:`, so the view retains the default raw value 0 (`behindWindow`). The current native host does not import or reconstruct this SwiftUI island; Spotlight's actual `QueryFilterBarView` owns it. Cornerlight intentionally supplies no category model, so the bar remains hidden.

`QueryFilterBarView`'s result-section observer is at `0x10007de00`. When its `sections` collection is empty it sets the hosting view's alpha to zero immediately. When at least one section exists, it calls `NSAnimationContext.runAnimationGroup`; the closure at `0x1000829b4` sets duration to the exact double `0.2`, enables `allowsImplicitAnimation`, and sets the hosted view's alpha to one. This is an ordinary implicit AppKit alpha transition, not a guessed spring.

## Application grid

The smallest recovered data boundary is `ATXAppIdentity`. Runtime probing confirms `initWithBundleURL:` accepts Cornerlight's enumerated bundle URL directly. `+[SPUISAppBrowseSectionBuilder appSectionWithTitle:identifier:style:appIdentities:]` then returns an `SFMutableResultSection`, and `SearchUIDataSourceSnapshotBuilder.buildSnapshotFromResultSections:queryId:` returns SearchUI's native diffable snapshot. No indexed Spotlight query is needed at this boundary.

`AppZKWQueryDataSource` maps Grid catalog sections to style `0`, Grid predicted/grouped sections to style `1`, and List sections to style `3`. Cornerlight uses styles `0` and `1` only when adapting enumerated and suggested identities. It does not subclass the results controller or implement application execution; the actual Spotlight controller owns both.

Spotlight's lower `SearchResultsViewController` owns SearchUI's `SearchUIPassthroughScrollView`, `SearchUICollectionView`, and `SearchUICollectionViewLayout`. For Applications browse, the style-1 suggestion section and style-0 catalog section are consecutive sections in this one controller, so the recent row, its native boundary, and every catalog row scroll together. Both source titles are empty: this suppresses SearchUI's supplementary text header. The decompiled `AppZKWQueryDataSource` builder call at `0x2713d9d50` identifies the suggestion section as `com.apple.spotlight.zkw.apps.suggestions`; the alphabetic catalog path at `0x2713da83c` identifies the catalog as `com.apple.spotlight.zkw.alphabetic`. SearchUI recognizes those identifiers as browse sections and inserts its one-point `_TtGC8SearchUI24SupplementaryHostingViewVS_9Separator_` boundary between them. Substitute identifiers can still produce two scrolling grid sections, but they omit that supplementary separator. The separate `SearchResultsAboveFiltersViewController` remains empty; routing suggestions there pins them above the scrolling catalog and does not match the launcher. Runtime probes and production-path tests observe `SearchUIVerticalLayoutCardSectionView` for Grid, `SearchUIDetailedRowCardSectionView` for List, and `SearchUIImageView` for icons. Spotlight tags every suggestion result with `sectionBundleIdentifier = "com.apple.spotlight.zkw"`; Cornerlight preserves that contract and supplies no custom heading, separator, scroll view, layout constants, or tile view.

`SearchUIGridSectionModel` exposes the native `numberOfColumns` property and setter. Both Spotlight app-browse sections produce that model with seven columns. An offscreen runtime probe of the stock 844-point platter measures 20-point horizontal content insets, seven approximately 115-point cells, 115 × 92-point item frames, and a 102-point vertical row stride. SearchUI exposes no corresponding row-count property for these sections: the number of visible rows is determined by the platter viewport height.

Cornerlight does not modify `numberOfColumns`, the platter transforms, the SwiftUI host frame, or `SPSpotlightPanel`'s content-size proposals. Spotlight owns the stock seven-column, 844 × 576 Applications layout end to end.

The system suggestion identities come from `SpotlightUIShared.AppZKWQueryDataSource`, which calls `ATXAppDirectoryClient.predictedAppsAndRecentAppsWithMaxNumberOfPredictedApps:shouldUseDefaultCategories:reply:` with a maximum of seven and default categories enabled. Predictions come first; recent identifiers are a deduplicated fallback. Cornerlight places its own event-driven MRU bundle identifiers before that system fallback, intersects the merged identifiers with its enumerated catalog, and passes at most seven identities into the same native style-1 section. The MRU observer consumes `NSWorkspace.didActivateApplicationNotification`; it does not poll `NSWorkspace.runningApplications`.

SearchUI's `SearchUIImageView.updateWithImage:fallbackImage:needsOverlayButton:animateTransition:` is at `0x1c1d42e60`. Once SearchUI converts its source image to `TLKImage`, the nonanimated branch sends `setTlkImage:` and the animated branch sends `animateTransitionToImage:` to the inherited `TLKImageView`. The native section builder and collection controller own this complete main-icon/reuse/transition path.

Runtime inspection also confirms that `SearchUIImageView` inherits `TLKImageView.badgeImageView`. Assigning a `TLKImage` through the source image's `badgeImage` property and reapplying that source makes TLK construct a native `SearchUIImageView` badge at 16 × 16 points in the upper-right corner of a 75-point app icon. Cornerlight uses this existing path for pin state; it does not add an AppKit overlay or choose badge geometry.

`SearchUICollectionViewController` exposes `collectionView:canDragItemsAtIndexPaths:withEvent:` at SearchUI image offset `0x125a8`, and `SearchUICollectionView` has native mouse selection and drag handling. Runtime testing established that its private drag session consumes the subsequent pointer stream but does not accept Cornerlight's pinned-item type as a local reorder destination. Cornerlight therefore leaves the native collection, layout, items, selection, and icon views in place while narrowly suppressing that drag-source callback for Cornerlight's hosted collection. After SearchUI performs its native mouse-down selection, a mouse-only local monitor follows the drag and mouse-up for pinned suggestion tiles. It reads the actual SearchUI item frames, snapshots the selected native `SearchUIImageView` for the cursor-attached preview, displays a two-point system-accent insertion marker, persists the reordered pin paths, and consumes mouse-up only when an order actually changed. Recent tiles cannot enter this path. There is no pasteboard writer, drop delegate, global event monitor, keyboard capture, polling loop, replacement row, or replacement cell.

Spotlight's `SearchField.control:textView:doCommandBySelector:` is at `0x10003d530`. It compares the command selector with `cancelOperation:` and routes that command through its search-field delegate. Cornerlight now hosts that actual field and delegate path rather than implementing either.

The concrete `SearchField.textDidChange:` implementation is at image offset `0x3f3f4`. It is direct `NSText` field-editor delegate traffic and does not depend on Spotlight delivering an indexed result section. Cornerlight observes AppKit's public `NSText.didChangeNotification`, filtered to that native search field or its current field editor, to run its in-memory filter; no Spotlight search-field method is replaced. `SearchResultsViewController.setSections:` remains a separate output firewall: any indexed proposal is replaced with the current enumerated sections and never acts as a query-change signal.

`DeleteHandlingTextView.respondsToSelector:` deliberately reports false for `insertNewline:`, `moveDown:`, `quickLookPreviewItems:`, and `insertNewlineIgnoringFieldEditor:` so those commands reach the responder chain. It handles copy only with a nonempty selection, handles left/up only when the caret can move, handles right only before the end of the text, and otherwise forwards. Tab and Backtab try the next responder before falling back to `NSTextView`. `MainWindowController` implements Return, all four arrows, Tab, and Backtab. Cornerlight hosts both actual native classes and adds no competing key-command path.

Runtime inspection of Spotlight's `SearchFieldCell.initTextCell:` shows a borderless cell with `drawsBackground == false`. The decompiled initializer at `0x10003b508` reads the persistent editor's `typingAttributes`, replaces only its foreground color with `placeholderTextColor`, and uses the resulting dictionary for the attributed placeholder. The editor getter at `0x100039768` builds that dictionary through `0x100045cf4`: `.SFNS-Regular` at exactly 26 points via the large-title text style, `labelColor`, and the non-tightening paragraph style. These attributes also provide AppKit's empty-field insertion-point line fragment; overriding only `NSTextView.font` leaves the caret at its 12/13-point fallback height.

`MainWindowController.invokeSpotlightWithResetPosition:reason:animated:completion:` calls `makeKeyAndOrderFront:` and immediately follows it with `SearchViewController.selectAll:`. The recovered `MainWindowController` method table has no `windowDidBecomeKey:` or `windowDidResignKey:` implementation. Cornerlight does not call this method itself: the loaded executable's actual `SPAppDelegate.launchAppsBrowsingWithCompletion:` selects it with app-browse reason `0x24`, or enters its native dismissal branch when that controller is already invoked.

The same invocation method stores a global `NSEvent` monitor with mask `0x20` (`mouseMoved`). The block thunk at `0x10003097c` calls its captured function at `0x10003542c`; that function weak-loads `MainWindowController` and directly dispatches `applicationLostFocus` with no debounce or time guard. At `0x100034540`, `MainWindowController.applicationLostFocus` unconditionally calls its weak delegate's `dismissSpotlightWindowController:withReason:completion:` with reason `15` and a nil caller completion. Cornerlight therefore forwards this callback even if `spotlightIsVisible` has already changed, and treats Spotlight's later `SPSpotlightPanel.orderOut:` lifecycle as the completion boundary for transition serialization. Dismissal removes the monitor again. Focus cancellation otherwise comes through the actual `SPApplication.sendEvent:` and its counted key-focus event tap, not invented window-key delegate callbacks.

Spotlight treats failure to install its annotated-session event tap as a focus-setup failure because the tap is a required member of its counted key-focus lease. Since the real `SPApplication` runs under Cornerlight's third-party identity, Cornerlight preflights Input Monitoring before presentation; denial shows a native explanation and the exact macOS 26.6 `Privacy_ListenEvent` settings link instead of asking the native class to create a denied tap.

`SPApplication.sendEvent:` handles WindowServer activation event type `0x15`, subtype `2`, by comparing the event ASN with the current application ASN. A foreign ASN calls its delegate's `dismissSpotlightWithReason:completion:`, drains every successful key-focus claim through `_releaseKeyFocus`, and deactivates `NSApp`. The supplied completion is asynchronous: Cornerlight must forward it into the hosted `SPAppDelegate.dismissSpotlightWithReason:completion:` and return it only after Spotlight's close finishes. Completing it when the animation merely starts creates a rapid-open/close race in which a later native acquisition outlives the panel. AppKit event type `0x0d`, subtype `2`, calls the delegate's `applicationLostFocus`. Cornerlight exposes those exact two selectors to its presentation coordinator and otherwise leaves this recovered method unchanged. No previous frontmost application is remembered or reactivated. Cornerlight observes only `SPSpotlightPanel.orderOut:` to release its enumerated section snapshot after native dismissal.

`SPSpotlightMenuItem.init` registers `_toggle` with `NSDistributedNotificationCenter` for `com.apple.spotlight.toggle` using suspension behavior `4` (`deliverImmediately`). In Apple's single Spotlight process this is the Dock/shortcut invocation route. A second hosted menu item would receive the same broadcast and enter its private delegate without passing through Cornerlight's Hot Corner coordinator, which can nest two processes' WindowServer key-focus claims during side-by-side testing. Cornerlight removes only that inherited observer. Its passive replacement drains `_releaseKeyFocus` to failure and deactivates before beginning the native close if stock Spotlight is invoked while Cornerlight is visible or transitioning. This reduces accidental overlap but cannot control a focus lease already owned by Apple's separate Spotlight process; rapid concurrent testing remains unsupported. The adjacent `com.apple.spotlight.invoked` string is not an arbitration notification: `_toggle:menu:` passes it to `BMDiscoverabilitySignalEvent` as an asynchronous discoverability signal.

## View-options menu

`SpotlightAppMacOS.ViewOptionsMenu` creates localized `Grid` and `List` menu items and, when the query capabilities include it, `Show iPhone Apps`. The recovered comments identify the first two as result display styles and the third as inclusion of iPhone Mirroring apps. There is no `Spotlight Settings…` item in this menu. The current native host uses Spotlight's real options control and does not construct or alter its menu.

## Reference material

- Local full-screen and exact 844 × 576-point panel captures were used during comparison but are not distributed.
