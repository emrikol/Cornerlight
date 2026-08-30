---
name: Cornerlight
description: Native Spotlight host with a separate graphite, satin-silver, and amber website communication system.
colors:
  website-graphite-deep: "#07090a"
  website-graphite-panel: "#0c0f11"
  website-graphite-raised: "#14181b"
  website-satin-bright: "#f0f1ef"
  website-satin-primary: "#c2c6c7"
  website-satin-muted: "#858c91"
  website-satin-rule: "#454c51"
  website-rule-translucent: "rgba(210, 216, 218, 0.2)"
  website-amber-signal: "#eda43a"
typography:
  website-display:
    fontFamily: "Barlow Condensed, Arial Narrow, sans-serif"
    fontWeight: 600
  website-body:
    fontFamily: "-apple-system, BlinkMacSystemFont, SF Pro Text, sans-serif"
    fontSize: "16px"
    lineHeight: 1.5
  website-label:
    fontFamily: "SFMono-Regular, Consolas, monospace"
---

# Design: native Spotlight host

Cornerlight has no independent visual design system. The installed macOS 26.6 Spotlight launcher is the design system and the runtime implementation.

## Native ownership

The visible hierarchy must be the real Apple classes:

```text
SpotlightAppMacOS.MainWindowController
└── SPSpotlightPanel
    └── SpotlightAppMacOS.SearchViewController
        ├── SpotlightAppMacOS.SearchField
        └── SpotlightAppMacOS.SearchResultsViewController
```

Spotlight therefore owns saved placement, the stock 844 × 576 platter, its seven-column grid, border, glass, translucency, opening and closing animation, typography, caret, header controls, scrolling, selection, keyboard navigation, accessibility, and launch behavior. Cornerlight must not recreate or tune any of those.

## Inventory boundary

Cornerlight passes bundle URLs across one narrow adapter:

```text
ApplicationCatalog
  → ApplicationRecord
  → ATXAppIdentity
  → SPUISAppBrowseSectionBuilder
  → SearchResultsViewController.setSections:
```

AppKit's public `NSText` field-editor change notification from Spotlight's native search field reads search text and triggers in-memory filtering. Indexed section proposals are intercepted separately at `SearchResultsViewController.setSections:` and replaced by the current enumerated sections; they never drive the query.

Spotlight's `SearchNavigationBar` also owns an `SPSpotlightIndexingView` for metadata-index progress. Cornerlight marks that exact native view ineligible because its enumerated inventory is complete independently of Spotlight's metadata index. The native view continues to own its own visibility; Cornerlight adds no replacement loading or status surface.

An event-driven `NSWorkspace.didActivateApplicationNotification` observer stores a bounded MRU list of bundle identifiers. Persisted app pins lead the suggestion model in their chosen order; local recents and Spotlight's cached system suggestions fill the remaining slots, and every entry must exist in the enumerated inventory. They cross the same native section builder as style `1`, so Spotlight owns the seven-slot row's cells, layout, and scrolling. SearchUI's private drag session consumes the pointer stream but does not accept a Cornerlight-owned pinned reorder. Cornerlight therefore suppresses that session only for its hosted pinned tiles, then uses a mouse-only local monitor with SearchUI's actual item frames and selected icon view for the cursor-attached preview and insertion marker. It persists only a completed order change and never captures keyboard input or introduces a replacement row, cell, or collection. A pinned tile sets `TLKImage.badgeImage` and lets the inherited `SearchUIImageView` render its native 16-point corner badge; cell reuse clears only Cornerlight's own badge. Recent tiles cannot be reordered or dragged. Persistently hidden bundle paths are removed before both browse and query filtering unless the persisted Show Hidden Apps preference is enabled; hiding a pinned app does not erase its pin. The category model is intentionally absent, so Spotlight's category strip remains hidden.

## Platform glue

Cornerlight loads Spotlight before creating the process application and uses the actual `SPApplication` singleton as `NSApp`. Its original `_stealKeyFocusWithOptions:`, `_releaseKeyFocus`, and `sendEvent:` implementations therefore own the paired focus lease, outside-click event tap, release, and deactivation. Cornerlight exposes the two dismissal delegate selectors that `SPApplication.sendEvent:` calls. Its reasoned dismissal selector forwards the original completion into the real `SPAppDelegate` so `SPApplication` cannot release focus before Spotlight's asynchronous close finishes. Cornerlight does not keep a competing focus counter, event tap, deactivation path, or previous-application restoration target.

The selected corner uses WindowServer region events and a rearm-on-exit gate. The adapter never re-enters `SPAppDelegate.launchAppsBrowsingWithCompletion:` while Spotlight's previous transition is unfinished; rapid entries are reduced by toggle parity and replayed after the native completion. Every actual native invocation lends its transition token to Spotlight's dismissal lifecycle, so app launch, Escape, and click-outside can all finish the gate even when the native invocation completion is omitted. Reasoned WindowServer closes use Spotlight's completion block, while focus-loss closes finish at Spotlight's own `SPSpotlightPanel.orderOut:` lifecycle boundary. A dismissal that starts a queued reopen marks that exact cleanup boundary to retain its prepared sections; unrelated active transitions never suppress cleanup. This prevents an old close callback from emptying a new presentation without leaving native app-launch dismissals active forever. This gate uses no timer and never acquires or releases focus itself. A small AppKit Settings window lists only corners whose `com.apple.dock` action is unassigned, persists the selection, and falls back to another available corner if macOS later claims it. No cursor polling, cursor control, focus automation, or invisible sensor window is permitted.

