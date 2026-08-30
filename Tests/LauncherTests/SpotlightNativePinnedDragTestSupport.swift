import AppKit
@testable import Cornerlight
import Testing

private typealias NativeCanDragPinnedItems = @convention(c) (
    AnyObject,
    Selector,
    NSCollectionView,
    NSSet,
    NSEvent?,
) -> Bool

final class PinnedMoveObservation {
    var applicationURL: URL?
    var insertionIndex: Int?
    var visibleApplicationURLs: [URL] = []
}

@MainActor
private func makePinnedReorderSurface(
    for host: SpotlightNativeLauncherUI,
) throws -> (controller: AnyObject, window: NSWindow) {
    let controller = try #require(
        host.collectionView.perform(NSSelectorFromString("controller"))?
            .takeUnretainedValue(),
    )
    let resultsController = try #require(
        host.viewController.perform(NSSelectorFromString("resultsViewController"))?
            .takeUnretainedValue(),
    )
    let sections = try #require(
        resultsController.perform(NSSelectorFromString("sections"))?
            .takeUnretainedValue() as? NSArray,
    )
    try applyNativeSnapshot(sections, to: controller)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 844, height: 475),
        styleMask: .borderless,
        backing: .buffered,
        defer: false,
    )
    window.contentViewController = host.viewController
    host.viewController.view.frame = window.contentView?.bounds ?? .zero
    host.viewController.view.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    return (controller, window)
}

@MainActor
final class NativePinnedReorderHarness {
    let host: SpotlightNativeLauncherUI
    let pinnedApplications: [ApplicationRecord]
    let observation = PinnedMoveObservation()

    private let window: NSWindow
    private let collectionController: AnyObject
    private let collectionDataSource: AnyObject
    private let canDragSelector = NSSelectorFromString(
        "collectionView:canDragItemsAtIndexPaths:withEvent:",
    )

    init() throws {
        host = try #require(SpotlightNativeLauncherUI())
        pinnedApplications = [
            ApplicationRecord(
                name: "App Store",
                url: URL(fileURLWithPath: "/System/Applications/App Store.app"),
            ),
            ApplicationRecord(
                name: "Calculator",
                url: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
            ),
        ]
        let recent = ApplicationRecord(
            name: "Calendar",
            url: URL(fileURLWithPath: "/System/Applications/Calendar.app"),
        )
        let pinnedPaths = Set(pinnedApplications.map(\.url.standardizedFileURL.path))
        host.isApplicationPinned = {
            pinnedPaths.contains($0.standardizedFileURL.path)
        }
        host.onMovePinnedApplication = { [observation] url, index, visibleURLs in
            observation.applicationURL = url
            observation.insertionIndex = index
            observation.visibleApplicationURLs = visibleURLs
        }
        host.update(suggestions: pinnedApplications + [recent], applications: [])
        let surface = try makePinnedReorderSurface(for: host)
        collectionController = surface.controller
        collectionDataSource = try #require(host.collectionView.dataSource as AnyObject?)
        window = surface.window
    }

    func canDrag(items: [Int]) -> Bool {
        let indexPaths = NSSet(
            array: items.map { NSIndexPath(forItem: $0, inSection: 0) },
        )
        return unsafeBitCast(
            collectionController.method(for: canDragSelector),
            to: NativeCanDragPinnedItems.self,
        )(
            collectionController,
            canDragSelector,
            host.collectionView,
            indexPaths,
            nil,
        )
    }

    var collectionIsSelectable: Bool {
        host.collectionView.isSelectable
    }

    var usesSeparateSearchUIDataSource: Bool {
        collectionDataSource !== collectionController &&
            NSStringFromClass(type(of: collectionDataSource)) == "SearchUICollectionViewDataSource"
    }

    func updatePointerReorder(source: Int, destination: Int) -> Bool {
        let sourcePath = IndexPath(item: source, section: 0)
        host.collectionView.selectionIndexPaths = [sourcePath]
        host.beginPinnedApplicationPointerReorder(in: host.collectionView)

        let frames = pinnedApplications.indices.compactMap { item in
            host.collectionView.collectionViewLayout?
                .layoutAttributesForItem(at: IndexPath(item: item, section: 0))?.frame
        }
        guard frames.count == pinnedApplications.count else { return false }
        let point = NSPoint(x: frames[destination].minX, y: frames[destination].midY)
        return host.updatePinnedApplicationPointerReorder(
            in: host.collectionView,
            at: point,
        )
    }

    func updatePointerDragPreview(source: Int, destination: Int) -> (NSPoint, NSRect?) {
        let sourcePath = IndexPath(item: source, section: 0)
        let destinationPath = IndexPath(item: destination, section: 0)
        let sourceFrame = host.collectionView.collectionViewLayout?
            .layoutAttributesForItem(at: sourcePath)?.frame ?? .zero
        let destinationFrame = host.collectionView.collectionViewLayout?
            .layoutAttributesForItem(at: destinationPath)?.frame ?? .zero
        let sourcePoint = NSPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let destinationPoint = NSPoint(x: destinationFrame.midX, y: destinationFrame.midY)
        host.collectionView.selectionIndexPaths = [sourcePath]
        host.beginPinnedApplicationPointerReorder(
            in: host.collectionView,
            at: sourcePoint,
        )
        _ = host.updatePinnedApplicationPointerReorder(
            in: host.collectionView,
            at: destinationPoint,
        )
        return (destinationPoint, host.pinnedApplicationDragPreviewFrame)
    }
}
