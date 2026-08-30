import AppKit
@testable import Cornerlight
import Testing

@Suite(.serialized)
struct LauncherPinningUserStoryTests {
    @Test
    func `pinned apps lead the native seven item row and recents fill the remainder`() {
        let apps = applicationFixtures(count: 10)
        let suggestions = LauncherSuggestionPolicy.applications(
            in: apps,
            pinnedApplicationPaths: [
                apps[6].url.standardizedFileURL.path,
                apps[2].url.standardizedFileURL.path,
            ],
            matching: [
                "com.example.app2", "com.example.app1", "com.example.app8",
                "com.example.app0", "com.example.app3", "com.example.app4",
            ],
        )

        #expect(suggestions == [apps[6], apps[2], apps[1], apps[8], apps[0], apps[3], apps[4]])
        #expect(suggestions.count <= LauncherSuggestionPolicy.maximumCount)
    }

    @Test
    func `a hidden pin stays persisted while remaining absent from the native row`() {
        let apps = applicationFixtures(count: 3)
        let pinnedPaths = [apps[0].url.standardizedFileURL.path]
        let visibleInventory = LauncherApplicationVisibilityPolicy.applications(
            in: apps,
            hiddenApplicationPaths: Set(pinnedPaths),
            showsHiddenApplications: false,
        )
        let bundleIdentifiers = apps.compactMap(\.bundleIdentifier)
        let suggestionsWhileHidden = LauncherSuggestionPolicy.applications(
            in: visibleInventory,
            pinnedApplicationPaths: pinnedPaths,
            matching: bundleIdentifiers,
        )
        let suggestionsWhileShown = LauncherSuggestionPolicy.applications(
            in: apps,
            pinnedApplicationPaths: pinnedPaths,
            matching: bundleIdentifiers,
        )

        #expect(suggestionsWhileHidden == Array(apps.dropFirst()))
        #expect(suggestionsWhileShown.first == apps[0])
    }

    @Test
    func `dragging a pin reorders only the persisted pinned sequence`() {
        let paths = ["hidden", "one", "two", "three"]
        let visiblePaths = ["one", "two", "three"]

        #expect(
            LauncherPinnedApplicationPolicy.moving(
                applicationPath: "three",
                toVisibleInsertionIndex: 0,
                visibleApplicationPaths: visiblePaths,
                in: paths,
            ) == ["hidden", "three", "one", "two"],
        )
        #expect(
            LauncherPinnedApplicationPolicy.moving(
                applicationPath: "one",
                toVisibleInsertionIndex: visiblePaths.count,
                visibleApplicationPaths: visiblePaths,
                in: paths,
            ) == ["hidden", "two", "three", "one"],
        )
    }

    @Test @MainActor
    func `pins persist in order and cannot exceed the native row capacity`() throws {
        let suiteName = "LauncherTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LauncherPinnedApplicationStore(defaults: defaults)
        let applications = applicationFixtures(count: 9)

        for application in applications {
            store.setPinned(true, applicationURL: application.url)
        }
        #expect(store.applicationPaths == applications.prefix(7).map(\.url.standardizedFileURL.path))
        #expect(!store.canPinAnotherApplication)

        store.move(
            applicationURL: applications[6].url,
            toVisibleInsertionIndex: 0,
            visibleApplicationURLs: Array(applications.prefix(7)).map(\.url),
        )
        let reloaded = LauncherPinnedApplicationStore(defaults: defaults)
        #expect(reloaded.applicationPaths.first == applications[6].url.standardizedFileURL.path)

        reloaded.setPinned(false, applicationURL: applications[6].url)
        #expect(!LauncherPinnedApplicationStore(defaults: defaults).isPinned(applications[6].url))
        #expect(LauncherPinnedApplicationStore(defaults: defaults).canPinAnotherApplication)
    }

    @Test @MainActor
    func `native application menus pin and unpin the enumerated app`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        let application = ApplicationRecord(
            name: "Audio MIDI Setup",
            url: URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"),
        )
        var pinnedPaths = Set<String>()
        host.isApplicationPinned = { pinnedPaths.contains($0.standardizedFileURL.path) }
        host.canPinApplication = { _ in true }
        host.onSetApplicationPinned = { url, pinned in
            if pinned {
                pinnedPaths.insert(url.standardizedFileURL.path)
            } else {
                pinnedPaths.remove(url.standardizedFileURL.path)
            }
        }
        host.update(suggestions: [], applications: [application])

        #expect(host.hasNativePinnedReorderHook)
        let menu = try nativeApplicationContextMenu(in: host)
        let pinItem = try #require(
            menu.items.first(where: {
                $0.identifier?.rawValue == "com.emrikol.Cornerlight.toggleApplicationPin"
            }),
        )
        #expect(pinItem.title == "Pin This App")
        _ = pinItem.target?.perform(pinItem.action, with: pinItem)
        #expect(pinnedPaths == [application.url.standardizedFileURL.path])
    }

    @Test @MainActor
    func `native pinned tiles carry Spotlights TLK badge while recents do not`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        let pinned = ApplicationRecord(
            name: "App Store",
            url: URL(fileURLWithPath: "/System/Applications/App Store.app"),
        )
        let recent = ApplicationRecord(
            name: "Calculator",
            url: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
        )
        var pinnedPaths = Set([pinned.url.standardizedFileURL.path])
        host.isApplicationPinned = {
            pinnedPaths.contains($0.standardizedFileURL.path)
        }
        host.update(suggestions: [pinned, recent], applications: [])

        #expect(host.hasNativePinnedBadgeHook)
        let surface = try NativeCollectionTestSurface(host: host)
        let pinnedItem = try #require(
            surface.collectionView.item(at: IndexPath(item: 0, section: 0)),
        )
        let recentItem = try #require(
            surface.collectionView.item(at: IndexPath(item: 1, section: 0)),
        )
        let pinnedImage = try #require(
            firstNativeDescendant(named: "SearchUIImageView", in: pinnedItem.view),
        )
        let recentImage = try #require(
            firstNativeDescendant(named: "SearchUIImageView", in: recentItem.view),
        )
        let badge = try #require(
            pinnedImage.perform(NSSelectorFromString("badgeImageView"))?
                .takeUnretainedValue() as? NSView,
        )
        let recentBadge = recentImage.perform(NSSelectorFromString("badgeImageView"))?
            .takeUnretainedValue() as? NSView

        #expect(NSStringFromClass(type(of: badge)) == "SearchUIImageView")
        #expect(badge.frame.size == NSSize(width: 16, height: 16))
        #expect(recentBadge == nil)

        pinnedPaths.removeAll()
        host.nativeItemWillDisplay(
            pinnedItem,
            at: NSIndexPath(forItem: 0, inSection: 0),
        )
        let clearedBadge = pinnedImage.perform(NSSelectorFromString("badgeImageView"))?
            .takeUnretainedValue()
        #expect(
            clearedBadge?.perform(NSSelectorFromString("tlkImage"))?
                .takeUnretainedValue() == nil,
        )
    }

    @Test @MainActor
    func `native drag loop stays disabled so pointer reorder receives the complete gesture`() throws {
        _ = NSApplication.shared
        let harness = try NativePinnedReorderHarness()
        #expect(harness.usesSeparateSearchUIDataSource)
        #expect(harness.collectionIsSelectable)
        #expect(!harness.canDrag(items: [0]))
        #expect(!harness.canDrag(items: [0, 1]))
    }

    @Test @MainActor
    func `a recent tile cannot enter the pinned pointer reorder`() throws {
        _ = NSApplication.shared
        let harness = try NativePinnedReorderHarness()
        #expect(!harness.canDrag(items: [2]))
        #expect(!harness.updatePointerReorder(source: 2, destination: 0))
        #expect(harness.observation.applicationURL == nil)
    }

    private func applicationFixtures(count: Int) -> [ApplicationRecord] {
        (0 ..< count).map { index in
            ApplicationRecord(
                name: "App \(index)",
                url: URL(fileURLWithPath: "/Applications/App\(index).app"),
                bundleIdentifier: "com.example.app\(index)",
            )
        }
    }

    @MainActor
    private func firstNativeDescendant(named name: String, in root: NSView) -> NSView? {
        if NSStringFromClass(type(of: root)) == name {
            return root
        }
        for subview in root.subviews {
            if let match = firstNativeDescendant(named: name, in: subview) {
                return match
            }
        }
        return nil
    }
}

