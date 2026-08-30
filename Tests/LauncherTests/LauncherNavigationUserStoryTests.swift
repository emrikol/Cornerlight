import AppKit
@testable import Cornerlight
import Testing

@Suite(.serialized)
struct LauncherNavigationUserStoryTests {
    @Test @MainActor
    func `spotlights main controller owns the launcher window`() throws {
        _ = NSApplication.shared
        let host = try #require(SpotlightNativeLauncherUI())
        let controller = try #require(host.panel.windowController)

        #expect(
            NSStringFromClass(type(of: controller)) ==
                "SpotlightAppMacOS.MainWindowController",
        )
        #expect(controller.window === host.panel)
        #expect(host.panel.contentViewController != nil)
    }
}
