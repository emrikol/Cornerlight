import AppKit
@testable import Cornerlight
import Testing

// The suite intentionally keeps the product's plain-language stories together.
// swiftlint:disable:next type_body_length
struct LauncherUserStoryTests {
    @Test
    func `a background login launch stays hidden`() {
        #expect(!LauncherStartupPolicy.shouldShowLauncher(arguments: ["Cornerlight", "--background"]))
    }

    @Test
    func `an explicit application launch opens the launcher`() {
        #expect(LauncherStartupPolicy.shouldShowLauncher(arguments: ["Cornerlight"]))
        #expect(
            LauncherStartupPolicy.shouldShowLauncher(
                arguments: ["Cornerlight", "--show"],
                launchAtLoginEnabled: true,
            ),
        )
    }

    @Test
    func `a registered login item starts quietly`() {
        #expect(
            !LauncherStartupPolicy.shouldShowLauncher(
                arguments: ["Cornerlight"],
                launchAtLoginEnabled: true,
            ),
        )
    }

    @Test
    func `a denied invocation explains Input Monitoring before presenting the launcher`() {
        #expect(
            LauncherInvocationPolicy.action(
                kind: .hotCorner,
                isLauncherPresented: false,
                inputMonitoringGranted: false,
            ) == .explainInputMonitoring,
        )
        #expect(
            LauncherInvocationPolicy.action(
                kind: .explicit,
                isLauncherPresented: false,
                inputMonitoringGranted: false,
            ) == .explainInputMonitoring,
        )
    }

    @Test
    func `a granted hot corner invocation enters Spotlights native toggle path`() {
        #expect(
            LauncherInvocationPolicy.action(
                kind: .hotCorner,
                isLauncherPresented: false,
                inputMonitoringGranted: true,
            ) == .toggle,
        )
    }

    @Test
    func `a second hot corner entry dismisses a visible launcher even if permission changed`() {
        #expect(
            LauncherInvocationPolicy.action(
                kind: .hotCorner,
                isLauncherPresented: true,
                inputMonitoringGranted: false,
            ) == .toggle,
        )
    }

    @Test
    func `the permission explanation states the exact limited input scope`() {
        #expect(InputMonitoringPermissionContent.messageText.contains("Input Monitoring"))
        #expect(InputMonitoringPermissionContent.informativeText.contains("mouse clicks"))
        #expect(InputMonitoringPermissionContent.informativeText.contains("while the launcher is open"))
        #expect(InputMonitoringPermissionContent.informativeText.contains("does not monitor system-wide keystrokes"))
    }

    @Test
    func `repeated denied invocations cannot stack permission prompts`() {
        var state = InputMonitoringPromptPresentationState()

        let firstPresentation = state.begin()
        let repeatedPresentation = state.begin()
        #expect(firstPresentation)
        #expect(!repeatedPresentation)
        #expect(state.isPresenting)
        state.finish()
        #expect(!state.isPresenting)
        let nextPresentation = state.begin()
        #expect(nextPresentation)
    }

    @Test
    func `the permission button opens the macOS Input Monitoring pane after denial`() {
        var requested = false
        var openedURL: URL?

        let result = InputMonitoringPermissionRequestFlow.perform(
            requestAccess: {
                requested = true
                return false
            },
            preflightAccess: { false },
            openSettings: { url in
                openedURL = url
                return true
            },
        )

        #expect(requested)
        #expect(result == .settingsOpened(true))
        #expect(openedURL == InputMonitoringPermissionContent.settingsURL)
        #expect(
            openedURL?.absoluteString
                == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
        )
    }

    @Test
    func `a newly granted request proceeds without opening System Settings`() {
        var openedSettings = false

        let result = InputMonitoringPermissionRequestFlow.perform(
            requestAccess: { true },
            preflightAccess: {
                Issue.record("preflight is unnecessary after the request succeeds")
                return false
            },
            openSettings: { _ in
                openedSettings = true
                return true
            },
        )

        #expect(result == .granted)
        #expect(!openedSettings)
    }

    @Test
    func `browse mode does not duplicate suggested applications in the catalog`() {
        let apps = applicationFixtures(count: 3)

        let visible = LauncherContentPolicy.visibleCatalog(
            applications: apps,
            suggestions: [apps[1]],
            query: "",
        )

        #expect(visible == [apps[0], apps[2]])
    }

    @Test
    func `search results may include applications that are also suggested`() {
        let apps = applicationFixtures(count: 3)

        let visible = LauncherContentPolicy.visibleCatalog(
            applications: apps,
            suggestions: [apps[1]],
            query: "App 1",
        )

        #expect(visible == [apps[1]])
    }

    @Test
    func `the suggestion row preserves Spotlight prediction order and contains at most seven apps`() {
        let apps = applicationFixtures(count: 9)
        let bundleIdentifiers = [3, 1, 3] + Array(2 ... 8)

        let suggestions = LauncherSuggestionPolicy.applications(
            in: apps,
            matching: bundleIdentifiers.map { "com.example.app\($0)" },
        )

        #expect(suggestions == [apps[3], apps[1], apps[2], apps[4], apps[5], apps[6], apps[7]])
        #expect(suggestions.count == LauncherSuggestionPolicy.maximumCount)
    }

    @Test
    func `spotlight suggestions use predictions first and recents only as a deduplicated fallback`() {
        let identifiers = LauncherSuggestionPolicy.orderedBundleIdentifiers(
            predicted: ["predicted.one", "shared"],
            recent: ["shared", "recent.one"],
        )

        #expect(identifiers == ["predicted.one", "shared", "recent.one"])
    }

    @Test
    func `local recents lead system suggestions without duplicates`() {
        let identifiers = LauncherSuggestionPolicy.prioritizedBundleIdentifiers(
            localRecents: ["local.one", "shared"],
            systemSuggestions: ["shared", "system.one"],
        )

        #expect(identifiers == ["local.one", "shared", "system.one"])
    }

    @Test
    func `activating an application moves it to the front of the bounded recent history`() {
        let history = (0 ..< 40).map { "com.example.app\($0)" }

        let recorded = LauncherRecentApplicationPolicy.recording(
            "com.example.app5",
            in: history,
        )

        #expect(recorded.first == "com.example.app5")
        #expect(recorded.filter { $0 == "com.example.app5" }.count == 1)
        #expect(recorded.count == LauncherRecentApplicationPolicy.maximumStoredCount)
    }

    @Test @MainActor
    func `recent application history persists across launcher controller lifetimes`() throws {
        let suiteName = "LauncherTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LauncherRecentApplicationStore(defaults: defaults)
        store.record(bundleIdentifier: "com.example.first")
        store.record(bundleIdentifier: "com.example.second")

        let reloaded = LauncherRecentApplicationStore(defaults: defaults)
        #expect(reloaded.bundleIdentifiers == ["com.example.second", "com.example.first"])
    }

    @Test @MainActor
    func `spotlights cached predictions remain bounded for the native top application row`() {
        let applications = ApplicationCatalog.scan()
        let identifiers = SpotlightApplicationSuggestionService.cachedBundleIdentifiers()
        let suggestions = LauncherSuggestionPolicy.applications(
            in: applications,
            matching: identifiers,
        )

        #expect(suggestions.count <= LauncherSuggestionPolicy.maximumCount)
    }

    @Test
    func `duplicate bundle identifiers cannot crash the suggestion adapter`() {
        let first = ApplicationRecord(
            name: "Xcode",
            url: URL(fileURLWithPath: "/Applications/Xcode.app"),
            bundleIdentifier: "com.apple.dt.Xcode",
        )
        let duplicate = ApplicationRecord(
            name: "Xcode Beta",
            url: URL(fileURLWithPath: "/Applications/Xcode-beta.app"),
            bundleIdentifier: "com.apple.dt.Xcode",
        )

        let suggestions = LauncherSuggestionPolicy.applications(
            in: [first, duplicate],
            matching: ["com.apple.dt.Xcode"],
        )

        #expect(suggestions == [first])
    }

    @Test @MainActor
    func `hidden applications persist by their exact bundle path`() throws {
        let suiteName = "LauncherTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let applicationURL = URL(fileURLWithPath: "/Applications/Example.app")

        let store = LauncherHiddenApplicationStore(defaults: defaults)
        store.setHidden(true, applicationURL: applicationURL)

        let reloaded = LauncherHiddenApplicationStore(defaults: defaults)
        #expect(reloaded.isHidden(applicationURL))

        reloaded.setHidden(false, applicationURL: applicationURL)
        #expect(!LauncherHiddenApplicationStore(defaults: defaults).isHidden(applicationURL))
    }

    @Test @MainActor
    func `show hidden apps persists across launcher instances`() throws {
        let suiteName = "LauncherTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LauncherHiddenApplicationStore(defaults: defaults)
        #expect(!store.showsHiddenApplications)

        store.setShowsHiddenApplications(true)
        #expect(LauncherHiddenApplicationStore(defaults: defaults).showsHiddenApplications)

        store.setShowsHiddenApplications(false)
        #expect(!LauncherHiddenApplicationStore(defaults: defaults).showsHiddenApplications)
    }

    @Test
    func `hidden applications are prefiltered unless Show Hidden Apps is enabled`() {
        let visible = ApplicationRecord(
            name: "Visible",
            url: URL(fileURLWithPath: "/Applications/Visible.app"),
        )
        let hidden = ApplicationRecord(
            name: "Hidden",
            url: URL(fileURLWithPath: "/Applications/Hidden.app"),
        )
        let hiddenPaths = Set([hidden.url.standardizedFileURL.path])

        #expect(
            LauncherApplicationVisibilityPolicy.applications(
                in: [visible, hidden],
                hiddenApplicationPaths: hiddenPaths,
                showsHiddenApplications: false,
            ) == [visible],
        )
        #expect(
            LauncherApplicationVisibilityPolicy.applications(
                in: [visible, hidden],
                hiddenApplicationPaths: hiddenPaths,
                showsHiddenApplications: true,
            ) == [visible, hidden],
        )
    }

    @Test
    func `search cannot return a hidden application unless Show Hidden Apps is enabled`() {
        let visible = ApplicationRecord(
            name: "Calendar Helper",
            url: URL(fileURLWithPath: "/Applications/Calendar Helper.app"),
        )
        let hidden = ApplicationRecord(
            name: "Calendar",
            url: URL(fileURLWithPath: "/System/Applications/Calendar.app"),
        )
        let hiddenPaths = Set([hidden.url.standardizedFileURL.path])

        let hiddenExcluded = LauncherApplicationVisibilityPolicy.applications(
            in: [visible, hidden],
            hiddenApplicationPaths: hiddenPaths,
            showsHiddenApplications: false,
        )
        #expect(
            LauncherContentPolicy.visibleCatalog(
                applications: hiddenExcluded,
                suggestions: [],
                query: "cal",
            ) == [visible],
        )

        let hiddenIncluded = LauncherApplicationVisibilityPolicy.applications(
            in: [visible, hidden],
            hiddenApplicationPaths: hiddenPaths,
            showsHiddenApplications: true,
        )
        #expect(
            LauncherContentPolicy.visibleCatalog(
                applications: hiddenIncluded,
                suggestions: [],
                query: "cal",
            ) == [hidden, visible],
        )
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
}
