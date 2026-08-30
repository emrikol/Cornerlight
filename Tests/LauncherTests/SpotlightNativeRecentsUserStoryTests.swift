import AppKit
@testable import Cornerlight
import Testing

private typealias NativeSnapshotBuilder = @convention(c) (
    AnyObject,
    Selector,
    NSArray,
    UInt,
) -> Unmanaged<AnyObject>?
private typealias NativeSeparatorStyleGetter = @convention(c) (
    AnyObject,
    Selector,
    UInt,
    Bool,
) -> Int32
@Suite(.serialized)
struct SpotlightNativeRecentsUserStoryTests {
    @Test @MainActor
    // swiftlint:disable:next function_body_length
    func `recent apps and catalog share Spotlights scrolling results surface`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        host.update(
            suggestions: [
                ApplicationRecord(
                    name: "App Store",
                    url: URL(fileURLWithPath: "/System/Applications/App Store.app"),
                ),
            ],
            applications: [
                ApplicationRecord(
                    name: "Calculator",
                    url: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
                ),
            ],
        )

        let navigationControllers = try #require(
            host.viewController.perform(NSSelectorFromString("viewControllers"))?
                .takeUnretainedValue() as? NSArray,
        )
        let sandwichController = try #require(navigationControllers.firstObject as AnyObject?)
        let aboveFilterController = try #require(
            objectIvar(named: "topHitViewController", on: sandwichController),
        )
        let scrollingResultsController = try #require(
            objectIvar(named: "resultsViewController", on: sandwichController),
        )
        let aboveFilterSections = try sections(of: aboveFilterController)
        let scrollingSections = try sections(of: scrollingResultsController)

        #expect(aboveFilterSections.count == 0)
        #expect(scrollingSections.count == 2)

        let suggestionSection = try #require(scrollingSections[0] as? NSObject)
        let catalogSection = try #require(scrollingSections[1] as? NSObject)
        #expect(suggestionSection.value(forKey: "title") as? String == "")
        #expect(catalogSection.value(forKey: "title") as? String == "")
        #expect(
            suggestionSection.value(forKey: "identifier") as? String ==
                "com.apple.spotlight.zkw.apps.suggestions",
        )
        #expect(
            catalogSection.value(forKey: "identifier") as? String ==
                "com.apple.spotlight.zkw.alphabetic",
        )

        let suggestionResults = try #require(suggestionSection.value(forKey: "results") as? NSArray)
        let suggestionResult = try #require(suggestionResults.firstObject as? NSObject)
        #expect(
            suggestionResult.value(forKey: "sectionBundleIdentifier") as? String ==
                "com.apple.spotlight.zkw",
        )

        let scrollingViewController = try #require(scrollingResultsController as? NSViewController)
        let collectionView = try #require(
            firstDescendant(of: NSCollectionView.self, in: scrollingViewController.view),
        )
        #expect(collectionView.numberOfSections == 2)

        let snapshotBuilderClass: AnyClass = try #require(
            NSClassFromString("SearchUIDataSourceSnapshotBuilder"),
        )
        let snapshotBuilder = try #require(
            (snapshotBuilderClass as AnyObject)
                .perform(NSSelectorFromString("new"))?
                .takeRetainedValue(),
        )
        let buildSnapshotSelector = NSSelectorFromString(
            "buildSnapshotFromResultSections:queryId:",
        )
        let snapshot = try #require(
            unsafeBitCast(
                snapshotBuilder.method(for: buildSnapshotSelector),
                to: NativeSnapshotBuilder.self,
            )(
                snapshotBuilder,
                buildSnapshotSelector,
                scrollingSections,
                1,
            )?.takeUnretainedValue(),
        )
        let sectionModels = try #require(
            snapshot.perform(NSSelectorFromString("sectionIdentifiers"))?
                .takeUnretainedValue() as? NSArray,
        )
        typealias BoolGetter = @convention(c) (AnyObject, Selector) -> Bool
        for sectionModel in sectionModels {
            let model = sectionModel as AnyObject
            let nativeSection = try #require(
                model.perform(NSSelectorFromString("section"))?.takeUnretainedValue(),
            )
            let isBrowseSectionSelector = NSSelectorFromString("isBrowseSection")
            #expect(
                unsafeBitCast(
                    nativeSection.method(for: isBrowseSectionSelector),
                    to: BoolGetter.self,
                )(nativeSection, isBrowseSectionSelector),
            )
        }
        let catalogSectionModel = try #require(sectionModels.lastObject as AnyObject?)
        let needsHeaderSelector = NSSelectorFromString("needsHeader")
        #expect(
            !unsafeBitCast(
                catalogSectionModel.method(for: needsHeaderSelector),
                to: BoolGetter.self,
            )(catalogSectionModel, needsHeaderSelector),
        )
        let separatorSelector = NSSelectorFromString(
            "separatorStyleForIndex:shouldDrawTopAndBottomSeparators:",
        )
        #expect(
            unsafeBitCast(
                catalogSectionModel.method(for: separatorSelector),
                to: NativeSeparatorStyleGetter.self,
            )(catalogSectionModel, separatorSelector, 0, false) == 1,
        )

        scrollingViewController.view.frame = NSRect(x: 0, y: 0, width: 844, height: 475)
        collectionView.collectionViewLayout?.invalidateLayout()
        scrollingViewController.view.layoutSubtreeIfNeeded()
        let separator = try #require(
            firstDescendant(
                named: "_TtGC8SearchUI24SupplementaryHostingViewVS_9Separator_",
                in: scrollingViewController.view,
            ),
        )
        let suggestionItem = try #require(
            collectionView.item(at: IndexPath(item: 0, section: 0)),
        )
        let catalogItem = try #require(
            collectionView.item(at: IndexPath(item: 0, section: 1)),
        )
        #expect(separator.frame.height == 1)
        #expect(separator.frame.minY > suggestionItem.view.frame.maxY)
        #expect(separator.frame.maxY < catalogItem.view.frame.minY)

        _ = scrollingResultsController.perform(
            NSSelectorFromString("setSections:"),
            with: NSArray(),
        )
        #expect(try sections(of: aboveFilterController).count == 0)
        #expect(try sections(of: scrollingResultsController).count == 2)
    }

    private func sections(of controller: AnyObject) throws -> NSArray {
        try #require(
            controller.perform(NSSelectorFromString("sections"))?
                .takeUnretainedValue() as? NSArray,
        )
    }

    private func objectIvar(named name: String, on object: AnyObject) -> AnyObject? {
        guard let ivar = class_getInstanceVariable(type(of: object), name),
              let rawValue = Unmanaged.passUnretained(object).toOpaque()
              .advanced(by: ivar_getOffset(ivar))
              .load(as: UnsafeRawPointer?.self)
        else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(rawValue).takeUnretainedValue()
    }

    @MainActor
    private func firstDescendant<View: NSView>(of _: View.Type, in root: NSView) -> View? {
        if let match = root as? View {
            return match
        }
        for subview in root.subviews {
            if let match = firstDescendant(of: View.self, in: subview) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func firstDescendant(named className: String, in root: NSView) -> NSView? {
        if NSStringFromClass(type(of: root)) == className {
            return root
        }
        for subview in root.subviews {
            if let match = firstDescendant(named: className, in: subview) {
                return match
            }
        }
        return nil
    }
}
