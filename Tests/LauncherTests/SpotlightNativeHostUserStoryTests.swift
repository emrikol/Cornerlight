import AppKit
@testable import Cornerlight
import Testing

@Suite(.serialized)
// The suite audits one version-pinned native Spotlight ownership boundary.
// swiftlint:disable:next type_body_length
struct SpotlightNativeHostUserStoryTests {
    @Test @MainActor
    func `native app browse invocation is owned by Spotlights actual app delegate`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())

        #expect(NSStringFromClass(type(of: host.appDelegate)) == "SPAppDelegate")
        #expect(
            host.appDelegate.responds(
                to: NSSelectorFromString("launchAppsBrowsingWithCompletion:"),
            ),
        )
        #expect(host.appDelegate.responds(to: NSSelectorFromString("spotlightIsVisible")))
        #expect(host.appDelegate.responds(to: NSSelectorFromString("dismissSpotlight")))
        #expect(
            host.appDelegate.responds(
                to: NSSelectorFromString("dismissSpotlightWithReason:completion:"),
            ),
        )
        #expect(host.appDelegate.responds(to: NSSelectorFromString("applicationLostFocus")))
        let ownedController = try #require(
            host.appDelegate
                .perform(NSSelectorFromString("appBrowseWindowController"))?
                .takeUnretainedValue() as? NSWindowController,
        )
        #expect(ownedController === host.panel.windowController)
        #expect(!host.isPresented)
    }

    @Test @MainActor
    func `a WindowServer corner entry cannot be consumed by Spotlights Dock suppression flag`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        let setter = NSSelectorFromString("setIgnoreDockAppsLaunch:")
        let getter = NSSelectorFromString("ignoreDockAppsLaunch")
        typealias BoolSetter = @convention(c) (AnyObject, Selector, Bool) -> Void
        typealias BoolGetter = @convention(c) (AnyObject, Selector) -> Bool

        #expect(host.appDelegate.responds(to: setter))
        #expect(host.appDelegate.responds(to: getter))
        unsafeBitCast(host.appDelegate.method(for: setter), to: BoolSetter.self)(
            host.appDelegate,
            setter,
            true,
        )
        #expect(
            unsafeBitCast(host.appDelegate.method(for: getter), to: BoolGetter.self)(
                host.appDelegate,
                getter,
            ),
        )

        host.prepareForWindowServerInvocation()

        #expect(
            !unsafeBitCast(host.appDelegate.method(for: getter), to: BoolGetter.self)(
                host.appDelegate,
                getter,
            ),
        )
    }

    @Test @MainActor
    func `launch hosts Spotlights controller tree rather than a lookalike`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        let mainWindowController = try #require(host.panel.windowController)

        #expect(
            NSStringFromClass(type(of: host.viewController)) ==
                "SpotlightAppMacOS.SearchViewController",
        )
        #expect(
            NSStringFromClass(type(of: host.searchField)) ==
                "SpotlightAppMacOS.SearchField",
        )
        #expect(
            NSStringFromClass(type(of: host.panel)) == "SPSpotlightPanel",
        )
        #expect(
            NSStringFromClass(type(of: mainWindowController)) ==
                "SpotlightAppMacOS.MainWindowController",
        )
        #expect(
            mainWindowController.responds(
                to: NSSelectorFromString(
                    "invokeSpotlightWithResetPosition:reason:animated:completion:",
                ),
            ),
        )
        #expect(
            mainWindowController.responds(
                to: NSSelectorFromString("dismissSpotlightWithAnimated:completion:"),
            ),
        )
    }

    @Test @MainActor
    func `spotlights native search field remains the editable input surface`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())

        #expect(host.searchField.isEnabled)
        #expect(host.searchField.isEditable)
        #expect(host.searchField.isSelectable)
        #expect(host.searchField.placeholderString == "Applications")
    }

    @Test @MainActor
    func `enumerated inventory never exposes Spotlights indexing status`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        let indexingView = try #require(
            firstDescendant(named: "SPSpotlightIndexingView", in: host.view),
        )
        let setter = NSSelectorFromString("setEligibleToView:")
        let getter = NSSelectorFromString("eligibleToView")
        typealias BoolSetter = @convention(c) (AnyObject, Selector, Bool) -> Void
        typealias BoolGetter = @convention(c) (AnyObject, Selector) -> Bool

        #expect(indexingView.responds(to: setter))
        #expect(indexingView.responds(to: getter))
        unsafeBitCast(indexingView.method(for: setter), to: BoolSetter.self)(
            indexingView,
            setter,
            true,
        )

        #expect(
            !unsafeBitCast(indexingView.method(for: getter), to: BoolGetter.self)(
                indexingView,
                getter,
            ),
        )
        #expect(indexingView.isHidden)
    }

    @Test @MainActor
    func `native orderOut reports dismissal without a duplicate presentation state machine`() async throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        var dismissals = 0
        host.onNativeDismiss = { dismissals += 1 }

        host.panel.orderOut(nil)
        await drainMainQueue()

        #expect(dismissals == 1)
        #expect(!host.isPresented)
    }

    @Test @MainActor
    func `enumerated applications cross only Spotlights native result section boundary`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        let applications = [
            ApplicationRecord(
                name: "App Store",
                url: URL(fileURLWithPath: "/System/Applications/App Store.app"),
            ),
            ApplicationRecord(
                name: "Calculator",
                url: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
            ),
        ]

        host.update(
            suggestions: [],
            applications: applications,
        )
        host.onQueryChange = {
            Issue.record("Spotlight index proposals must not drive local filtering")
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        let resultsController = try #require(
            host.viewController
                .perform(NSSelectorFromString("resultsViewController"))?
                .takeUnretainedValue() as? NSObject,
        )
        let sections = try #require(
            resultsController
                .perform(NSSelectorFromString("sections"))?
                .takeUnretainedValue() as? NSArray,
        )

        #expect(NSStringFromClass(type(of: resultsController)) == "SpotlightAppMacOS.SearchResultsViewController")
        #expect(sections.count == 1)

        _ = resultsController.perform(
            NSSelectorFromString("setSections:"),
            with: NSArray(),
        )
        let restoredSections = try #require(
            resultsController
                .perform(NSSelectorFromString("sections"))?
                .takeUnretainedValue() as? NSArray,
        )
        #expect(restoredSections.count == 1)

        let queryFilterBar = try #require(
            firstDescendant(named: "SpotlightAppMacOS.QueryFilterBarView", in: host.view),
        )
        #expect(queryFilterBar.isHidden)
    }

    @Test @MainActor
    func `spotlights native overflow menu offers Show Hidden Apps`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        var observedStates: [Bool] = []
        var settingsOpenCount = 0
        host.onSetShowsHiddenApplications = { observedStates.append($0) }
        host.onOpenSettings = { settingsOpenCount += 1 }
        host.setShowsHiddenApplications(false)

        let menu = NSMenu()
        menu.addItem(withTitle: "Grid", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "List", action: nil, keyEquivalent: "")
        host.configureViewOptionsMenu(menu)
        let item = try #require(
            menu.items.first(where: {
                $0.identifier?.rawValue == "com.emrikol.Cornerlight.showHiddenApplications"
            }),
        )

        #expect(item.title == "Show Hidden Apps")
        #expect(item.state == .off)

        let updateSelector = NSSelectorFromString("update")
        let nativeMenuClass: AnyClass = try #require(
            NSClassFromString("_TtC17SpotlightAppMacOS15ViewOptionsMenu"),
        )
        let nativeUpdate = try #require(class_getInstanceMethod(nativeMenuClass, updateSelector))
        let appKitUpdate = try #require(class_getInstanceMethod(NSMenu.self, updateSelector))
        #expect(method_getImplementation(nativeUpdate) != method_getImplementation(appKitUpdate))

        _ = item.target?.perform(item.action, with: item)
        #expect(observedStates == [true])
        #expect(item.state == .on)

        host.configureViewOptionsMenu(menu)
        #expect(
            menu.items.count(where: {
                $0.identifier?.rawValue == "com.emrikol.Cornerlight.showHiddenApplications"
            }) == 1,
        )
        #expect(
            menu.items.count(where: {
                $0.identifier?.rawValue == "com.emrikol.Cornerlight.openSettings"
            }) == 1,
        )
        let settingsItem = try #require(
            menu.items.first(where: {
                $0.identifier?.rawValue == "com.emrikol.Cornerlight.openSettings"
            }),
        )
        _ = settingsItem.target?.perform(settingsItem.action, with: settingsItem)
        #expect(settingsOpenCount == 1)
    }

    @Test @MainActor
    func `spotlights native overflow menu offers Quit Cornerlight`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        var quitCount = 0
        host.onQuit = { quitCount += 1 }
        let menu = NSMenu()
        host.configureViewOptionsMenu(menu)
        let quitItem = try #require(menu.items.first {
            $0.identifier?.rawValue == "com.emrikol.Cornerlight.quit"
        })
        #expect(quitItem.title == "Quit Cornerlight")
        #expect(quitItem.keyEquivalent == "q")
        #expect(quitItem.keyEquivalentModifierMask == .command)
        _ = quitItem.target?.perform(quitItem.action, with: quitItem)
        #expect(quitCount == 1)

        host.configureViewOptionsMenu(menu)
        #expect(menu.items.count {
            $0.identifier?.rawValue == "com.emrikol.Cornerlight.quit"
        } == 1)
    }

    @Test @MainActor
    func `spotlights native overflow menu offers a manual update check`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        var updateCheckCount = 0
        host.onCheckForUpdates = { updateCheckCount += 1 }

        let menu = NSMenu()
        host.configureViewOptionsMenu(menu)
        let updateItem = try #require(
            menu.items.first(where: {
                $0.identifier?.rawValue == "com.emrikol.Cornerlight.checkForUpdates"
            }),
        )

        #expect(updateItem.title == "Check for Updates…")
        _ = updateItem.target?.perform(updateItem.action, with: updateItem)
        #expect(updateCheckCount == 1)
    }

    @Test @MainActor
    func `native application context menu survives controller replacement and toggles visibility`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        let application = ApplicationRecord(
            name: "Audio MIDI Setup",
            url: URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"),
        )
        var hiddenPaths = Set<String>()
        host.isApplicationHidden = {
            hiddenPaths.contains($0.standardizedFileURL.path)
        }
        host.onSetApplicationHidden = { url, hidden in
            if hidden {
                hiddenPaths.insert(url.standardizedFileURL.path)
            } else {
                hiddenPaths.remove(url.standardizedFileURL.path)
            }
        }
        host.update(suggestions: [], applications: [application])

        #expect(host.hasNativeApplicationContextMenuHook)
        let hideMenu = try nativeApplicationContextMenu(in: host)
        let hideItem = try #require(
            hideMenu.items.first(where: {
                $0.identifier?.rawValue == "com.emrikol.Cornerlight.toggleApplicationVisibility"
            }),
        )
        #expect(hideItem.title == "Hide This App")

        _ = hideItem.target?.perform(hideItem.action, with: hideItem)
        #expect(hiddenPaths == [application.url.standardizedFileURL.path])

        let unhideMenu = NSMenu()
        unhideMenu.addItem(withTitle: "Open", action: nil, keyEquivalent: "")
        host.addApplicationVisibilityItem(
            to: unhideMenu,
            applicationURL: application.url,
        )
        let unhideItem = try #require(
            unhideMenu.items.first(where: {
                $0.identifier?.rawValue == "com.emrikol.Cornerlight.toggleApplicationVisibility"
            }),
        )
        #expect(unhideItem.title == "Unhide This App")
    }

    @Test @MainActor
    func `spotlights native query update reaches only the inventory adapter`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        var observedQueries: [String] = []
        host.onQueryChange = { observedQueries.append(host.searchField.stringValue) }

        host.searchField.stringValue = "cal"
        NotificationCenter.default.post(
            name: NSText.didChangeNotification,
            object: NSSearchField(),
        )
        NotificationCenter.default.post(
            name: NSText.didChangeNotification,
            object: host.searchField,
        )

        #expect(observedQueries == ["cal"])
    }

    @MainActor
    private func firstDescendant(named name: String, in root: NSView) -> NSView? {
        if NSStringFromClass(type(of: root)) == name {
            return root
        }
        for subview in root.subviews {
            if let match = firstDescendant(named: name, in: subview) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
