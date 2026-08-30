import AppKit
@testable import Cornerlight
import Testing

struct LauncherSettingsUserStoryTests {
    @Test
    func `launch at login uses native registration and approval paths`() {
        #expect(
            LauncherLoginItemActionPolicy.action(enabling: true, status: .disabled) == .register,
        )
        #expect(
            LauncherLoginItemActionPolicy.action(enabling: true, status: .requiresApproval)
                == .openSystemSettings,
        )
        #expect(
            LauncherLoginItemActionPolicy.action(enabling: false, status: .enabled) == .unregister,
        )
        #expect(
            LauncherLoginItemActionPolicy.action(enabling: true, status: .enabled) == .none,
        )
    }

    @Test
    func `launch at login explains enabled approval and error states`() {
        let enabled = LauncherLoginItemPresentation.content(for: .enabled)
        #expect(enabled.isEnabled)
        #expect(enabled.message.contains("quietly"))
        #expect(!enabled.isError)

        let approval = LauncherLoginItemPresentation.content(for: .requiresApproval)
        #expect(!approval.isEnabled)
        #expect(approval.message.contains("System Settings"))

        let failure = LauncherLoginItemPresentation.content(
            for: .enabled,
            errorMessage: "Permission denied",
        )
        #expect(failure.isEnabled)
        #expect(failure.message.contains("Permission denied"))
        #expect(failure.isError)
    }

    @Test
    func `settings lists hidden applications by name while preserving exact paths`() {
        let applications = LauncherHiddenApplicationSettingsPolicy.applications(for: [
            "/Applications/Zed.app",
            "/System/Applications/Utilities/Audio MIDI Setup.app",
            "/Missing/Archived.app",
        ])

        #expect(applications.map(\.name) == ["Archived", "Audio MIDI Setup", "Zed"])
        #expect(applications.map(\.path) == [
            "/Missing/Archived.app",
            "/System/Applications/Utilities/Audio MIDI Setup.app",
            "/Applications/Zed.app",
        ])
    }
}