extension LauncherPinningUserStoryTests {
    @Test
    func `a completed pin reorder consumes its release without consuming clicks`() {
        var gesture = LauncherPinnedPointerGestureState()

        gesture.begin()
        gesture.record(reordered: false)
        let clickReleaseIsConsumed = gesture.end()
        #expect(!clickReleaseIsConsumed)

        gesture.begin()
        gesture.record(reordered: true)
        gesture.record(reordered: false)
        let dragReleaseIsConsumed = gesture.end()
        let followingReleaseIsConsumed = gesture.end()
        #expect(dragReleaseIsConsumed)
        #expect(!followingReleaseIsConsumed)
    }

    @Test
    func `pin drop indicator occupies the requested native row boundary`() throws {
        let frames = [
            NSRect(x: 20, y: 10, width: 80, height: 100),
            NSRect(x: 140, y: 10, width: 80, height: 100),
        ]

        let beforeFirst = try #require(
            LauncherPinnedDropPolicy.indicatorFrame(at: 0, itemFrames: frames),
        )
        let between = try #require(
            LauncherPinnedDropPolicy.indicatorFrame(at: 1, itemFrames: frames),
        )
        let afterLast = try #require(
            LauncherPinnedDropPolicy.indicatorFrame(at: 2, itemFrames: frames),
        )

        #expect(beforeFirst.midX == frames[0].minX)
        #expect(between.midX == 120)
        #expect(afterLast.midX == frames[1].maxX)
        #expect(between.width == 2)
        #expect(between.height == 84)
    }

    @Test @MainActor
    func `dragged pin icon follows the pointer and disappears when the drag ends`() throws {
        _ = NSApplication.shared
        let harness = try NativePinnedReorderHarness()

        let (pointer, previewFrame) = harness.updatePointerDragPreview(
            source: 1,
            destination: 0,
        )
        let visibleFrame = try #require(previewFrame)
        #expect(abs(visibleFrame.midX - pointer.x) < 0.5)
        #expect(abs(visibleFrame.midY - pointer.y) < 0.5)

        harness.host.endPinnedApplicationPointerReorder()
        #expect(harness.host.pinnedApplicationDragPreviewFrame == nil)
    }

    @Test @MainActor
    func `spotlight pointer drag reorders a pinned tile while crossing its neighbor`() throws {
        _ = NSApplication.shared
        let harness = try NativePinnedReorderHarness()

        #expect(harness.updatePointerReorder(source: 1, destination: 0))
        #expect(harness.observation.applicationURL == harness.pinnedApplications[1].url)
        #expect(harness.observation.insertionIndex == 0)
        #expect(harness.observation.visibleApplicationURLs == harness.pinnedApplications.map(\.url))
    }
}
