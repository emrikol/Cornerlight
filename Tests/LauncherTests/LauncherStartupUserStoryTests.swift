@testable import Cornerlight
import Testing

struct LauncherStartupUserStoryTests {
    @Test
    func `a launch services reopen cannot present during background bootstrap`() {
        let arguments = ["Cornerlight", "--background"]
        #expect(
            !LauncherReopenPolicy.shouldInvokeLauncher(
                arguments: arguments,
                elapsedSinceLaunch: 0.85,
            ),
        )
        #expect(
            LauncherReopenPolicy.shouldInvokeLauncher(
                arguments: arguments,
                elapsedSinceLaunch: 2.1,
            ),
        )
        #expect(
            LauncherReopenPolicy.shouldInvokeLauncher(
                arguments: ["Cornerlight"],
                elapsedSinceLaunch: 0,
            ),
        )
    }
}
