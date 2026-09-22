import AppKit
@testable import Cornerlight
import Testing

@Suite(.serialized)
struct SpotlightNativeEventCollectorQueueTests {
    @Test @MainActor
    func `replacement native menu items each own an event collector queue`() throws {
        _ = NSApplication.shared
        let first = try #require(SpotlightNativeLauncherUI())
        #expect(eventCollectorQueue(in: first) != nil)

        let replacement = try #require(SpotlightNativeLauncherUI())
        #expect(eventCollectorQueue(in: replacement) != nil)
    }

    @MainActor
    private func eventCollectorQueue(in host: SpotlightNativeLauncherUI) -> AnyObject? {
        let getter = NSSelectorFromString("menuItem")
        let menuItem = host.appDelegate.responds(to: getter)
            ? host.appDelegate.perform(getter)?.takeUnretainedValue()
            : nativeObjectIvar(named: "menuItem", on: host.appDelegate) ??
            nativeObjectIvar(named: "spotlightMenuItem", on: host.appDelegate)
        return menuItem?
            .perform(NSSelectorFromString("eventCollectorQueue"))?
            .takeUnretainedValue()
    }
}
