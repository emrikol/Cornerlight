# Privacy

Cornerlight is a local, personal utility.

- It enumerates application bundles only in `/Applications`, `/System/Applications`, and `~/Applications`.
- It stores the selected Hot Corner, hidden app paths, pinned app paths, a bounded recent-app identifier list, and the Show Hidden Apps preference in local macOS preferences.
- It makes no network requests during app discovery, search, launch, or idle operation.
- If automatic update checks are enabled or **Check for Updates…** is selected, Sparkle requests Cornerlight's signed release feed and update archive from GitHub. GitHub receives the connection metadata inherent to that request. Cornerlight sends no analytics, telemetry, advertising identifiers, account data, app inventory, queries, or usage history.
- It does not read document contents or maintain a Spotlight-style metadata index.
- It does not monitor system-wide keystrokes.

Input Monitoring is required only because Spotlight's native nonactivating panel uses a mouse-only event tap to detect clicks outside the launcher and release keyboard focus. That tap exists only while the launcher is open.

Launch at Login is optional and uses `SMAppService.mainApp`.

Automatic update checks are optional, disabled by default, and managed by Sparkle 2.9.6.
