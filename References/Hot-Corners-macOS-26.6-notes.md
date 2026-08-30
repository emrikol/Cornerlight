# macOS 26.6 Hot Corners reference

The shipped Dock binary implements Hot Corners with a dedicated WindowServer connection rather than an AppKit window or a global mouse monitor.

Its relevant path is:

1. `CGSNewConnection`
2. `CGSGetEventPort`
3. An `MSHCreateMachServerSource` run-loop source for that Mach receive port
4. `CGSNewRegionWithRectList`
5. `CGSSetBackgroundEventMaskAndShape(connection, 0x302, region)`
6. Drain `CGEventCreateNextEvent(connection)` until it returns nil when the source callback runs

The run-loop source must consume the Mach message before the CGEvent queue is drained. A
`DispatchSourceMachReceive` only signals that the port is readable; it does not receive the
message. Using one directly therefore leaves the port permanently readable and starves AppKit's
main run loop. Cornerlight uses `CFMachPortCreateWithPort`, the Core Foundation equivalent of Dock's
Mach-server run-loop source, then performs Dock's complete event-drain loop in its callback.

Event type 8 enters the region and type 9 exits it. Dock's top-left candidate for a display with Quartz bounds `bounds` is:

```text
(bounds.minX - 1, bounds.minY - 1, 3, 3)
```

Cornerlight uses the same event-state boundary rather than a time debounce: one type-8 entry is accepted, repeated entries are ignored, and the gate rearms only after a type-9 exit whose event location is actually outside the region. A second genuine re-entry intentionally toggles an already visible launcher closed, matching Spotlight's Applications action.

Dock suppresses candidates shared by more than one usable display. It counts local displays returned by `CGGetDisplaysWithRect` for which `CGSDisplayStatusQuery(display, 9) == 0`; it also counts adjacent Universal Control display rectangles. Cornerlight reproduces the local-display rule and omits Dock's process-internal Universal Control helper.

The APIs above are private SkyLight SPI. Testing on macOS 26.6 confirmed an ordinary accessory application can create the connection, register the background region, and receive enter/exit events without injection, entitlements, privacy permission, root access, or SIP changes.

Dock's native Hot Corner preference is a closed integer action switch. It has no URL, application path, bundle identifier, Shortcut, or third-party callback, so a system Hot Corner cannot be configured to open Cornerlight directly.
