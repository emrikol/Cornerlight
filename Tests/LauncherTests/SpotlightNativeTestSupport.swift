import AppKit
@testable import Cornerlight
import Testing

private typealias SnapshotBuilder = @convention(c) (
    AnyObject,
    Selector,
    NSArray,
    UInt,
) -> Unmanaged<AnyObject>?
private typealias SnapshotCompletion = @convention(block) () -> Void
private typealias SnapshotUpdater = @convention(c) (
    AnyObject,
    Selector,
    AnyObject,
    UInt,
    Bool,
    SnapshotCompletion,
) -> Void
private typealias CollectionControllerInitializer = @convention(c) (
    AnyObject,
    Selector,
    Bool,
) -> Unmanaged<AnyObject>?

@MainActor
final class NativeCollectionTestSurface {
    let window: NSWindow
    let collectionView: NSCollectionView

    init(host: SpotlightNativeLauncherUI) throws {
        let installedCollectionController = try #require(
            host.collectionView.perform(NSSelectorFromString("controller"))?
                .takeUnretainedValue(),
        )
        let collectionController = try replacementCollectionController(
            matching: installedCollectionController,
        )
        let viewController = try #require(collectionController as? NSViewController)
        window = NSWindow(
            contentRect: viewController.view.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
        )
        window.contentViewController = viewController

        let resultsController = try #require(
            host.viewController
                .perform(NSSelectorFromString("resultsViewController"))?
                .takeUnretainedValue(),
        )
        let sections = try #require(
            resultsController.perform(NSSelectorFromString("sections"))?
                .takeUnretainedValue() as? NSArray,
        )
        try applyNativeSnapshot(sections, to: collectionController)
        viewController.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        collectionView = try #require(
            nativeDescendant(named: "SearchUICollectionView", in: viewController.view)
                as? NSCollectionView,
        )
    }
}

@MainActor
func nativeApplicationContextMenu(in host: SpotlightNativeLauncherUI) throws -> NSMenu {
    let collectionView = try #require(
        nativeDescendant(named: "SearchUICollectionView", in: host.view)
            as? NSCollectionView,
    )
    let installedCollectionController = try #require(
        collectionView.perform(NSSelectorFromString("controller"))?.takeUnretainedValue(),
    )
    let collectionController = try replacementCollectionController(
        matching: installedCollectionController,
    )
    let resultsController = try #require(
        host.viewController
            .perform(NSSelectorFromString("resultsViewController"))?
            .takeUnretainedValue(),
    )
    let sections = try #require(
        resultsController.perform(NSSelectorFromString("sections"))?
            .takeUnretainedValue() as? NSArray,
    )
    try applyNativeSnapshot(sections, to: collectionController)
    host.view.layoutSubtreeIfNeeded()

    return try #require(
        collectionController.perform(
            NSSelectorFromString("menuForItemAtIndexPath:"),
            with: NSIndexPath(forItem: 0, inSection: 0),
        )?.takeUnretainedValue() as? NSMenu,
    )
}

@MainActor
private func replacementCollectionController(matching controller: AnyObject) throws -> AnyObject {
    let controllerClass = type(of: controller) as AnyObject
    let allocated = try #require(
        controllerClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
    )
    let initializer = NSSelectorFromString("initForAboveFilterResults:")
    let replacement = try #require(
        unsafeBitCast(allocated.method(for: initializer), to: CollectionControllerInitializer.self)(
            allocated,
            initializer,
            false,
        )?.takeRetainedValue(),
    )
    let viewController = try #require(replacement as? NSViewController)
    viewController.view.frame = NSRect(x: 0, y: 0, width: 844, height: 475)
    viewController.view.layoutSubtreeIfNeeded()
    return replacement
}

@MainActor
func applyNativeSnapshot(_ sections: NSArray, to collectionController: AnyObject) throws {
    let builderClass: AnyClass = try #require(
        NSClassFromString("SearchUIDataSourceSnapshotBuilder"),
    )
    let builder = try #require(
        (builderClass as AnyObject).perform(NSSelectorFromString("new"))?
            .takeRetainedValue(),
    )
    let buildSelector = NSSelectorFromString("buildSnapshotFromResultSections:queryId:")
    let snapshot = try #require(
        unsafeBitCast(builder.method(for: buildSelector), to: SnapshotBuilder.self)(
            builder,
            buildSelector,
            sections,
            1,
        )?.takeUnretainedValue(),
    )

    var finished = false
    let completion: SnapshotCompletion = { finished = true }
    let updateSelector = NSSelectorFromString("updateWithSnapshot:queryId:animated:completion:")
    unsafeBitCast(
        collectionController.method(for: updateSelector),
        to: SnapshotUpdater.self,
    )(
        collectionController,
        updateSelector,
        snapshot,
        1,
        false,
        completion,
    )
    let deadline = Date(timeIntervalSinceNow: 1)
    while !finished, RunLoop.current.run(mode: .default, before: deadline) {}
    #expect(finished)
}

@MainActor
private func nativeDescendant(named name: String, in root: NSView) -> NSView? {
    if NSStringFromClass(type(of: root)) == name {
        return root
    }
    for subview in root.subviews {
        if let match = nativeDescendant(named: name, in: subview) {
            return match
        }
    }
    return nil
}
