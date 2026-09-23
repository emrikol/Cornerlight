import AppKit
@testable import Cornerlight
import Testing

// swiftlint:disable file_length

@Suite(.serialized)
// The suite audits one version-pinned native Spotlight ownership boundary.
// swiftlint:disable:next type_body_length
struct SpotlightNativeHostUserStoryTests {
    @Test
    func `enhanced Siri dismissal keeps the split results snapshot sized`() {
        #expect(
            !SpotlightNativeDismissedContentPolicy.clearsNativeSnapshot(
                usesEnhancedSiri: true,
            ),
        )
        #expect(
            SpotlightNativeDismissedContentPolicy.clearsNativeSnapshot(
                usesEnhancedSiri: false,
            ),
        )
    }

    @Test @MainActor
    // swiftlint:disable:next function_body_length
    func `native app browse invocation is owned by Spotlights actual runtime graph`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())

        if SpotlightExecutableRuntime.generation == .spotlightUIInternal {
            let usesEnhancedSiri = SpotlightExecutableRuntime.usesEnhancedSiri
            #expect(NSStringFromClass(type(of: host.appDelegate)) == (usesEnhancedSiri
                    ? "Siri_AI.AppDelegate"
                    : "SpotlightAppMacOS.AppDelegate"))
            let manager = try #require(
                nativeObjectIvar(
                    named: usesEnhancedSiri
                        ? "$__lazy_storage_$_windowManager"
                        : "windowManager",
                    on: host.appDelegate,
                ) as? NSObject,
            )
            #expect(NSStringFromClass(type(of: manager)) == (usesEnhancedSiri
                    ? "CampoUIInternal.MacWindowManager"
                    : "SpotlightUIInternal.WindowManager"))
            #expect(manager.responds(to: NSSelectorFromString("spotlightIsVisible")))
            if usesEnhancedSiri {
                let menuItem = try #require(
                    nativeObjectIvar(named: "spotlightMenuItem", on: host.appDelegate),
                )
                let keyCommandManager = try #require(
                    nativeObjectIvar(named: "spotlightKeyCommandManager", on: host.appDelegate),
                )
                #expect(
                    menuItem.perform(NSSelectorFromString("delegate"))?
                        .takeUnretainedValue() === host.appDelegate,
                )
                #expect(
                    keyCommandManager.perform(NSSelectorFromString("delegate"))?
                        .takeUnretainedValue() === host.appDelegate,
                )
                #expect(
                    manager.responds(
                        to: NSSelectorFromString("applicationLostFocusWithReason:"),
                    ),
                )
            }
            #expect(host.viewController.responds(to: NSSelectorFromString("insertText:")))
            #expect(host.restoresAppsBrowsingResults)
            #expect(host.panel.windowController != nil)
            #expect(
                nativeFirstDescendant(
                    identifiedBy: "CornerlightLauncherBackdrop",
                    in: host.viewController.view,
                ) == nil,
            )
            #expect(!host.isPresented)
            return
        }

        #expect(NSStringFromClass(type(of: host.appDelegate)) == "SPAppDelegate")
        #expect(!host.restoresAppsBrowsingResults)
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
    // swiftlint:disable:next function_body_length
    func `presentation keeps enumerated results in Spotlights live hierarchy`() async throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        guard SpotlightExecutableRuntime.generation == .spotlightUIInternal else {
            return
        }
        let originalAlphaValue = host.panel.alphaValue
        host.panel.alphaValue = 0
        defer {
            host.dismiss()
            host.panel.orderOut(nil)
            host.panel.alphaValue = originalAlphaValue
        }

        host.update(
            suggestions: [],
            applications: [
                ApplicationRecord(
                    name: "Calculator",
                    url: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
                ),
            ],
        )
        let invocationStartedAt = Date()
        host.invoke()
        await waitForNativeSpotlightPresentation {
            guard let pageController = nativeAppsBrowsingPageController(in: host.view),
                  let selectedController = pageController.selectedViewController,
                  NSStringFromClass(type(of: selectedController)).contains(
                      "SandwichViewController",
                  ),
                  let resultsController = nativeResponder(
                      named: "SpotlightUIInternal.SearchResultsViewController",
                      in: selectedController.view,
                  ) as? NSViewController,
                  let collectionView = nativeDescendant(
                      named: "SearchUICollectionView",
                      in: resultsController.view,
                  ) as? NSCollectionView
            else { return false }
            return !selectedController.view.isHidden &&
                collectionView.numberOfSections > 0 &&
                collectionView.numberOfItems(inSection: 0) > 0 &&
                nativeDescendants(
                    named: "SearchUIBackgroundColorView",
                    in: host.view,
                ).contains(where: { $0.frame.size == NSSize(width: 844, height: 520) })
        }
        let presentationDuration = Date().timeIntervalSince(invocationStartedAt)

        let nativePageController = try #require(nativeAppsBrowsingPageController(in: host.view))
        let liveSelectedController = try #require(nativePageController.selectedViewController)
        let liveResultsController = try #require(
            nativeResponder(
                named: "SpotlightUIInternal.SearchResultsViewController",
                in: liveSelectedController.view,
            ) as? NSViewController,
        )
        let liveCollectionView = try #require(
            nativeDescendant(named: "SearchUICollectionView", in: liveResultsController.view)
                as? NSCollectionView,
        )
        let windowState = try #require(
            nativeObjectIvar(named: "windowState", on: host.viewController),
        )
        let currentWindowState = try #require(
            Mirror(reflecting: windowState).children.first(where: {
                $0.label == "_current"
            })?.value,
        )
        let backgroundViews = nativeDescendants(
            named: "SearchUIBackgroundColorView",
            in: host.view,
        )
        #expect(liveResultsController === host.retainedNativeResultsController)
        #expect(liveCollectionView === host.retainedNativeCollectionView)
        #expect(NSStringFromClass(type(of: liveSelectedController)).contains("SandwichViewController"))
        if SpotlightExecutableRuntime.usesEnhancedSiri {
            #expect(String(reflecting: currentWindowState).contains("prompt"))
        } else {
            let viewControllerFactory = try #require(
                nativeObjectIvar(named: "viewControllerFactory", on: host.viewController),
            )
            let factoryConfiguration = try #require(
                Mirror(reflecting: viewControllerFactory).children.first(where: {
                    $0.label == "configuration"
                })?.value,
            )
            let sizingCoordinator = try #require(
                nativeObjectIvar(named: "sizingCoordinator", on: host.viewController),
            )
            let windowSize = try #require(
                nativeObjectIvar(named: "windowSize", on: sizingCoordinator),
            )
            let windowBehavior = try #require(
                Mirror(reflecting: windowSize).children.first(where: {
                    $0.label == "_behavior"
                })?.value,
            )
            #expect(String(reflecting: currentWindowState).contains("Applications"))
            #expect(String(reflecting: factoryConfiguration).contains("Mode.regular"))
            #expect(String(reflecting: windowBehavior).contains("minSize: (844.0, 520.0)"))
        }
        #expect(presentationDuration < 0.75)
        #expect(backgroundViews.count >= 2)
        #expect(backgroundViews.contains(where: { $0.frame.size == NSSize(width: 844, height: 520) }))
        #expect(nativeDescendant(named: "SearchUIGradientView", in: host.view) != nil)
        let sectionCount = liveCollectionView.numberOfSections
        #expect(sectionCount > 0)
        if sectionCount > 0 {
            #expect(liveCollectionView.numberOfItems(inSection: 0) > 0)
        }
        #expect(liveSelectedController.view.frame.width == 844)
        #expect(liveSelectedController.view.frame.height == (SpotlightExecutableRuntime.usesEnhancedSiri
                ? 520
                : 434))
        #expect(liveCollectionView.frame.height > 1)
        #expect(liveResultsController.preferredContentSize.height > 1)
        #expect(nativePageController.selectedViewController?.view.isHidden == false)
        let initialSelectedWidth = liveSelectedController.view.frame.width
        let initialSelectedPreferredWidth = liveSelectedController.preferredContentSize.width
        let initialCollectionWidth = liveCollectionView.frame.width
        let initialScrollWidth = liveCollectionView.enclosingScrollView?.frame.width
        #expect(initialSelectedPreferredWidth == initialSelectedWidth)
        #expect(initialCollectionWidth == initialSelectedWidth)
        #expect(initialScrollWidth == initialSelectedWidth)

        host.dismiss()
        await waitForNativeSpotlightPresentation(timeout: 0.5) { false }
        host.releaseDismissedContent()
        host.update(
            suggestions: [],
            applications: [
                ApplicationRecord(
                    name: "Calculator",
                    url: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
                ),
            ],
        )
        host.invoke()
        await waitForNativeSpotlightPresentation {
            guard let pageController = nativeAppsBrowsingPageController(in: host.view),
                  let selectedController = pageController.selectedViewController
            else { return false }
            return host.retainedNativeCollectionView.numberOfSections > 0 &&
                host.retainedNativeCollectionView.numberOfItems(inSection: 0) > 0 &&
                selectedController.view.frame.width == initialSelectedWidth
        }

        let relaunchedCollectionView = host.retainedNativeCollectionView
        let relaunchedPageController = try #require(
            nativeAppsBrowsingPageController(in: host.view),
        )
        let relaunchedSelectedController = try #require(
            relaunchedPageController.selectedViewController,
        )
        #expect(relaunchedCollectionView.numberOfSections > 0)
        if relaunchedCollectionView.numberOfSections > 0 {
            #expect(relaunchedCollectionView.numberOfItems(inSection: 0) > 0)
        }
        #expect(NSStringFromClass(type(of: relaunchedSelectedController)).contains("SandwichViewController"))
        #expect(relaunchedSelectedController.view.frame.height > 1)
        #expect(relaunchedCollectionView.frame.height > 1)
        #expect(relaunchedSelectedController.view.frame.width == initialSelectedWidth)
        #expect(
            relaunchedSelectedController.preferredContentSize.width == initialSelectedPreferredWidth,
        )
        #expect(relaunchedCollectionView.frame.width == initialCollectionWidth)
        #expect(relaunchedCollectionView.enclosingScrollView?.frame.width == initialScrollWidth)
    }

    @Test @MainActor
    func `a WindowServer corner entry cannot be consumed by Spotlights Dock suppression flag`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        let setter = NSSelectorFromString("setIgnoreDockAppsLaunch:")
        let getter = NSSelectorFromString("ignoreDockAppsLaunch")
        typealias BoolSetter = @convention(c) (AnyObject, Selector, Bool) -> Void
        typealias BoolGetter = @convention(c) (AnyObject, Selector) -> Bool

        if SpotlightExecutableRuntime.generation == .spotlightUIInternal {
            #expect(!host.appDelegate.responds(to: setter))
            #expect(!host.appDelegate.responds(to: getter))
            host.prepareForWindowServerInvocation()
            return
        }

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

        let usesInternalFramework = SpotlightExecutableRuntime.generation == .spotlightUIInternal
        #expect(NSStringFromClass(type(of: host.viewController)) == (usesInternalFramework
                ? "SpotlightUIInternal.SearchViewController"
                : "SpotlightAppMacOS.SearchViewController"))
        #expect(NSStringFromClass(type(of: host.searchField)) == (usesInternalFramework
                ? "SpotlightUIInternal.SearchField"
                : "SpotlightAppMacOS.SearchField"))
        #expect(NSStringFromClass(type(of: host.panel)) == (usesInternalFramework
                ? "SpotlightUIInternal.FluidWindow"
                : "SPSpotlightPanel"))
        #expect(NSStringFromClass(type(of: mainWindowController)) == (usesInternalFramework
                ? "SpotlightUIInternal.MainWindowController"
                : "SpotlightAppMacOS.MainWindowController"))
        if usesInternalFramework {
            #expect(
                mainWindowController.responds(
                    to: NSSelectorFromString("windowShouldClose:"),
                ),
            )
            return
        }
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
        let indexingView = try #require(firstDescendant(
            named: SpotlightExecutableRuntime.generation == .spotlightUIInternal
                ? "SPUISpotlightIndexingView"
                : "SPSpotlightIndexingView",
            in: host.view,
        ))
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
    // swiftlint:disable:next function_body_length
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
            nativeResultsController(in: host) as? NSViewController,
        )
        let sections = try #require(
            resultsController
                .perform(NSSelectorFromString("sections"))?
                .takeUnretainedValue() as? NSArray,
        )

        #expect(NSStringFromClass(type(of: resultsController)) ==
            (SpotlightExecutableRuntime.generation == .spotlightUIInternal
                ? "SpotlightUIInternal.SearchResultsViewController"
                : "SpotlightAppMacOS.SearchResultsViewController"))
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

        if SpotlightExecutableRuntime.generation == .spotlightUIInternal {
            let selector = NSSelectorFromString("isBelowVisibleFilterBar")
            typealias BoolGetter = @convention(c) (AnyObject, Selector) -> Bool
            #expect(resultsController.responds(to: selector))
            #expect(!unsafeBitCast(resultsController.method(for: selector), to: BoolGetter.self)(
                resultsController,
                selector,
            ))
        } else {
            let queryFilterBar = try #require(firstDescendant(
                named: "SpotlightAppMacOS.QueryFilterBarView",
                in: host.view,
            ))
            #expect(queryFilterBar.isHidden)
        }
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
        let nativeMenuClass: AnyClass = try #require(NSClassFromString(
            SpotlightExecutableRuntime.generation == .spotlightUIInternal
                ? "_TtC19SpotlightUIInternal15ViewOptionsMenu"
                : "_TtC17SpotlightAppMacOS15ViewOptionsMenu",
        ))
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

@MainActor
private func waitForNativeSpotlightPresentation(
    timeout: TimeInterval = 2,
    condition: () -> Bool,
) async {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while !condition(), Date() < deadline {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                continuation.resume()
            }
        }
    }
}
