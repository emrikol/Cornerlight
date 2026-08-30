# Cornerlight

<img src="Resources/AppIcon.png" width="128" alt="Cornerlight app icon">

Cornerlight is a tiny, index-free macOS application launcher. It enumerates application bundles from `/Applications`, `/System/Applications`, and `~/Applications`, then presents them through macOS 26.6 Spotlight's actual launcher UI.

**Your apps, directly.**

[Website](https://emrikol.github.io/Cornerlight/) · [Releases](https://github.com/emrikol/Cornerlight/releases)

## Architecture

Cornerlight has one product-specific boundary: the application inventory.

- `ApplicationCatalogService` scans the three application roots asynchronously once at startup. FSEvents coalesces recursive install, update, move, and removal changes into background rescans. Opening the launcher never starts a scan, and no polling or persistent index is used.
- `SpotlightNativeLauncherUI` loads the installed macOS 26.6 Spotlight executable into Cornerlight's process and instantiates Spotlight's real `MainWindowController`, `SPSpotlightPanel`, `SearchViewController`, `SearchField`, and `SearchResultsViewController`.
- Enumerated bundle URLs are converted to Spotlight's native `ATXAppIdentity` and `SPUISAppBrowseSectionBuilder` models. A narrow `setSections:` adapter keeps indexed Spotlight results from replacing that inventory.
- Persistent app pins lead Spotlight's native seven-slot suggestion row; recent apps fill the remaining slots. Spotlight supplies the cells, layout, and scrolling. Cornerlight adds a mouse-only pinned-item reorder path using SearchUI's actual item frames and icon view, then persists only the ordered bundle paths.
- Spotlight owns the stock 844 × 576 panel and seven-column grid, material, animation, search header, options menu, result collection, scrolling, selection, keyboard navigation, accessibility, dismissal, and app-launch command path.
- Cornerlight intentionally does not supply Spotlight's category model. The category strip stays hidden.
- A WindowServer region registers the selected three-point Hot Corner. It is event-driven; there is no pointer polling, cursor movement, or sensor window. The corresponding macOS Hot Corner must remain unassigned because Dock has no third-party action-provider mechanism.
- Launch at Login is optional and uses macOS `SMAppService.mainApp`; login launches remain quiet.
- Sparkle 2.9.6 provides signed in-app updates. Its controller is created only for a manual check or when automatic checks have been enabled; app discovery and search remain offline.

This is a personal macOS 26.6 implementation. It depends on private Apple classes and may require adjustment after an OS update. It does not inject into Dock, require root, or require disabling SIP.

## Build

Requires macOS 26.6 and Xcode 26.

```sh
./build.sh                         # build dist/Cornerlight.app without opening it
./build.sh --compile-only
./build.sh --install               # install without opening
./build.sh --run                   # explicit foreground launch
./build.sh --restart-background    # safe resident-app replacement
./build.sh --distribution          # Developer ID + hardened runtime release bundle
```

The build prefers the installed Apple Development identity so Input Monitoring remains associated with a stable designated requirement. It stages and signs a new bundle before replacing the installed one and refuses to overwrite a running executable.

Validated version tags produce signed and notarized ZIP and DMG artifacts plus a signed Sparkle appcast through GitHub Actions. See [RELEASE.md](RELEASE.md) for the release contract and one-time secret setup.

GitHub Pages is deployed from `docs/` after relevant `main` changes and after every successful Release workflow. The deploy resolves the current `Cornerlight.dmg` asset through GitHub's API, so the website's primary download always follows the newest published release without a source edit.

## Input Monitoring

Cornerlight mirrors the focus lease that Spotlight's nonactivating panel expects. A non-Apple binary needs Input Monitoring for the lease's mouse-only outside-click tap. Removing it would prevent Spotlight's search field from reliably acquiring and releasing focus. Cornerlight explains this before presentation and opens the exact System Settings pane.

## Known incompatibility

Cornerlight is intended to replace the stock Spotlight Applications launcher, not run concurrently with it. Rapidly alternating between both can nest two independent `SPApplication` WindowServer focus leases. macOS may then restore keyboard focus to a hidden launcher after either panel closes. Cornerlight prevents the stock distributed toggle from directly invoking its hosted menu item and attempts to yield outstanding native focus claims, but cross-process focus restoration remains outside its process boundary.

The corner selected in Cornerlight must be set to **None** (`—`) in **System Settings → Desktop & Dock → Hot Corners**. Cornerlight does not modify that system preference or replace an entry in Apple's action list; it registers the same kind of WindowServer corner region independently. Cornerlight Settings offers only corners that macOS currently reports as unassigned.

The tap requests no keyboard events. It observes mouse clicks only while the launcher is open and is removed after dismissal. A quiet `--background` start neither creates the tap nor prompts.

## Settings

Open Spotlight's overflow menu and choose **Settings…** to:

- enable or disable Launch at Login;
- enable or disable automatic update checks;
- choose an unassigned macOS Hot Corner;
- review and unhide hidden applications.

## Use

- First leave the selected corner unassigned in macOS Hot Corners, then choose it in Cornerlight Settings.
- Move the pointer into that exact corner.
- Type to filter the enumerated applications.
- Use Spotlight's native keyboard or pointer navigation.
- Right-click an app to pin or unpin it; drag pinned apps within the top row to reorder them.
- Choose **Check for Updates…** in the overflow menu to run a manual signed update check.
- Press Return or click an app to launch it.
- Press Escape, click elsewhere, or re-enter the corner to dismiss.

## Verify

The automated suite is headless: it does not order the launcher onscreen, activate Cornerlight, move the pointer, or synthesize input.

```sh
./verify.sh
```

An offscreen snapshot can exercise the native controller hierarchy without taking focus:

```sh
dist/Cornerlight.app/Contents/MacOS/Cornerlight --snapshot /tmp/cornerlight.png
```

The real Hot Corner, WindowServer glass, focus handoff, and launch command remain manual acceptance checks.

See [BUILD.md](BUILD.md), [TESTING.md](TESTING.md), [RELEASE.md](RELEASE.md), and [PRIVACY.md](PRIVACY.md) for the maintained workflows and project guarantees.

## License

Cornerlight is licensed under the [GNU General Public License v3.0](LICENSE). Bundled dependency and font notices are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Support policy

Cornerlight is provided as-is without support:

- Issues are disabled; bug reports and feature requests are not accepted.
- Pull requests are accepted only from explicitly added collaborators.
- Anyone else may fork and adapt the project under GPL-3.0.
- Redistributed modified versions should use a different name and branding to avoid confusion.

Cornerlight relies on private, version-pinned macOS implementation details. Supporting other macOS releases, hardware, or configurations is outside this personal project's scope.
