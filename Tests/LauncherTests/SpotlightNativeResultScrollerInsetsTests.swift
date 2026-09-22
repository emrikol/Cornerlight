import AppKit
@testable import Cornerlight
import Testing

@Suite(.serialized)
struct NativeResultScrollerInsetsTests {
    @Test @MainActor
    func `result scroller uses SearchUIs native platter corner radius`() {
        let collectionView = NSCollectionView(
            frame: NSRect(x: 0, y: 0, width: 827, height: 900),
        )
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 844, height: 520),
        )
        scrollView.documentView = collectionView

        let applied = SpotlightNativeResultScrollerInsets.apply(
            to: collectionView,
            maximumCornerRadius: 37,
        )

        #expect(applied)
        #expect(scrollView.scrollerInsets.top == 37)
        #expect(scrollView.scrollerInsets.left == 0)
        #expect(scrollView.scrollerInsets.bottom == 37)
        #expect(scrollView.scrollerInsets.right == 0)
    }

    @Test @MainActor
    func `result scroller radius cannot exceed half its height`() {
        let collectionView = NSCollectionView(
            frame: NSRect(x: 0, y: 0, width: 827, height: 100),
        )
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 844, height: 40),
        )
        scrollView.documentView = collectionView

        let applied = SpotlightNativeResultScrollerInsets.apply(
            to: collectionView,
            maximumCornerRadius: 37,
        )

        #expect(applied)
        #expect(scrollView.scrollerInsets.top == 20)
        #expect(scrollView.scrollerInsets.bottom == 20)
    }

    @Test @MainActor
    func `missing result scroll view leaves native layout untouched`() {
        let collectionView = NSCollectionView(frame: .zero)

        #expect(!SpotlightNativeResultScrollerInsets.apply(
            to: collectionView,
            maximumCornerRadius: 37,
        ))
    }
}