The catalog service, directory monitor, recents, pins, hidden-app preferences, Hot Corner, and Settings controller belong to the resident app delegate. The hosted Spotlight controller tree is lazy and created on first invocation, then retained as one native ownership graph for later reopenings. Spotlight's private SwiftUI and AttributeGraph internals retain portions of that graph after wrapper release, so rebuilding it per invocation would accumulate native controllers instead of lowering the stable footprint. Cornerlight therefore reuses one host and refreshes it from the current in-memory catalog; reopening never rescans the filesystem.

## Rule

If a behavior belongs to Spotlight's visible launcher, call the native controller. Do not add a second implementation in Cornerlight.

## Website visual system

This section applies only to Cornerlight's public website. It documents the shipped communication layer and does not create an independent application UI or relax Spotlight's native ownership above.

**Creative North Star: "The Machined Boundary Plate"**

The website turns Cornerlight's narrow implementation boundary into a restrained technical artifact. A deep graphite field, satin-silver type and rules, and one amber transfer signal make the inventory-to-system handoff legible without imitating the product UI.

The world is precise, sparse, and nearly flat. Structure comes from alignment, seams, clipped corners, labels, and negative space rather than a collection of elevated containers.

**Key Characteristics:**

- Graphite field with satin-silver structure and one restrained amber signal.
- Condensed structural typography paired with calm system body text and compact monospaced labels.
- Machined, clipped-corner controls and plates with sparse rules instead of rounded card chrome.
- Image-native three-root convergence followed by an explicitly system-owned, abstract native handoff.
- Responsive topology that changes the diagram and information flow instead of merely shrinking them.

### Color and material

Graphite supplies the field and plate layers; satin silver carries readable type, conduits, borders, and quiet metadata. Amber is scarce and directional: it marks the transfer path, the primary action's edge, numbered installation cues, and small status points.

**The Amber Transfer Rule.** Amber indicates passage, activation, or a decisive next step; it does not become a broad decorative fill or a second background system.

Depth remains near-flat. Large plates may use one soft outer shadow and one restrained inner highlight, while ordinary sections are divided by single translucent rules. Avoid stacked shadows, glass-card piles, and decorative surface layering.

### Typography

Barlow Condensed is the structural voice for promises, section headings, control labels, and the wordmark. It is compact, usually uppercase, and uses abrupt scale changes to establish hierarchy. The system sans-serif stack carries readable paragraphs, and the system monospace stack identifies paths, stage labels, indices, and technical facts.

Structural display text stays dense and assertive; body copy stays calm, generously led, and short. Monospaced annotation remains subordinate and gains distinction through tracking and uppercase rather than size.

### Form and control language

Controls and system plates feel machined: tight geometry, one clipped top-right corner, fine satin borders, and minimal rounding. The shipped primary download control uses a 15-pixel cut; the large system plate uses a 23-pixel cut. Small rules, seams, and insertion-like amber edges define components more often than enclosing backgrounds do.

Primary actions can lift by two pixels and brighten their amber or silver edge on hover. Focus remains unmistakable through a two-pixel bright outline with a four-pixel offset. Secondary links stay typographic and reveal amber only at the underline.

### Imagery and native handoff

The signature visual is image-native and semantically reinforced in HTML: exactly three application roots converge into one narrow Cornerlight inventory stage, then one amber projection crosses into a restrained system-owned destination. Desktop artwork carries the convergence horizontally; mobile artwork reorients the same meaning vertically.

**The Native Restraint Rule.** The destination may suggest native macOS territory, but it remains an abstract diagram labeled as system-owned—never a fabricated Spotlight screenshot, invented result list, or alternate native interface.

### Layout and responsive topology

The website uses a wide centered field capped at 1540 pixels, with 24-pixel side gutters on larger viewports and 14-pixel gutters on compact screens. Sparse rules, aligned baselines, and generous negative space hold the system together.

Wide multi-column structures collapse at 1180 pixels. At 760 pixels and below, content becomes a single reading flow, auxiliary navigation recedes, actions stretch to the available width, and the handoff swaps to its purpose-built vertical asset. Supporting grids flatten rather than compressing into illegible miniatures.

**The Topology Rule.** Preserve sequence and meaning across breakpoints by changing structure and artwork orientation; do not scale a desktop diagram down until its labels fail.

### Motion and reduced motion

Motion explains state or reinforces the handoff. The shipped system artwork enters once through a restrained 900-millisecond opacity-and-scale reveal using a fast-settling custom ease after a short delay; interactive edges, borders, and two-pixel lifts settle in 160 milliseconds.

**The Completed-State Rule.** With Reduced Motion enabled, remove smooth scrolling and collapse animation and transition durations to effectively immediate while rendering the handoff in its complete, fully opaque state.

### Website do's and don'ts

#### Do

- **Do** reserve amber for transfer, activation, primary action emphasis, and small status signals.
- **Do** use sparse satin rules, alignment, and negative space to separate information.
- **Do** preserve the three-root convergence and the restrained native handoff in every responsive orientation.
- **Do** keep the website system explicitly separate from Spotlight's runtime-native ownership.

#### Don't

- **Don't** turn the page into a feature-card grid or a mosaic of interchangeable rounded panels.
- **Don't** use fake native screenshots, invented launcher contents, or a website-built Spotlight lookalike.
- **Don't** promote a route-specific first-viewport composition into the global website system; that composition belongs in its surface brief.
- **Don't** spread amber across large surfaces or add ornamental glow that obscures the boundary story.
