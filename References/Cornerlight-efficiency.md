# Cornerlight efficiency record

Measurements are kept separate from design claims. They must be repeated after installing the current signed bundle; no automated check may present the panel or take focus merely to collect a number.

## 2026-08-27 pre-native-host baseline

Command: `Tools/measure-efficiency.sh` against a release bundle built in a temporary output root with the stable Apple Development identity.

- Bundle size: 292 KiB
- Executable size: 290,064 bytes
- Headless native-hierarchy snapshot: 0.27 seconds
- Headless peak resident size: 145,768,448 bytes
- Snapshot framebuffer: 1,688 × 1,152 pixels (844 × 576 points at 2×)

These measurements describe the retired hand-wired prototype that was removed before the first public commit; they must not be presented as current native-host measurements. The peak resident value included process startup, private framework loading, catalog enumeration, SearchUI snapshot construction, icon work, and the full-resolution bitmap.

The already-running pre-deployment development build sampled at 0.0% CPU after 1:57:15 of uptime and 144,912 KiB RSS. That process predates the current native-results and cleanup changes, so it is evidence only that the hot-corner path is event-driven—not a final memory acceptance result.

## Structural efficiency checks

- Hot-corner delivery blocks on SkyLight/WindowServer events; there is no cursor polling timer or sensor window.
- `/Applications`, `/System/Applications`, and `$HOME/Applications` are scanned asynchronously once by the resident `ApplicationCatalogService` at startup. Coalesced FSEvents notifications request later rescans; opening the panel never scans.
- The small catalog and preference stores remain resident. The hosted Spotlight controller tree is constructed lazily once, then retained and reused so Spotlight's private ownership graph cannot accumulate across reopenings.
- Cornerlight contains no SwiftUI or hand-built launcher view; the loaded Spotlight controller owns its complete UI hierarchy.
- Native panel `orderOut:` is the dismissal boundary. Cornerlight clears injected sections and calls the native results controller's purge path while retaining the one native host for later reuse.

## 2026-08-29 native-host pre-unload sample

These are comparison samples from the installed debug process before on-demand host release was enabled. They are not the final post-dismissal floor.

- Cornerlight physical footprint: 84.7 MiB; peak: 416.4 MiB
- Stock Spotlight physical footprint: 147.5 MiB; peak: 606.4 MiB
- Five idle samples for both processes: 0.0% CPU and 0.0 power
- Cornerlight threads: 5; stock Spotlight threads: 6
- Compile-only release executable: 594 KiB with no third-party dynamic libraries

## 2026-08-29 on-demand host experiment (rejected)

An experimental stable-identity debug bundle was restarted in the background and sampled before its first panel invocation, so no hosted Spotlight controller tree had been constructed.

- Physical footprint: 79.7 MiB; peak during startup and catalog scan: 396.4 MiB
- Five idle samples: 0.0% CPU and 0.0 power
- Settled threads: 8

After three manual open/close cycles, the process footprint was 89.9 MiB with 0.0% idle CPU and power. Heap inspection found three retained `SPSpotlightPanel`, `MainWindowController`, and `SearchViewController` ownership graphs: releasing Cornerlight's wrapper does not dismantle Spotlight's private SwiftUI/AttributeGraph graph. A complete teardown would require brittle private-object surgery for roughly 5 MiB of cold-process savings. The experiment was rejected; Cornerlight retains and reuses one native host instead, preventing per-invocation accumulation and keeping reopen latency lower.

## Manual acceptance still required

After installing the current stable-signed bundle, sample the same PID with the panel never opened, while visible, and after dismissal/cache release. Record CPU and RSS with `Tools/measure-efficiency.sh BUNDLE PID`; also verify a second invocation does not increase the post-dismissal floor. This is intentionally manual because presenting a real glass panel solely for automation would interrupt the user and invalidate the no-focus test policy.

## 2026-08-29 final renamed-bundle cold sample

The stable Apple Development-signed `com.emrikol.Cornerlight` bundle was installed and started quietly with its panel never opened:

- Bundle size: 344 KiB
- Executable size: 343,904 bytes
- Resident size after 68 seconds: 66,176 KiB
- Idle CPU: 0.0%
- Headless native-hierarchy snapshot: 0.55 seconds
- Headless peak resident size: 200,228,864 bytes

Visible and post-dismissal readings remain owner-driven acceptance measurements because collecting them would present the launcher and take focus.
