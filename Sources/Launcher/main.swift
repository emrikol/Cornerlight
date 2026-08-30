/*
 THESIS: App launching should be a direct view of installed apps, never a side effect of an index.
 UI: The installed macOS 26.6 Spotlight launcher owns every visible component and transition.
 STORY: Enter the corner, see every app, type only if needed, then click or press Return.
 DATA: Cornerlight replaces only Spotlight's indexed app sections with directly enumerated bundle URLs.
 */

// A single source file is intentional: this is a small, single-purpose utility.
// swiftlint:disable file_length

import AppKit
import CoreGraphics
import CoreServices
import Darwin
import ObjectiveC.runtime
import OSLog
import ServiceManagement
import Sparkle

private enum CornerlightTrace {
    static let lifecycle = Logger(subsystem: "com.emrikol.Cornerlight", category: "Lifecycle")
}

enum LauncherProcessLifetimePolicy {
    static let automaticTerminationReason = "Cornerlight owns the Hot Corner event source"

    static func makeResident(
        disableAutomaticTermination: (String) -> Void,
    ) {
        disableAutomaticTermination(automaticTerminationReason)
    }
}

// MARK: - App catalog

struct ApplicationRecord: Equatable, Sendable {
    let name: String
    let url: URL
    let bundleIdentifier: String?
    let searchName: String

    init(
        name: String,
        url: URL,
        bundleIdentifier: String? = nil,
    ) {
        self.name = name
        self.url = url
        self.bundleIdentifier = bundleIdentifier
        searchName = Self.normalize(name)
    }

    func matchRank(for normalizedQuery: String) -> Int? {
        guard !normalizedQuery.isEmpty else { return 0 }
        if searchName.hasPrefix(normalizedQuery) {
            return 0
        }
        if searchName.split(separator: " ").contains(where: { $0.hasPrefix(normalizedQuery) }) {
            return 1
        }
        if searchName.contains(normalizedQuery) {
            return 2
        }
        return nil
    }

    static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current,
        )
    }
}

enum ApplicationCatalog {
    static var defaultRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Applications", directoryHint: .isDirectory),
        ]
    }

    static func scan(
        roots: [URL] = defaultRoots,
        isCancelled: @Sendable () -> Bool = { false },
    ) -> [ApplicationRecord] {
        let fileManager = FileManager.default
        var seenPaths = Set<String>()
        var applications: [ApplicationRecord] = []
        applications.reserveCapacity(192)

        for root in roots {
            guard !isCancelled() else { return [] }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
            ) else { continue }

            for case let url as URL in enumerator {
                guard !isCancelled() else { return [] }
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                    continue
                }

                enumerator.skipDescendants()
                let path = url.standardizedFileURL.path
                guard seenPaths.insert(path).inserted else { continue }

                var name = fileManager.displayName(atPath: path)
                if name.lowercased().hasSuffix(".app") {
                    name.removeLast(4)
                }
                guard !name.isEmpty else { continue }
                applications.append(
                    ApplicationRecord(
                        name: name,
                        url: url,
                        bundleIdentifier: bundleIdentifier(for: url),
                    ),
                )
            }
        }

        return applications.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            if order == .orderedSame {
                return $0.url.path < $1.url.path
            }
            return order == .orderedAscending
        }
    }

    static func filter(
        _ applications: [ApplicationRecord],
        query: String,
    ) -> [ApplicationRecord] {
        let normalizedQuery = ApplicationRecord.normalize(
            query.trimmingCharacters(in: .whitespacesAndNewlines),
        )
        guard !normalizedQuery.isEmpty else { return applications }

        return applications.compactMap { application -> (ApplicationRecord, Int)? in
            guard let rank = application.matchRank(for: normalizedQuery) else { return nil }
            return (application, rank)
        }
        .sorted {
            if $0.1 != $1.1 {
                return $0.1 < $1.1
            }
            return $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending
        }
        .map(\.0)
    }

    private static func bundleIdentifier(for applicationURL: URL) -> String? {
        let infoURL = applicationURL
            .appending(path: "Contents", directoryHint: .isDirectory)
            .appending(path: "Info.plist", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: infoURL, options: .mappedIfSafe),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return info["CFBundleIdentifier"] as? String
    }
}

struct ApplicationCatalogRefreshState {
    struct Completion: Equatable {
        let acceptsResult: Bool
        let nextRevision: Int?
    }

    private(set) var requestedRevision = 0
    private(set) var inFlightRevision: Int?

    mutating func requestRefresh() -> Int? {
        requestedRevision &+= 1
        guard inFlightRevision == nil else { return nil }
        inFlightRevision = requestedRevision
        return requestedRevision
    }

    mutating func finish(revision: Int) -> Completion {
        guard inFlightRevision == revision else {
            return Completion(acceptsResult: false, nextRevision: nil)
        }
        inFlightRevision = nil
        guard revision != requestedRevision else {
            return Completion(acceptsResult: true, nextRevision: nil)
        }
        inFlightRevision = requestedRevision
        return Completion(acceptsResult: false, nextRevision: requestedRevision)
    }
}

/// Maintains one in-memory catalog. Scans run at startup and after FSEvents changes,
/// never as part of presenting the launcher.
@MainActor
final class ApplicationCatalogService {
    typealias Scan = @Sendable (@Sendable () -> Bool) -> [ApplicationRecord]

    var onUpdate: (([ApplicationRecord]) -> Void)?
    private(set) var applications: [ApplicationRecord] = []

    private let scan: Scan
    private var refreshState = ApplicationCatalogRefreshState()
    private var scanTask: Task<[ApplicationRecord], Never>?
    private var isRunning = false

    init(
        scan: @escaping Scan = { isCancelled in
            ApplicationCatalog.scan(isCancelled: isCancelled)
        },
    ) {
        self.scan = scan
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        requestRefresh()
    }

    func applicationRootsDidChange() {
        guard isRunning else { return }
        requestRefresh(cancellingInFlightScan: true)
    }

    func stop() {
        isRunning = false
        scanTask?.cancel()
        scanTask = nil
        onUpdate = nil
    }

    private func requestRefresh(cancellingInFlightScan: Bool = false) {
        guard let revision = refreshState.requestRefresh() else {
            if cancellingInFlightScan {
                scanTask?.cancel()
            }
            return
        }
        beginScan(revision: revision)
    }

    private func beginScan(revision: Int) {
        let scan = scan
        let task = Task.detached(priority: .utility) {
            scan { Task<Never, Never>.isCancelled }
        }
        scanTask = task
        Task { [weak self] in
            let result = await task.value
            guard let self, isRunning else { return }
            scanTask = nil
            let completion = refreshState.finish(revision: revision)
            if completion.acceptsResult, !task.isCancelled {
                applications = result
                onUpdate?(result)
            }
            if let nextRevision = completion.nextRevision {
                beginScan(revision: nextRevision)
            }
        }
    }
}

/// FSEvents coalesces recursive changes to the application roots. The callback only
/// invalidates the in-memory catalog; it performs no directory work itself.
@MainActor
private final class ApplicationCatalogDirectoryMonitor {
    private let paths: [String]
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?

    init(roots: [URL], onChange: @escaping () -> Void) {
        paths = roots.map(\.standardizedFileURL.path)
        self.onChange = onChange
    }

    func start() -> Bool {
        guard stream == nil else { return true }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil,
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<ApplicationCatalogDirectoryMonitor>
                .fromOpaque(info)
                .takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.onChange()
            }
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagIgnoreSelf,
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1,
            flags,
        ) else { return false }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

enum LauncherContentPolicy {
    static func visibleCatalog(
        applications: [ApplicationRecord],
        suggestions: [ApplicationRecord],
        query: String,
    ) -> [ApplicationRecord] {
        let candidates: [ApplicationRecord]
        if query.isEmpty {
            let suggestionPaths = Set(suggestions.map(\.url.standardizedFileURL.path))
            candidates = applications.filter {
                !suggestionPaths.contains($0.url.standardizedFileURL.path)
            }
        } else {
            candidates = applications
        }
        return ApplicationCatalog.filter(candidates, query: query)
    }
}

enum LauncherSuggestionPolicy {
    static let maximumCount = 7

    static func applications(
        in catalog: [ApplicationRecord],
        matching bundleIdentifiers: [String],
    ) -> [ApplicationRecord] {
        var byIdentifier: [String: ApplicationRecord] = [:]
        for application in catalog {
            guard let identifier = application.bundleIdentifier,
                  byIdentifier[identifier] == nil
            else { continue }
            byIdentifier[identifier] = application
        }
        var seen = Set<String>()
        return bundleIdentifiers.compactMap { identifier in
            guard seen.insert(identifier).inserted else { return nil }
            return byIdentifier[identifier]
        }
        .prefix(maximumCount)
        .map(\.self)
    }

    static func applications(
        in catalog: [ApplicationRecord],
        pinnedApplicationPaths: [String],
        matching bundleIdentifiers: [String],
    ) -> [ApplicationRecord] {
        var byPath: [String: ApplicationRecord] = [:]
        var byIdentifier: [String: ApplicationRecord] = [:]
        for application in catalog {
            let path = application.url.standardizedFileURL.path
            if byPath[path] == nil {
                byPath[path] = application
            }
            if let identifier = application.bundleIdentifier,
               byIdentifier[identifier] == nil {
                byIdentifier[identifier] = application
            }
        }

        var seenPaths = Set<String>()
        var suggestions: [ApplicationRecord] = []
        suggestions.reserveCapacity(maximumCount)
        for path in pinnedApplicationPaths {
            guard suggestions.count < maximumCount,
                  seenPaths.insert(path).inserted,
                  let application = byPath[path]
            else { continue }
            suggestions.append(application)
        }
        for identifier in bundleIdentifiers {
            guard suggestions.count < maximumCount,
                  let application = byIdentifier[identifier],
                  seenPaths.insert(application.url.standardizedFileURL.path).inserted
            else { continue }
            suggestions.append(application)
        }
        return suggestions
    }

    static func orderedBundleIdentifiers(
        predicted: [String],
        recent: [String],
    ) -> [String] {
        var seen = Set<String>()
        return (predicted + recent).filter { seen.insert($0).inserted }
    }

    static func prioritizedBundleIdentifiers(
        localRecents: [String],
        systemSuggestions: [String],
    ) -> [String] {
        var seen = Set<String>()
        return (localRecents + systemSuggestions).filter { seen.insert($0).inserted }
    }
}

enum LauncherRecentApplicationPolicy {
    static let maximumStoredCount = 32

    static func recording(_ bundleIdentifier: String, in history: [String]) -> [String] {
        guard !bundleIdentifier.isEmpty else { return history }
        return ([bundleIdentifier] + history.filter { $0 != bundleIdentifier })
            .prefix(maximumStoredCount)
            .map(\.self)
    }
}

enum LauncherPinnedApplicationPolicy {
    static func settingPinned(
        _ pinned: Bool,
        applicationPath: String,
        in paths: [String],
    ) -> [String] {
        guard !applicationPath.isEmpty else { return paths }
        if !pinned {
            return paths.filter { $0 != applicationPath }
        }
        guard !paths.contains(applicationPath),
              paths.count < LauncherSuggestionPolicy.maximumCount
        else { return paths }
        return paths + [applicationPath]
    }

    static func moving(
        applicationPath: String,
        toVisibleInsertionIndex insertionIndex: Int,
        visibleApplicationPaths: [String],
        in paths: [String],
    ) -> [String] {
        guard paths.contains(applicationPath),
              visibleApplicationPaths.contains(applicationPath)
        else { return paths }

        let destination = min(max(insertionIndex, 0), visibleApplicationPaths.count)
        let anchor = destination < visibleApplicationPaths.count
            ? visibleApplicationPaths[destination]
            : nil
        if anchor == applicationPath {
            return paths
        }

        var reordered = paths.filter { $0 != applicationPath }
        if let anchor,
           let anchorIndex = reordered.firstIndex(of: anchor) {
            reordered.insert(applicationPath, at: anchorIndex)
            return reordered
        }

        let visibleWithoutSource = visibleApplicationPaths.filter { $0 != applicationPath }
        if let lastVisiblePath = visibleWithoutSource.last,
           let lastVisibleIndex = reordered.firstIndex(of: lastVisiblePath) {
            reordered.insert(applicationPath, at: lastVisibleIndex + 1)
        }
        return reordered
    }

    static func removingUnavailable(
        from paths: [String],
        availableApplicationPaths: Set<String>,
    ) -> [String] {
        paths.filter(availableApplicationPaths.contains)
    }
}

enum LauncherPinnedDropPolicy {
    static let indicatorWidth: CGFloat = 2

    static func insertionIndex(at point: NSPoint, itemFrames: [NSRect]) -> Int? {
        guard !itemFrames.isEmpty,
              itemFrames.contains(where: { point.y >= $0.minY && point.y <= $0.maxY })
        else { return nil }

        for (index, frame) in itemFrames.enumerated() where point.x < frame.midX {
            return index
        }
        return itemFrames.count
    }

    static func indicatorFrame(
        at insertionIndex: Int,
        itemFrames: [NSRect],
    ) -> NSRect? {
        guard !itemFrames.isEmpty,
              (0 ... itemFrames.count).contains(insertionIndex)
        else { return nil }

        let boundaryX = switch insertionIndex {
        case 0:
            itemFrames[0].minX
        case itemFrames.count:
            itemFrames[itemFrames.count - 1].maxX
        default:
            (itemFrames[insertionIndex - 1].maxX + itemFrames[insertionIndex].minX) / 2
        }
        let minY = itemFrames.map(\.minY).min() ?? 0
        let maxY = itemFrames.map(\.maxY).max() ?? 0
        return NSRect(
            x: boundaryX - indicatorWidth / 2,
            y: minY + 8,
            width: indicatorWidth,
            height: max(maxY - minY - 16, 0),
        )
    }
}

enum LauncherApplicationVisibilityPolicy {
    static func applications(
        in applications: [ApplicationRecord],
        hiddenApplicationPaths: Set<String>,
        showsHiddenApplications: Bool,
    ) -> [ApplicationRecord] {
        guard !showsHiddenApplications, !hiddenApplicationPaths.isEmpty else {
            return applications
        }
        return applications.filter {
            !hiddenApplicationPaths.contains($0.url.standardizedFileURL.path)
        }
    }
}

@MainActor
final class LauncherHiddenApplicationStore {
    private static let defaultsKey = "hiddenApplicationPaths"
    private static let showsHiddenApplicationsDefaultsKey = "showsHiddenApplications"

    private let defaults: UserDefaults
    private(set) var hiddenApplicationPaths: Set<String>
    private(set) var showsHiddenApplications: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hiddenApplicationPaths = Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
        showsHiddenApplications = defaults.bool(
            forKey: Self.showsHiddenApplicationsDefaultsKey,
        )
    }

    func isHidden(_ applicationURL: URL) -> Bool {
        hiddenApplicationPaths.contains(applicationURL.standardizedFileURL.path)
    }

    func setHidden(_ hidden: Bool, applicationURL: URL) {
        let path = applicationURL.standardizedFileURL.path
        if hidden {
            hiddenApplicationPaths.insert(path)
        } else {
            hiddenApplicationPaths.remove(path)
        }
        defaults.set(hiddenApplicationPaths.sorted(), forKey: Self.defaultsKey)
    }

    func setShowsHiddenApplications(_ showsHiddenApplications: Bool) {
        self.showsHiddenApplications = showsHiddenApplications
        defaults.set(
            showsHiddenApplications,
            forKey: Self.showsHiddenApplicationsDefaultsKey,
        )
    }
}

@MainActor
final class LauncherRecentApplicationStore {
    private static let defaultsKey = "recentApplicationBundleIdentifiers"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var bundleIdentifiers: [String] {
        defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }

    func record(bundleIdentifier: String) {
        let current = bundleIdentifiers
        let next = LauncherRecentApplicationPolicy.recording(bundleIdentifier, in: current)
        guard next != current else { return }
        defaults.set(next, forKey: Self.defaultsKey)
    }
}

@MainActor
final class LauncherPinnedApplicationStore {
    private static let defaultsKey = "pinnedApplicationPaths"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var applicationPaths: [String] {
        defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }

    func isPinned(_ applicationURL: URL) -> Bool {
        applicationPaths.contains(applicationURL.standardizedFileURL.path)
    }

    var canPinAnotherApplication: Bool {
        applicationPaths.count < LauncherSuggestionPolicy.maximumCount
    }

    func setPinned(_ pinned: Bool, applicationURL: URL) {
        let current = applicationPaths
        let next = LauncherPinnedApplicationPolicy.settingPinned(
            pinned,
            applicationPath: applicationURL.standardizedFileURL.path,
            in: current,
        )
        guard next != current else { return }
        defaults.set(next, forKey: Self.defaultsKey)
    }

    func move(
        applicationURL: URL,
        toVisibleInsertionIndex insertionIndex: Int,
        visibleApplicationURLs: [URL],
    ) {
        let current = applicationPaths
        let next = LauncherPinnedApplicationPolicy.moving(
            applicationPath: applicationURL.standardizedFileURL.path,
            toVisibleInsertionIndex: insertionIndex,
            visibleApplicationPaths: visibleApplicationURLs.map(\.standardizedFileURL.path),
            in: current,
        )
        guard next != current else { return }
        defaults.set(next, forKey: Self.defaultsKey)
    }

    func removeUnavailableApplications(in catalog: [ApplicationRecord]) {
        let current = applicationPaths
        let next = LauncherPinnedApplicationPolicy.removingUnavailable(
            from: current,
            availableApplicationPaths: Set(catalog.map(\.url.standardizedFileURL.path)),
        )
        guard next != current else { return }
        defaults.set(next, forKey: Self.defaultsKey)
    }
}

@MainActor
final class LauncherRecentApplicationObserver: NSObject {
    private let store: LauncherRecentApplicationStore
    private var isObserving = false

    init(store: LauncherRecentApplicationStore) {
        self.store = store
        super.init()
    }

    func start() {
        guard !isObserving else { return }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
        )
        isObserving = true
    }

    func stop() {
        guard isObserving else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        isObserving = false
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication,
            let identifier = application.bundleIdentifier,
            identifier != Bundle.main.bundleIdentifier,
            application.bundleURL?.pathExtension.caseInsensitiveCompare("app") == .orderedSame
        else { return }
        store.record(bundleIdentifier: identifier)
    }
}

@MainActor
enum SpotlightApplicationSuggestionService {
    private typealias CachedRequest = @convention(c) (
        AnyObject,
        Selector,
        UInt,
    ) -> Unmanaged<AnyObject>?

    private static let frameworkHandle = dlopen(
        "/System/Library/PrivateFrameworks/AppPredictionClient.framework/Versions/A/AppPredictionClient",
        RTLD_LAZY | RTLD_LOCAL,
    )
    private static let cachedSelector = NSSelectorFromString(
        "getDirectoryResponseFromCacheWithMaxNumberOfAppsToPredict:",
    )
    private static let client: AnyObject? = {
        _ = frameworkHandle
        guard let clientClass = NSClassFromString("ATXAppDirectoryClient") else { return nil }
        return (clientClass as AnyObject)
            .perform(NSSelectorFromString("sharedInstance"))?
            .takeUnretainedValue()
    }()

    static func cachedBundleIdentifiers(
        maximumCount: Int = LauncherSuggestionPolicy.maximumCount,
    ) -> [String] {
        guard let client, client.responds(to: cachedSelector) else { return [] }
        let request = unsafeBitCast(client.method(for: cachedSelector), to: CachedRequest.self)
        let response = request(client, cachedSelector, UInt(maximumCount))?.takeUnretainedValue()
        let object = response as? NSObject
        return LauncherSuggestionPolicy.orderedBundleIdentifiers(
            predicted: object?.value(forKey: "predictedApps") as? [String] ?? [],
            recent: object?.value(forKey: "recentApps") as? [String] ?? [],
        )
    }
}

// MARK: - Hot corner

enum LauncherHotCorner: String, CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var displayName: String {
        switch self {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        }
    }

    fileprivate var dockPreferenceKey: String {
        switch self {
        case .topLeft: "wvous-tl-corner"
        case .topRight: "wvous-tr-corner"
        case .bottomLeft: "wvous-bl-corner"
        case .bottomRight: "wvous-br-corner"
        }
    }
}

enum LauncherHotCornerAvailability {
    static func availableCorners(
        systemActions: [LauncherHotCorner: Int],
    ) -> [LauncherHotCorner] {
        LauncherHotCorner.allCases.filter { corner in
            (systemActions[corner] ?? 0) <= 1
        }
    }

    static func effectiveCorner(
        preferred: LauncherHotCorner,
        available: [LauncherHotCorner],
    ) -> LauncherHotCorner? {
        available.contains(preferred) ? preferred : available.first
    }
}

final class LauncherHotCornerStore {
    private static let defaultsKey = "hotCorner"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedCorner: LauncherHotCorner {
        get {
            guard let rawValue = defaults.string(forKey: Self.defaultsKey),
                  let corner = LauncherHotCorner(rawValue: rawValue)
            else { return .topLeft }
            return corner
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.defaultsKey)
        }
    }
}

private enum LauncherSystemHotCornerAssignments {
    static func availableCorners() -> [LauncherHotCorner] {
        let dockApplicationIdentifier = "com.apple.dock" as CFString
        _ = CFPreferencesAppSynchronize(dockApplicationIdentifier)
        let actions = Dictionary(uniqueKeysWithValues: LauncherHotCorner.allCases.map { corner in
            let value = CFPreferencesCopyAppValue(
                corner.dockPreferenceKey as CFString,
                dockApplicationIdentifier,
            ) as? NSNumber
            return (corner, value?.intValue ?? 0)
        })
        return LauncherHotCornerAvailability.availableCorners(systemActions: actions)
    }
}

private struct SkyLightHotCornerAPI {
    typealias NewConnection = @convention(c) (
        UnsafeRawPointer?,
        UnsafeMutablePointer<UInt32>,
    ) -> Int32
    typealias ReleaseConnection = @convention(c) (UInt32) -> Int32
    typealias GetEventPort = @convention(c) (
        UInt32,
        UnsafeMutablePointer<mach_port_t>,
    ) -> Int32
    typealias NewRegionWithRectList = @convention(c) (
        UnsafePointer<CGRect>?,
        UInt32,
        UnsafeMutablePointer<OpaquePointer?>,
    ) -> Int32
    typealias ReleaseRegion = @convention(c) (OpaquePointer?) -> Void
    typealias DisplayStatusQuery = @convention(c) (CGDirectDisplayID, UInt32) -> Int32
    typealias SetBackgroundEventMask = @convention(c) (
        UInt32,
        UInt64,
        OpaquePointer?,
    ) -> Int32
    typealias CreateNextEvent = @convention(c) (UInt32) -> OpaquePointer?

    let handle: UnsafeMutableRawPointer
    let newConnection: NewConnection
    let releaseConnection: ReleaseConnection
    let getEventPort: GetEventPort
    let newRegionWithRectList: NewRegionWithRectList
    let releaseRegion: ReleaseRegion
    let displayStatusQuery: DisplayStatusQuery
    let setBackgroundEventMask: SetBackgroundEventMask
    let createNextEvent: CreateNextEvent

    // Symbol loading is intentionally centralized so the private boundary is obvious.
    // swiftlint:disable:next function_body_length
    init?() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard
            let newConnection = Self.function(
                "CGSNewConnection",
                in: handle,
                as: NewConnection.self,
            ),
            let releaseConnection = Self.function(
                "CGSReleaseConnection",
                in: handle,
                as: ReleaseConnection.self,
            ),
            let getEventPort = Self.function(
                "CGSGetEventPort",
                in: handle,
                as: GetEventPort.self,
            ),
            let newRegionWithRectList = Self.function(
                "CGSNewRegionWithRectList",
                in: handle,
                as: NewRegionWithRectList.self,
            ),
            let releaseRegion = Self.function(
                "CGSRegionRelease",
                in: handle,
                as: ReleaseRegion.self,
            ),
            let displayStatusQuery = Self.function(
                "CGSDisplayStatusQuery",
                in: handle,
                as: DisplayStatusQuery.self,
            ),
            let setBackgroundEventMask = Self.function(
                "CGSSetBackgroundEventMaskAndShape",
                in: handle,
                as: SetBackgroundEventMask.self,
            ),
            let createNextEvent = Self.function(
                "CGEventCreateNextEvent",
                in: handle,
                as: CreateNextEvent.self,
            )
        else {
            dlclose(handle)
            return nil
        }

        self.handle = handle
        self.newConnection = newConnection
        self.releaseConnection = releaseConnection
        self.getEventPort = getEventPort
        self.newRegionWithRectList = newRegionWithRectList
        self.releaseRegion = releaseRegion
        self.displayStatusQuery = displayStatusQuery
        self.setBackgroundEventMask = setBackgroundEventMask
        self.createNextEvent = createNextEvent
    }

    func close() {
        dlclose(handle)
    }

    private static func function<Function>(
        _ name: String,
        in handle: UnsafeMutableRawPointer,
        as _: Function.Type,
    ) -> Function? {
        guard let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: Function.self)
    }
}

@MainActor
private final class HotCornerController: NSObject {
    private static let backgroundEventMask: UInt64 = 0x302

    private let corner: LauncherHotCorner
    private let onEnter: () -> Void
    private var api: SkyLightHotCornerAPI?
    private var connectionID: UInt32 = 0
    private var region: OpaquePointer?
    private var eventPort: CFMachPort?
    private var eventRunLoopSource: CFRunLoopSource?
    private var entryGate = HotCornerEntryGate()
    private var cornerRectangles: [CGRect] = []

    init?(corner: LauncherHotCorner, onEnter: @escaping () -> Void) {
        self.corner = corner
        self.onEnter = onEnter
        super.init()

        guard let api = SkyLightHotCornerAPI() else {
            Self.report("SkyLight hot-corner functions are unavailable")
            return nil
        }
        self.api = api

        guard api.newConnection(nil, &connectionID) == 0 else {
            Self.report("could not create a WindowServer connection")
            shutdown()
            return nil
        }

        var eventPortName: mach_port_t = 0
        guard api.getEventPort(connectionID, &eventPortName) == 0 else {
            Self.report("could not obtain the WindowServer event port")
            shutdown()
            return nil
        }

        guard installEventSource(portName: eventPortName) else {
            Self.report("could not create the WindowServer event source")
            shutdown()
            return nil
        }

        guard installRegion() else {
            shutdown()
            return nil
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil,
        )
    }

    func shutdown() {
        if let api {
            if connectionID != 0 {
                _ = api.setBackgroundEventMask(connectionID, 0, nil)
            }
            if let eventRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), eventRunLoopSource, .defaultMode)
                self.eventRunLoopSource = nil
            }
            if let eventPort {
                CFMachPortInvalidate(eventPort)
                self.eventPort = nil
            }
            if let region {
                api.releaseRegion(region)
                self.region = nil
            }
            if connectionID != 0 {
                _ = api.releaseConnection(connectionID)
                connectionID = 0
            }
            api.close()
            self.api = nil
        }
    }

    @objc private func screenParametersChanged() {
        _ = installRegion()
    }

    private func installEventSource(portName: mach_port_t) -> Bool {
        var context = CFMachPortContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil,
        )
        guard let eventPort = CFMachPortCreateWithPort(
            kCFAllocatorDefault,
            portName,
            { _, _, _, info in
                guard let info else { return }
                let controller = Unmanaged<HotCornerController>
                    .fromOpaque(info)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    controller.drainEvents()
                }
            },
            &context,
            nil,
        ), let eventRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventPort,
            0,
        ) else {
            return false
        }
        self.eventPort = eventPort
        self.eventRunLoopSource = eventRunLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), eventRunLoopSource, .defaultMode)
        return true
    }

    private func installRegion() -> Bool {
        guard let api else { return false }
        let rectangles = NSScreen.screens
            .compactMap { Self.cornerRectangle(for: $0, corner: corner) }
            .filter { Self.isExposed($0, using: api) }
        guard !rectangles.isEmpty else {
            _ = api.setBackgroundEventMask(connectionID, 0, nil)
            if let region {
                api.releaseRegion(region)
                self.region = nil
            }
            cornerRectangles = []
            Self.report("no active display has an exposed \(corner.displayName.lowercased()) corner")
            return false
        }

        var nextRegion: OpaquePointer?
        let regionResult = rectangles.withUnsafeBufferPointer { buffer in
            api.newRegionWithRectList(
                buffer.baseAddress,
                UInt32(buffer.count),
                &nextRegion,
            )
        }
        guard regionResult == 0, let nextRegion else {
            Self.report("could not create the WindowServer corner region")
            return false
        }

        guard api.setBackgroundEventMask(
            connectionID,
            Self.backgroundEventMask,
            nextRegion,
        ) == 0 else {
            api.releaseRegion(nextRegion)
            Self.report("could not register the WindowServer corner region")
            return false
        }

        if let region {
            api.releaseRegion(region)
        }
        region = nextRegion
        cornerRectangles = rectangles
        entryGate.rebuild(pointerIsInside: Self.pointerIsInside(rectangles))
        return true
    }

    private func drainEvents() {
        guard let api else { return }
        while let pointer = api.createNextEvent(connectionID) {
            let event = Unmanaged<CGEvent>
                .fromOpaque(UnsafeRawPointer(pointer))
                .takeRetainedValue()
            let pointerIsInside = cornerRectangles.contains { $0.contains(event.location) }
            let wasArmed = entryGate.isArmed
            let shouldInvoke = entryGate.consume(
                eventType: event.type.rawValue,
                pointerIsInside: pointerIsInside,
            )
            let eventType = event.type.rawValue
            let isArmed = entryGate.isArmed
            CornerlightTrace.lifecycle.debug(
                "corner e=\(eventType, privacy: .public) run=\(shouldInvoke, privacy: .public)",
            )
            CornerlightTrace.lifecycle.debug(
                "corner arm=\(wasArmed, privacy: .public)->\(isArmed, privacy: .public)",
            )
            if shouldInvoke, HotCornerInvocationPolicy.shouldInvoke(
                screenLocked: Self.isScreenLocked,
                mouseButtonPressed: Self.isMouseButtonPressed,
            ) {
                onEnter()
            }
        }
    }

    private static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private static var isMouseButtonPressed: Bool {
        (0 ... 4).contains { button in
            CGEventSource.buttonState(
                .combinedSessionState,
                button: CGMouseButton(rawValue: UInt32(button))!,
            )
        }
    }

    private static func pointerIsInside(_ rectangles: [CGRect]) -> Bool {
        guard let event = CGEvent(source: nil) else { return false }
        return rectangles.contains { $0.contains(event.location) }
    }

    private static func cornerRectangle(
        for screen: NSScreen,
        corner: LauncherHotCorner,
    ) -> CGRect? {
        guard
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber
        else {
            return nil
        }
        let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        let origin = switch corner {
        case .topLeft:
            CGPoint(x: bounds.minX - 1, y: bounds.minY - 1)
        case .topRight:
            CGPoint(x: bounds.maxX - 2, y: bounds.minY - 1)
        case .bottomLeft:
            CGPoint(x: bounds.minX - 1, y: bounds.maxY - 2)
        case .bottomRight:
            CGPoint(x: bounds.maxX - 2, y: bounds.maxY - 2)
        }
        return CGRect(origin: origin, size: CGSize(width: 3, height: 3))
    }

    private static func isExposed(
        _ rectangle: CGRect,
        using api: SkyLightHotCornerAPI,
    ) -> Bool {
        var displayCount: UInt32 = 0
        guard CGGetDisplaysWithRect(rectangle, 0, nil, &displayCount) == .success else {
            return false
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let result = displayIDs.withUnsafeMutableBufferPointer { buffer in
            CGGetDisplaysWithRect(
                rectangle,
                displayCount,
                buffer.baseAddress,
                &displayCount,
            )
        }
        guard result == .success else { return false }
        let usableDisplayCount = displayIDs
            .prefix(Int(displayCount))
            .lazy
            .filter { api.displayStatusQuery($0, 9) == 0 }
            .count
        return usableDisplayCount <= 1
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write(Data("Hot corner unavailable: \(message)\n".utf8))
    }
}

struct HotCornerEntryGate {
    static let enteredEventType: UInt32 = 8
    static let exitedEventType: UInt32 = 9

    private(set) var isArmed = true

    mutating func rebuild(pointerIsInside: Bool) {
        isArmed = !pointerIsInside
    }

    mutating func consume(eventType: UInt32, pointerIsInside: Bool = false) -> Bool {
        switch eventType {
        case Self.enteredEventType where isArmed:
            isArmed = false
            return true
        case Self.exitedEventType where !pointerIsInside:
            isArmed = true
            return false
        default:
            return false
        }
    }
}

enum HotCornerInvocationPolicy {
    static func shouldInvoke(screenLocked: Bool, mouseButtonPressed: Bool) -> Bool {
        !screenLocked && !mouseButtonPressed
    }
}

// MARK: - Launcher interface

@MainActor
enum SpotlightExecutableRuntime {
    static let executablePath = "/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight"

    private static let dependencyPaths = [
        "/System/Library/PrivateFrameworks/SearchFoundation.framework/Versions/A/SearchFoundation",
        "/System/Library/PrivateFrameworks/SearchUI.framework/Versions/A/SearchUI",
        "/System/Library/PrivateFrameworks/SpotlightUIShared.framework/Versions/A/SpotlightUIShared",
        "/System/Library/PrivateFrameworks/SpotlightUIServices.framework/Versions/A/SpotlightUIServices",
        "/System/Library/PrivateFrameworks/AppPredictionClient.framework/Versions/A/AppPredictionClient",
    ]

    private static var handles: [UnsafeMutableRawPointer] = []
    private static var attemptedLoad = false

    static var isLoaded: Bool {
        if !attemptedLoad {
            attemptedLoad = true
            for path in dependencyPaths + [executablePath] {
                if let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) {
                    handles.append(handle)
                }
            }
        }
        return NSClassFromString("_TtC17SpotlightAppMacOS20SearchViewController") != nil &&
            NSClassFromString("_TtC17SpotlightAppMacOS27SearchResultsViewController") != nil
    }

    static func sharedApplication() -> NSApplication {
        guard isLoaded,
              let applicationClass = NSClassFromString("SPApplication"),
              let application = (applicationClass as AnyObject)
              .perform(NSSelectorFromString("sharedApplication"))?
              .takeUnretainedValue() as? NSApplication,
              NSStringFromClass(type(of: application)) == "SPApplication"
        else {
            fatalError("macOS 26.6 Spotlight application runtime is unavailable")
        }
        return application
    }
}

@MainActor
private final class SpotlightNativeSectionsHookBridge: NSObject {
    weak var owner: SpotlightNativeLauncherUI?
}

@MainActor
private enum SpotlightNativeSectionsHook {
    private typealias SectionsSetter = @convention(c) (
        AnyObject,
        Selector,
        NSArray,
    ) -> Void

    private static let associationKey = UnsafeRawPointer(
        Unmanaged.passRetained(NSObject()).toOpaque(),
    )
    private static var originalImplementation: IMP?

    static func install(on resultsController: AnyObject, owner: SpotlightNativeLauncherUI) -> Bool {
        guard let resultClass = NSClassFromString(
            "_TtC17SpotlightAppMacOS27SearchResultsViewController",
        ),
            let method = class_getInstanceMethod(
                resultClass,
                NSSelectorFromString("setSections:"),
            )
        else { return false }

        if originalImplementation == nil {
            let original = method_getImplementation(method)
            originalImplementation = original
            let replacement: @convention(block) (AnyObject, NSArray) -> Void = { resultsController, incomingSections in
                MainActor.assumeIsolated {
                    let bridge = objc_getAssociatedObject(
                        resultsController,
                        associationKey,
                    ) as? SpotlightNativeSectionsHookBridge
                    if let owner = bridge?.owner {
                        owner.nativeSectionsWereProposed()
                    } else {
                        unsafeBitCast(original, to: SectionsSetter.self)(
                            resultsController,
                            NSSelectorFromString("setSections:"),
                            incomingSections,
                        )
                    }
                }
            }
            class_replaceMethod(
                resultClass,
                NSSelectorFromString("setSections:"),
                imp_implementationWithBlock(replacement),
                method_getTypeEncoding(method),
            )
        }

        let bridge = SpotlightNativeSectionsHookBridge()
        bridge.owner = owner
        objc_setAssociatedObject(
            resultsController,
            associationKey,
            bridge,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC,
        )
        return true
    }

    static func setEnumeratedSections(_ sections: [AnyObject], on resultsController: AnyObject) {
        guard let originalImplementation else { return }
        unsafeBitCast(originalImplementation, to: SectionsSetter.self)(
            resultsController,
            NSSelectorFromString("setSections:"),
            sections as NSArray,
        )
    }
}

@MainActor
private enum SpotlightNativeIndexingStatusHook {
    private typealias EligibilitySetter = @convention(c) (
        AnyObject,
        Selector,
        Bool,
    ) -> Void

    private static var originalImplementation: IMP?

    static func install(on indexingView: AnyObject) -> Bool {
        guard NSStringFromClass(type(of: indexingView)) == "SPSpotlightIndexingView",
              let indexingViewClass = NSClassFromString("SPSpotlightIndexingView"),
              let method = class_getInstanceMethod(
                  indexingViewClass,
                  NSSelectorFromString("setEligibleToView:"),
              )
        else { return false }

        if originalImplementation == nil {
            let original = method_getImplementation(method)
            originalImplementation = original
            let replacement: @convention(block) (AnyObject, Bool) -> Void = { indexingView, _ in
                MainActor.assumeIsolated {
                    unsafeBitCast(original, to: EligibilitySetter.self)(
                        indexingView,
                        NSSelectorFromString("setEligibleToView:"),
                        false,
                    )
                }
            }
            class_replaceMethod(
                indexingViewClass,
                NSSelectorFromString("setEligibleToView:"),
                imp_implementationWithBlock(replacement),
                method_getTypeEncoding(method),
            )
        }

        guard let originalImplementation else { return false }
        unsafeBitCast(originalImplementation, to: EligibilitySetter.self)(
            indexingView,
            NSSelectorFromString("setEligibleToView:"),
            false,
        )
        return true
    }
}

@MainActor
private final class SpotlightNativeSearchFieldObserver: NSObject {
    weak var owner: SpotlightNativeLauncherUI?
    weak var searchField: NSSearchField?

    @objc func textDidChange(_ notification: Notification) {
        guard let searchField,
              let source = notification.object as AnyObject?,
              source === searchField || source === searchField.currentEditor()
        else { return }
        owner?.nativeQueryDidChange()
    }
}

@MainActor
private final class SpotlightNativePanelHookBridge: NSObject {
    weak var owner: SpotlightNativeLauncherUI?
}

@MainActor
private enum SpotlightNativePanelHook {
    private typealias OrderOut = @convention(c) (AnyObject, Selector, AnyObject?) -> Void

    private static let associationKey = UnsafeRawPointer(
        Unmanaged.passRetained(NSObject()).toOpaque(),
    )
    private static var orderOutOriginalImplementation: IMP?

    static func install(on panel: NSPanel, owner: SpotlightNativeLauncherUI) -> Bool {
        guard let panelClass = NSClassFromString("SPSpotlightPanel"),
              installOrderOut(on: panelClass)
        else { return false }

        let bridge = SpotlightNativePanelHookBridge()
        bridge.owner = owner
        objc_setAssociatedObject(
            panel,
            associationKey,
            bridge,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC,
        )
        return true
    }

    private static func installOrderOut(on panelClass: AnyClass) -> Bool {
        if orderOutOriginalImplementation != nil {
            return true
        }
        let selector = NSSelectorFromString("orderOut:")
        guard let method = class_getInstanceMethod(panelClass, selector) else { return false }
        let original = method_getImplementation(method)
        let replacement: @convention(block) (AnyObject, AnyObject?) -> Void = { panel, sender in
            unsafeBitCast(original, to: OrderOut.self)(panel, selector, sender)
            MainActor.assumeIsolated {
                owner(for: panel)?.nativePanelDidOrderOut()
            }
        }
        class_replaceMethod(
            panelClass,
            selector,
            imp_implementationWithBlock(replacement),
            method_getTypeEncoding(method),
        )
        orderOutOriginalImplementation = original
        return true
    }

    private static func owner(for panel: AnyObject) -> SpotlightNativeLauncherUI? {
        (objc_getAssociatedObject(panel, associationKey) as? SpotlightNativePanelHookBridge)?.owner
    }
}

@MainActor
private final class SpotlightNativeMenuActionTarget: NSObject {
    weak var owner: SpotlightNativeLauncherUI?

    @objc func toggleApplicationPin(_ sender: NSMenuItem) {
        guard let applicationURL = sender.representedObject as? URL else { return }
        owner?.toggleApplicationPin(applicationURL)
    }

    @objc func toggleApplicationVisibility(_ sender: NSMenuItem) {
        guard let applicationURL = sender.representedObject as? URL else { return }
        owner?.toggleApplicationVisibility(applicationURL)
    }

    @objc func toggleShowsHiddenApplications(_ sender: NSMenuItem) {
        owner?.toggleShowsHiddenApplications(sender)
    }

    @objc func openSettings(_: NSMenuItem) {
        CornerlightTrace.lifecycle.notice("native Spotlight settings menu selected")
        owner?.openSettings()
    }

    @objc func checkForUpdates(_: NSMenuItem) {
        CornerlightTrace.lifecycle.notice("native Spotlight update menu selected")
        owner?.checkForUpdates()
    }

    @objc func quitApplication(_: NSMenuItem) {
        CornerlightTrace.lifecycle.notice("native Spotlight quit menu selected")
        owner?.quitApplication()
    }
}

@MainActor
private final class SpotlightNativeContextMenuHookBridge: NSObject {
    weak var owner: SpotlightNativeLauncherUI?
}

@MainActor
private enum SpotlightNativeContextMenuHook {
    private typealias MenuForItem = @convention(c) (
        AnyObject,
        Selector,
        AnyObject,
    ) -> Unmanaged<AnyObject>?
    private typealias MenuForItemReplacement = @convention(block) (
        AnyObject,
        AnyObject,
    ) -> AnyObject?

    private static let bridge = SpotlightNativeContextMenuHookBridge()
    private static var originalImplementation: IMP?
    private static var replacementImplementation: IMP?

    static func install(on collectionView: NSCollectionView, owner: SpotlightNativeLauncherUI) -> Bool {
        let selector = NSSelectorFromString("menuForItemAtIndexPath:")
        guard let controller = collectionView
            .perform(NSSelectorFromString("controller"))?
            .takeUnretainedValue()
        else { return false }
        let controllerClass: AnyClass = type(of: controller)
        guard let method = class_getInstanceMethod(controllerClass, selector) else { return false }
        bridge.owner = owner

        if originalImplementation == nil {
            let original = method_getImplementation(method)
            originalImplementation = original
            let replacement: MenuForItemReplacement = { controller, indexPath in
                let menu = unsafeBitCast(original, to: MenuForItem.self)(
                    controller,
                    selector,
                    indexPath,
                )?.takeUnretainedValue() as? NSMenu
                appendVisibilityItem(to: menu)
                return menu
            }
            let implementation = imp_implementationWithBlock(replacement)
            replacementImplementation = implementation
            class_replaceMethod(
                controllerClass,
                selector,
                implementation,
                method_getTypeEncoding(method),
            )
        }

        return true
    }

    private static func appendVisibilityItem(to menu: NSMenu?) {
        MainActor.assumeIsolated {
            if let menu,
               let owner = bridge.owner,
               let applicationURL = owner.applicationURL(fromNativeMenu: menu) {
                owner.addApplicationContextMenuItems(
                    to: menu,
                    applicationURL: applicationURL,
                )
            } else if let owner = bridge.owner {
                owner.logUnresolvedApplicationMenu(menu)
            }
        }
    }

    static func isInstalled(on collectionView: NSCollectionView) -> Bool {
        let selector = NSSelectorFromString("menuForItemAtIndexPath:")
        guard let controller = collectionView
            .perform(NSSelectorFromString("controller"))?
            .takeUnretainedValue(),
            let replacementImplementation,
            let method = class_getInstanceMethod(type(of: controller), selector)
        else { return false }
        return method_getImplementation(method) == replacementImplementation
            && bridge.owner != nil
    }
}

@MainActor
private final class SpotlightNativePinnedReorderHookBridge: NSObject {
    weak var owner: SpotlightNativeLauncherUI?
    weak var activeCollectionView: NSCollectionView?
    var gesture = LauncherPinnedPointerGestureState()
}

struct LauncherPinnedPointerGestureState {
    private(set) var didReorder = false

    mutating func begin() {
        didReorder = false
    }

    mutating func record(reordered: Bool) {
        didReorder = didReorder || reordered
    }

    mutating func end() -> Bool {
        defer { didReorder = false }
        return didReorder
    }
}

private final class LauncherPinnedInsertionIndicatorView: NSView {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

private final class LauncherPinnedDragImageView: NSImageView {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
private enum SpotlightNativePinnedReorderHook {
    private typealias CanDragItems = @convention(c) (
        AnyObject,
        Selector,
        NSCollectionView,
        NSSet,
        NSEvent?,
    ) -> Bool
    private typealias CanDragItemsReplacement = @convention(block) (
        AnyObject,
        NSCollectionView,
        NSSet,
        NSEvent?,
    ) -> Bool
    private typealias MouseEvent = @convention(c) (
        AnyObject,
        Selector,
        NSEvent,
    ) -> Void
    private typealias MouseEventReplacement = @convention(block) (
        AnyObject,
        NSEvent,
    ) -> Void
    private static var ownerAssociationKey: UInt8 = 0
    private static let sharedBridge = SpotlightNativePinnedReorderHookBridge()
    private static var canDragItemsReplacementImplementation: IMP?
    private static var mouseDownReplacementImplementation: IMP?
    private static var localPointerMonitor: Any?

    static func install(on collectionView: NSCollectionView, owner: SpotlightNativeLauncherUI) -> Bool {
        guard let delegate = collectionView.delegate else { return false }
        let delegateObject = delegate as AnyObject
        let delegateClass: AnyClass = type(of: delegateObject)
        let bridge = SpotlightNativePinnedReorderHookBridge()
        bridge.owner = owner
        sharedBridge.owner = owner
        objc_setAssociatedObject(
            collectionView,
            &ownerAssociationKey,
            bridge,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC,
        )
        guard installCanDragItems(on: delegateClass),
              installMouseDown(on: type(of: collectionView)),
              installLocalPointerMonitor()
        else { return false }
        return true
    }

    private static func installMouseDown(on collectionViewClass: AnyClass) -> Bool {
        if mouseDownReplacementImplementation != nil {
            return true
        }
        let selector = #selector(NSResponder.mouseDown(with:))
        guard let method = class_getInstanceMethod(collectionViewClass, selector) else { return false }
        let original = method_getImplementation(method)
        let replacement: MouseEventReplacement = { candidate, event in
            unsafeBitCast(original, to: MouseEvent.self)(candidate, selector, event)
            MainActor.assumeIsolated {
                guard let collectionView = candidate as? NSCollectionView,
                      let bridge = bridge(for: collectionView),
                      let owner = bridge.owner
                else { return }
                sharedBridge.activeCollectionView = collectionView
                sharedBridge.gesture.begin()
                owner.beginPinnedApplicationPointerReorder(
                    in: collectionView,
                    at: collectionView.convert(event.locationInWindow, from: nil),
                )
            }
        }
        let implementation = imp_implementationWithBlock(replacement)
        class_replaceMethod(
            collectionViewClass,
            selector,
            implementation,
            method_getTypeEncoding(method),
        )
        mouseDownReplacementImplementation = implementation
        return true
    }

    private static func installLocalPointerMonitor() -> Bool {
        if localPointerMonitor != nil {
            return true
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
        ) { event in
            var suppressEvent = false
            MainActor.assumeIsolated {
                guard let owner = sharedBridge.owner,
                      let collectionView = sharedBridge.activeCollectionView
                else { return }
                let point = collectionView.convert(event.locationInWindow, from: nil)
                switch event.type {
                case .leftMouseDragged:
                    sharedBridge.gesture.record(
                        reordered: owner.updatePinnedApplicationPointerReorder(
                            in: collectionView,
                            at: point,
                        ),
                    )
                case .leftMouseUp:
                    suppressEvent = sharedBridge.gesture.end()
                    owner.endPinnedApplicationPointerReorder()
                    sharedBridge.activeCollectionView = nil
                default:
                    break
                }
            }
            return suppressEvent ? nil : event
        }
        return localPointerMonitor != nil
    }

    private static func installCanDragItems(on controllerClass: AnyClass) -> Bool {
        let selector = NSSelectorFromString(
            "collectionView:canDragItemsAtIndexPaths:withEvent:",
        )
        guard let method = class_getInstanceMethod(controllerClass, selector)
        else { return false }
        if canDragItemsReplacementImplementation == nil {
            let original = method_getImplementation(method)
            let replacement: CanDragItemsReplacement = { controller, collectionView, indexPaths, event in
                MainActor.assumeIsolated {
                    guard owner(for: collectionView) != nil else {
                        return unsafeBitCast(original, to: CanDragItems.self)(
                            controller,
                            selector,
                            collectionView,
                            indexPaths,
                            event,
                        )
                    }
                    // SearchUI's native drag loop takes subsequent mouse events away from
                    // Cornerlight's pinned-row reorder tracker. The enumerated launcher owns this
                    // collection, so keep the native drag session disabled here.
                    return false
                }
            }
            let implementation = imp_implementationWithBlock(replacement)
            canDragItemsReplacementImplementation = implementation
            class_replaceMethod(
                controllerClass,
                selector,
                implementation,
                method_getTypeEncoding(method),
            )
        }
        return true
    }

    static func isInstalled(on collectionView: NSCollectionView) -> Bool {
        guard let delegate = collectionView.delegate,
              let canDragItemsReplacementImplementation,
              let mouseDownReplacementImplementation,
              localPointerMonitor != nil,
              let canDragMethod = class_getInstanceMethod(
                  type(of: delegate as AnyObject),
                  NSSelectorFromString("collectionView:canDragItemsAtIndexPaths:withEvent:"),
              ),
              let mouseDownMethod = class_getInstanceMethod(
                  type(of: collectionView),
                  #selector(NSResponder.mouseDown(with:)),
              )
        else { return false }
        return method_getImplementation(canDragMethod) == canDragItemsReplacementImplementation
            && method_getImplementation(mouseDownMethod) == mouseDownReplacementImplementation
            && owner(for: collectionView) != nil
    }

    private static func owner(
        for collectionView: NSCollectionView,
    ) -> SpotlightNativeLauncherUI? {
        bridge(for: collectionView)?.owner
    }

    private static func bridge(
        for collectionView: NSCollectionView,
    ) -> SpotlightNativePinnedReorderHookBridge? {
        if let associatedBridge = objc_getAssociatedObject(
            collectionView,
            &ownerAssociationKey,
        ) as? SpotlightNativePinnedReorderHookBridge {
            return associatedBridge
        }
        return sharedBridge.owner == nil ? nil : sharedBridge
    }
}

@MainActor
private final class SpotlightNativePinnedBadgeHookBridge: NSObject {
    weak var owner: SpotlightNativeLauncherUI?
}

@MainActor
private enum SpotlightNativePinnedBadgeHook {
    private typealias WillDisplayItem = @convention(c) (
        AnyObject,
        Selector,
        NSCollectionView,
        NSCollectionViewItem,
        NSIndexPath,
    ) -> Void
    private typealias WillDisplayItemReplacement = @convention(block) (
        AnyObject,
        NSCollectionView,
        NSCollectionViewItem,
        NSIndexPath,
    ) -> Void

    private static let bridge = SpotlightNativePinnedBadgeHookBridge()
    private static var replacementImplementation: IMP?

    static func install(on collectionView: NSCollectionView, owner: SpotlightNativeLauncherUI) -> Bool {
        let selector = NSSelectorFromString(
            "collectionView:willDisplayItem:forRepresentedObjectAtIndexPath:",
        )
        guard let controller = collectionView
            .perform(NSSelectorFromString("controller"))?
            .takeUnretainedValue(),
            let method = class_getInstanceMethod(type(of: controller), selector)
        else { return false }
        bridge.owner = owner

        if replacementImplementation == nil {
            let original = method_getImplementation(method)
            let replacement: WillDisplayItemReplacement = { controller, view, item, indexPath in
                unsafeBitCast(original, to: WillDisplayItem.self)(
                    controller,
                    selector,
                    view,
                    item,
                    indexPath,
                )
                MainActor.assumeIsolated {
                    bridge.owner?.nativeItemWillDisplay(item, at: indexPath)
                }
            }
            let implementation = imp_implementationWithBlock(replacement)
            replacementImplementation = implementation
            class_replaceMethod(
                type(of: controller),
                selector,
                implementation,
                method_getTypeEncoding(method),
            )
        }
        return true
    }

    static func isInstalled(on collectionView: NSCollectionView) -> Bool {
        let selector = NSSelectorFromString(
            "collectionView:willDisplayItem:forRepresentedObjectAtIndexPath:",
        )
        guard let controller = collectionView
            .perform(NSSelectorFromString("controller"))?
            .takeUnretainedValue(),
            let replacementImplementation,
            let method = class_getInstanceMethod(type(of: controller), selector)
        else { return false }
        return method_getImplementation(method) == replacementImplementation
            && bridge.owner != nil
    }
}

@MainActor
private final class SpotlightNativeViewOptionsMenuHookBridge: NSObject {
    weak var owner: SpotlightNativeLauncherUI?
}

@MainActor
private enum SpotlightNativeViewOptionsMenuHook {
    private typealias Update = @convention(c) (AnyObject, Selector) -> Void

    private static let bridge = SpotlightNativeViewOptionsMenuHookBridge()
    private static var originalImplementation: IMP?

    static func install(owner: SpotlightNativeLauncherUI) -> Bool {
        let selector = NSSelectorFromString("update")
        guard let menuClass = NSClassFromString("SpotlightAppMacOS.ViewOptionsMenu"),
              let method = class_getInstanceMethod(menuClass, selector)
        else { return false }

        bridge.owner = owner
        if originalImplementation == nil {
            let original = method_getImplementation(method)
            originalImplementation = original
            let replacement: @convention(block) (AnyObject) -> Void = { menu in
                unsafeBitCast(original, to: Update.self)(menu, selector)
                MainActor.assumeIsolated {
                    if let menu = menu as? NSMenu {
                        bridge.owner?.configureViewOptionsMenu(menu)
                    }
                }
            }
            guard class_addMethod(
                menuClass,
                selector,
                imp_implementationWithBlock(replacement),
                method_getTypeEncoding(method),
            ) else { return false }
        }
        return true
    }
}

/// Spotlight owns the panel, main controller, search controller, and result surface.
/// Cornerlight crosses one boundary only: enumerated bundle URLs become native app sections.
struct SpotlightNativeTransitionGate {
    typealias Token = UInt64

    enum ToggleRequest: Equatable {
        case start(Token)
        case queued
    }

    enum Completion: Equatable {
        case stale
        case idle
        case startQueuedToggle(Token)
    }

    private var generation: Token = 0
    private var activeToken: Token?
    private var pendingToggle = false

    mutating func requestToggle() -> ToggleRequest {
        guard activeToken == nil else {
            pendingToggle.toggle()
            return .queued
        }
        return .start(reserveTransition())
    }

    mutating func supersedeWithDismissal() -> Token {
        reserveTransition()
    }

    mutating func complete(_ token: Token) -> Completion {
        guard activeToken == token else { return .stale }
        guard pendingToggle else {
            activeToken = nil
            return .idle
        }
        pendingToggle = false
        return .startQueuedToggle(reserveTransition())
    }

    func isCurrent(_ token: Token) -> Bool {
        activeToken == token
    }

    var hasActiveTransition: Bool {
        activeToken != nil
    }

    private mutating func reserveTransition() -> Token {
        generation &+= 1
        activeToken = generation
        return generation
    }
}

struct LauncherContentLease {
    private(set) var isLoaded = false

    mutating func prepare() {
        isLoaded = true
    }

    mutating func finishDismissal(retainsForQueuedPresentation: Bool) -> Bool {
        guard isLoaded, !retainsForQueuedPresentation else { return false }
        isLoaded = false
        return true
    }
}

struct SpotlightNativeLifecycleLease {
    typealias Token = SpotlightNativeTransitionGate.Token

    private(set) var token: Token?

    mutating func begin(_ token: Token) {
        self.token = token
    }

    mutating func completeNativeInvocation(_ completedToken: Token) {
        if token == completedToken {
            token = nil
        }
    }

    mutating func takeDismissalToken() -> Token? {
        defer { token = nil }
        return token
    }

    mutating func clear() {
        token = nil
    }
}

enum SpotlightSystemToggleIsolation {
    static let notificationName = Notification.Name("com.apple.spotlight.toggle")

    static func removeNativeToggleObserver(
        _ observer: Any,
        from center: NotificationCenter,
    ) {
        center.removeObserver(observer, name: notificationName, object: nil)
    }
}

enum SpotlightNativeFocusReleaseDrain {
    static func perform(
        release: () -> Bool,
        deactivate: () -> Void,
    ) -> Int {
        var releaseCount = 0
        while release() {
            releaseCount += 1
        }
        if releaseCount > 0 {
            deactivate()
        }
        return releaseCount
    }
}

@MainActor
private final class SpotlightSystemToggleObserver: NSObject {
    weak var owner: SpotlightNativeLauncherUI?

    @objc func systemSpotlightDidToggle(_: Notification) {
        owner?.systemSpotlightDidToggle()
    }
}

@MainActor
// The dynamic bridge deliberately keeps Spotlight's related selectors in one auditable type.
// swiftlint:disable:next type_body_length
final class SpotlightNativeLauncherUI {
    private typealias MainWindowInitializer = @convention(c) (
        AnyObject,
        Selector,
        AnyObject?,
        AnyObject,
        AnyObject?,
    ) -> Unmanaged<AnyObject>?
    private typealias IdentityInitializer = @convention(c) (
        AnyObject,
        Selector,
        NSURL,
    ) -> Unmanaged<AnyObject>?
    private typealias SectionBuilder = @convention(c) (
        AnyObject,
        Selector,
        NSString,
        NSString,
        Int32,
        NSArray,
    ) -> Unmanaged<AnyObject>?
    private typealias BoolSetter = @convention(c) (AnyObject, Selector, Bool) -> Void
    private typealias BoolGetter = @convention(c) (AnyObject, Selector) -> Bool
    private typealias CompletionAction = @convention(c) (
        AnyObject,
        Selector,
        @convention(block) () -> Void,
    ) -> Void
    private typealias ReasonedCompletionAction = @convention(c) (
        AnyObject,
        Selector,
        Int,
        @convention(block) () -> Void,
    ) -> Void

    let panel: NSPanel
    let viewController: NSViewController
    let searchField: NSSearchField
    let appDelegate: NSObject
    let collectionView: NSCollectionView

    var onQueryChange: (() -> Void)?
    var onNativeDismiss: (() -> Void)?
    var isApplicationPinned: ((URL) -> Bool)?
    var canPinApplication: ((URL) -> Bool)?
    var onSetApplicationPinned: ((URL, Bool) -> Void)?
    var onMovePinnedApplication: ((URL, Int, [URL]) -> Void)?
    var isApplicationHidden: ((URL) -> Bool)?
    var onSetApplicationHidden: ((URL, Bool) -> Void)?
    var onSetShowsHiddenApplications: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onQuit: (() -> Void)?

    private let mainWindowController: AnyObject
    private let topHitResultsController: AnyObject
    private let resultsController: AnyObject
    private let menuItem: AnyObject
    private let sessionAnalytics: AnyObject
    private let menuActionTarget: SpotlightNativeMenuActionTarget
    private let searchFieldObserver: SpotlightNativeSearchFieldObserver
    private let systemToggleObserver: SpotlightSystemToggleObserver
    private nonisolated(unsafe) let statusItem: NSStatusItem
    private var currentSuggestionSections: [AnyObject] = []
    private var currentCatalogSections: [AnyObject] = []
    private var currentSuggestionApplications: [ApplicationRecord] = []
    private var currentApplicationsByPath: [String: ApplicationRecord] = [:]
    private var pointerReorderPinnedApplicationURL: URL?
    private var pinnedDragImageView: NSImageView?
    private var pinnedDragImageOffset = NSPoint.zero
    private var pinnedInsertionIndicatorView: NSView?
    private var showsHiddenApplications = false
    private var dismissalCallbackScheduled = false
    private var retainsContentForQueuedPresentation = false
    private var transitionGate = SpotlightNativeTransitionGate()
    private var lifecycleLease = SpotlightNativeLifecycleLease()
    private lazy var pinnedBadgeImage = Self.makePinnedBadgeImage()

    // swiftlint:disable:next function_body_length
    init?() {
        guard SpotlightExecutableRuntime.isLoaded,
              let mainWindowClass = NSClassFromString(
                  "_TtC17SpotlightAppMacOS20MainWindowController",
              ),
              let menuItemClass = NSClassFromString("SPSpotlightMenuItem"),
              let appDelegateClass = NSClassFromString("SPAppDelegate"),
              let sessionAnalyticsClass = NSClassFromString(
                  "_TtC17SpotlightAppMacOS16SessionAnalytics",
              )
        else { return nil }

        let menuItemClassObject = menuItemClass as AnyObject
        guard let allocatedMenuItem = menuItemClassObject
            .perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue(),
            let menuItem = allocatedMenuItem
            .perform(NSSelectorFromString("init"))?
            .takeRetainedValue()
        else { return nil }

        let statusItem = NSStatusBar.system.statusItem(withLength: 0)
        _ = menuItem.perform(NSSelectorFromString("setStatusItem:"), with: statusItem)

        let appDelegateClassObject = appDelegateClass as AnyObject
        guard let allocatedAppDelegate = appDelegateClassObject
            .perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue(),
            let appDelegateObject = allocatedAppDelegate
            .perform(NSSelectorFromString("init"))?
            .takeRetainedValue(),
            let appDelegate = appDelegateObject as? NSObject
        else {
            NSStatusBar.system.removeStatusItem(statusItem)
            return nil
        }
        Self.setObject(menuItem, on: appDelegate, selector: "setMenuItem:")
        Self.setObject(appDelegate, on: menuItem, selector: "setDelegate:")

        let sessionAnalyticsClassObject = sessionAnalyticsClass as AnyObject
        guard let allocatedSessionAnalytics = sessionAnalyticsClassObject
            .perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue(),
            let sessionAnalytics = allocatedSessionAnalytics
            .perform(NSSelectorFromString("init"))?
            .takeRetainedValue()
        else {
            NSStatusBar.system.removeStatusItem(statusItem)
            return nil
        }

        let mainWindowClassObject = mainWindowClass as AnyObject
        guard let allocatedMainWindowController = mainWindowClassObject
            .perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue()
        else { return nil }
        let mainInitializerSelector = NSSelectorFromString(
            "initWithWindow:appDelegate:sessionAnalytics:",
        )
        let initializeMainWindow = unsafeBitCast(
            allocatedMainWindowController.method(for: mainInitializerSelector),
            to: MainWindowInitializer.self,
        )
        guard let mainWindowController = initializeMainWindow(
            allocatedMainWindowController,
            mainInitializerSelector,
            nil,
            appDelegate,
            sessionAnalytics,
        )?.takeRetainedValue(),
            let panel = mainWindowController
            .perform(NSSelectorFromString("spotlightPanel"))?
            .takeUnretainedValue() as? NSPanel,
            let initialized = mainWindowController
            .perform(NSSelectorFromString("searchViewController"))?
            .takeUnretainedValue() as? NSViewController,
            NSStringFromClass(type(of: initialized)) ==
            "SpotlightAppMacOS.SearchViewController"
        else {
            NSStatusBar.system.removeStatusItem(statusItem)
            return nil
        }

        Self.set(true, on: initialized, selector: "setForAppsBrowseLaunch:")
        Self.call(true, on: initialized, selector: "goToAppsSearchWithResetQuery:")
        _ = initialized.view
        guard let results = initialized
            .perform(NSSelectorFromString("resultsViewController"))?
            .takeUnretainedValue(),
            NSStringFromClass(type(of: results)) ==
            "SpotlightAppMacOS.SearchResultsViewController",
            let field = Self.firstDescendant(of: NSSearchField.self, in: initialized.view),
            NSStringFromClass(type(of: field)) == "SpotlightAppMacOS.SearchField",
            let collectionView = Self.firstDescendant(
                of: NSCollectionView.self,
                in: initialized.view,
            ),
            NSStringFromClass(type(of: collectionView)) == "SearchUICollectionView"
        else {
            NSStatusBar.system.removeStatusItem(statusItem)
            return nil
        }
        guard let navigationControllers = initialized
            .perform(NSSelectorFromString("viewControllers"))?
            .takeUnretainedValue() as? NSArray,
            let sandwichController = navigationControllers.firstObject as AnyObject?,
            let topHitResultsController = Self.objectIvar(
                named: "topHitViewController",
                on: sandwichController,
            ),
            NSStringFromClass(type(of: topHitResultsController)) ==
            "SpotlightAppMacOS.SearchResultsAboveFiltersViewController"
        else {
            NSStatusBar.system.removeStatusItem(statusItem)
            return nil
        }
        guard let navigationBar = Self.objectIvar(
            named: "navigationBar",
            on: initialized,
        ),
            NSStringFromClass(type(of: navigationBar)) ==
            "SpotlightAppMacOS.SearchNavigationBar",
            let indexingStatusView = Self.objectIvar(
                named: "indexingView",
                on: navigationBar,
            ),
            NSStringFromClass(type(of: indexingStatusView)) ==
            "SPSpotlightIndexingView"
        else {
            NSStatusBar.system.removeStatusItem(statusItem)
            return nil
        }

        self.panel = panel
        self.appDelegate = appDelegate
        self.mainWindowController = mainWindowController
        self.topHitResultsController = topHitResultsController
        viewController = initialized
        searchField = field
        self.collectionView = collectionView
        resultsController = results
        self.menuItem = menuItem
        self.sessionAnalytics = sessionAnalytics
        let menuActionTarget = SpotlightNativeMenuActionTarget()
        self.menuActionTarget = menuActionTarget
        let searchFieldObserver = SpotlightNativeSearchFieldObserver()
        self.searchFieldObserver = searchFieldObserver
        let systemToggleObserver = SpotlightSystemToggleObserver()
        self.systemToggleObserver = systemToggleObserver
        self.statusItem = statusItem

        // This is the same ownership graph created by
        // `SPAppDelegate.applicationDidFinishLaunching:`. Calling that complete method in
        // a third-party background process would momentarily order the panel front during
        // startup, so construct its app-browse branch without that focus side effect.
        Self.setObject(
            mainWindowController,
            on: appDelegate,
            selector: "setAppBrowseWindowController:",
        )

        Self.set(true, on: results, selector: "setSingleClickExecutesCommands:")
        Self.set(false, on: results, selector: "setIsBelowVisibleFilterBar:")
        guard SpotlightNativeIndexingStatusHook.install(on: indexingStatusView),
              SpotlightNativeSectionsHook.install(on: results, owner: self),
              SpotlightNativeSectionsHook.install(on: topHitResultsController, owner: self),
              SpotlightNativePanelHook.install(on: panel, owner: self),
              SpotlightNativeContextMenuHook.install(on: collectionView, owner: self),
              SpotlightNativePinnedReorderHook.install(on: collectionView, owner: self),
              SpotlightNativePinnedBadgeHook.install(on: collectionView, owner: self),
              SpotlightNativeViewOptionsMenuHook.install(owner: self)
        else {
            NSStatusBar.system.removeStatusItem(statusItem)
            return nil
        }

        menuActionTarget.owner = self
        searchFieldObserver.owner = self
        searchFieldObserver.searchField = field
        NotificationCenter.default.addObserver(
            searchFieldObserver,
            selector: #selector(SpotlightNativeSearchFieldObserver.textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: nil,
        )
        systemToggleObserver.owner = self
        let distributedCenter = DistributedNotificationCenter.default()
        SpotlightSystemToggleIsolation.removeNativeToggleObserver(
            menuItem,
            from: distributedCenter,
        )
        distributedCenter.addObserver(
            systemToggleObserver,
            selector: #selector(SpotlightSystemToggleObserver.systemSpotlightDidToggle(_:)),
            name: SpotlightSystemToggleIsolation.notificationName,
            object: nil,
            suspensionBehavior: .deliverImmediately,
        )
        searchField.placeholderString = "Applications"
    }

    deinit {
        NotificationCenter.default.removeObserver(searchFieldObserver)
        DistributedNotificationCenter.default().removeObserver(systemToggleObserver)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    var view: NSView {
        panel.contentViewController?.view ?? viewController.view
    }

    var isPresented: Bool {
        let selector = NSSelectorFromString("spotlightIsVisible")
        return unsafeBitCast(
            appDelegate.method(for: selector),
            to: BoolGetter.self,
        )(appDelegate, selector)
    }

    func invoke() {
        switch transitionGate.requestToggle() {
        case let .start(token):
            performNativeInvocation(token: token)
        case .queued:
            CornerlightTrace.lifecycle.notice("native Spotlight toggle queued during transition")
        }
    }

    private func performNativeInvocation(token: SpotlightNativeTransitionGate.Token) {
        guard transitionGate.isCurrent(token) else { return }
        lifecycleLease.begin(token)
        prepareForWindowServerInvocation()
        let selector = NSSelectorFromString("launchAppsBrowsingWithCompletion:")
        let completionBlock: @convention(block) () -> Void = { [weak self] in
            guard let self else { return }
            lifecycleLease.completeNativeInvocation(token)
            nativeTransitionDidComplete(token)
        }
        unsafeBitCast(
            appDelegate.method(for: selector),
            to: CompletionAction.self,
        )(appDelegate, selector, completionBlock)
    }

    func prepareForWindowServerInvocation() {
        // Spotlight sets this while dismissing to consume Dock's paired launch message.
        // Cornerlight's Hot Corner is already edge-gated and arrives from WindowServer, so a
        // stale Dock-only suppression bit must not consume its next genuine entry.
        Self.set(false, on: appDelegate, selector: "setIgnoreDockAppsLaunch:")
    }

    func dismiss() {
        beginLifecycleDismissal()
        _ = appDelegate.perform(NSSelectorFromString("dismissSpotlight"))
    }

    func dismiss(reason: Int, completion: @escaping () -> Void) {
        lifecycleLease.clear()
        let token = transitionGate.supersedeWithDismissal()
        let selector = NSSelectorFromString("dismissSpotlightWithReason:completion:")
        let completionBlock: @convention(block) () -> Void = { [weak self] in
            completion()
            self?.nativeTransitionDidComplete(token)
        }
        unsafeBitCast(
            appDelegate.method(for: selector),
            to: ReasonedCompletionAction.self,
        )(appDelegate, selector, reason, completionBlock)
    }

    private func nativeTransitionDidComplete(_ token: SpotlightNativeTransitionGate.Token) {
        switch transitionGate.complete(token) {
        case .stale:
            CornerlightTrace.lifecycle.notice("ignored stale native Spotlight transition completion")
        case .idle:
            break
        case let .startQueuedToggle(nextToken):
            retainsContentForQueuedPresentation = !panel.isVisible && !isPresented
            CornerlightTrace.lifecycle.notice("replaying queued native Spotlight toggle")
            DispatchQueue.main.async { [weak self] in
                self?.performNativeInvocation(token: nextToken)
            }
        }
    }

    func applicationLostFocus() {
        if panel.isVisible || transitionGate.hasActiveTransition {
            beginLifecycleDismissal()
        }
        _ = appDelegate.perform(NSSelectorFromString("applicationLostFocus"))
    }

    func systemSpotlightDidToggle() {
        let releaseSelector = NSSelectorFromString("_releaseKeyFocus")
        let releaseCount = SpotlightNativeFocusReleaseDrain.perform(
            release: {
                unsafeBitCast(
                    NSApp.method(for: releaseSelector),
                    to: BoolGetter.self,
                )(NSApp, releaseSelector)
            },
            deactivate: {
                NSApp.deactivate()
            },
        )
        guard panel.isVisible || transitionGate.hasActiveTransition || isPresented else { return }
        CornerlightTrace.lifecycle.notice(
            "yielding to system Spotlight released=\(releaseCount, privacy: .public)",
        )
        dismiss()
    }

    func update(
        suggestions: [ApplicationRecord],
        applications: [ApplicationRecord],
    ) {
        var nextSuggestionSections: [AnyObject] = []
        if !suggestions.isEmpty,
           let section = makeSection(
               title: "",
               identifier: "com.apple.spotlight.zkw.apps.suggestions",
               style: 1,
               applications: suggestions,
           ) {
            tagSuggestionResults(in: section)
            nextSuggestionSections.append(section)
        }

        var nextCatalogSections: [AnyObject] = []
        if let section = makeSection(
            title: "",
            identifier: "com.apple.spotlight.zkw.alphabetic",
            style: 0,
            applications: applications,
        ) {
            nextCatalogSections.append(section)
        }

        currentSuggestionSections = nextSuggestionSections
        currentCatalogSections = nextCatalogSections
        currentSuggestionApplications = suggestions
        currentApplicationsByPath.removeAll(keepingCapacity: true)
        for application in suggestions + applications {
            currentApplicationsByPath[application.url.standardizedFileURL.path] = application
        }
        Self.setObject(
            searchField.stringValue as NSString,
            on: resultsController,
            selector: "setQueryString:",
        )
        Self.setObject(
            searchField.stringValue as NSString,
            on: topHitResultsController,
            selector: "setQueryString:",
        )
        restoreEnumeratedSections()
    }

    func restoreEnumeratedSections() {
        SpotlightNativeSectionsHook.setEnumeratedSections(
            [],
            on: topHitResultsController,
        )
        SpotlightNativeSectionsHook.setEnumeratedSections(
            currentSuggestionSections + currentCatalogSections,
            on: resultsController,
        )
    }

    func nativeSectionsWereProposed() {
        restoreEnumeratedSections()
    }

    func nativeQueryDidChange() {
        onQueryChange?()
    }

    func nativePanelDidOrderOut() {
        scheduleDismissalCallback()
    }

    func consumeQueuedPresentationContentRetention() -> Bool {
        defer { retainsContentForQueuedPresentation = false }
        return retainsContentForQueuedPresentation
    }

    func addApplicationContextMenuItems(to menu: NSMenu, applicationURL: URL) {
        let pinIdentifier = NSUserInterfaceItemIdentifier(
            "com.emrikol.Cornerlight.toggleApplicationPin",
        )
        let visibilityIdentifier = NSUserInterfaceItemIdentifier(
            "com.emrikol.Cornerlight.toggleApplicationVisibility",
        )
        guard !menu.items.contains(where: {
            $0.identifier == pinIdentifier || $0.identifier == visibilityIdentifier
        }) else { return }

        if !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }
        addApplicationPinItem(to: menu, applicationURL: applicationURL)
        addApplicationVisibilityItem(
            to: menu,
            applicationURL: applicationURL,
            addsSeparator: false,
        )
    }

    func addApplicationPinItem(to menu: NSMenu, applicationURL: URL) {
        let itemIdentifier = NSUserInterfaceItemIdentifier(
            "com.emrikol.Cornerlight.toggleApplicationPin",
        )
        guard !menu.items.contains(where: { $0.identifier == itemIdentifier }) else { return }

        let pinned = isApplicationPinned?(applicationURL) ?? false
        let item = NSMenuItem(
            title: pinned ? "Unpin This App" : "Pin This App",
            action: #selector(SpotlightNativeMenuActionTarget.toggleApplicationPin(_:)),
            keyEquivalent: "",
        )
        item.identifier = itemIdentifier
        item.image = NSImage(
            systemSymbolName: pinned ? "pin.slash" : "pin",
            accessibilityDescription: nil,
        )
        item.representedObject = applicationURL as NSURL
        item.target = menuActionTarget
        item.isEnabled = pinned || (canPinApplication?(applicationURL) ?? false)
        menu.addItem(item)
    }

    func addApplicationVisibilityItem(
        to menu: NSMenu,
        applicationURL: URL,
        addsSeparator: Bool = true,
    ) {
        let itemIdentifier = NSUserInterfaceItemIdentifier(
            "com.emrikol.Cornerlight.toggleApplicationVisibility",
        )
        guard !menu.items.contains(where: { $0.identifier == itemIdentifier }) else { return }

        let hidden = isApplicationHidden?(applicationURL) ?? false
        if addsSeparator, !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }
        let item = NSMenuItem(
            title: hidden ? "Unhide This App" : "Hide This App",
            action: #selector(SpotlightNativeMenuActionTarget.toggleApplicationVisibility(_:)),
            keyEquivalent: "",
        )
        item.identifier = itemIdentifier
        item.image = NSImage(
            systemSymbolName: hidden ? "eye" : "eye.slash",
            accessibilityDescription: nil,
        )
        item.representedObject = applicationURL as NSURL
        item.target = menuActionTarget
        menu.addItem(item)
    }

    var hasNativeApplicationContextMenuHook: Bool {
        guard let collectionView = Self.firstDescendant(
            of: NSCollectionView.self,
            in: viewController.view,
        ) else { return false }
        return SpotlightNativeContextMenuHook.isInstalled(on: collectionView)
    }

    var hasNativePinnedReorderHook: Bool {
        SpotlightNativePinnedReorderHook.isInstalled(on: collectionView)
    }

    var hasNativePinnedBadgeHook: Bool {
        SpotlightNativePinnedBadgeHook.isInstalled(on: collectionView)
    }

    func nativeItemWillDisplay(_ item: NSCollectionViewItem, at indexPath: NSIndexPath) {
        let pinned = searchField.stringValue.isEmpty &&
            indexPath.section == 0 &&
            currentSuggestionApplications.indices.contains(indexPath.item) &&
            isApplicationPinned?(currentSuggestionApplications[indexPath.item].url) == true
        setPinnedBadge(pinned, on: item.view)
    }

    func beginPinnedApplicationPointerReorder(
        in candidateCollectionView: NSCollectionView,
        at point: NSPoint? = nil,
    ) {
        endPinnedApplicationPointerReorder()
        guard candidateCollectionView.selectionIndexPaths.count == 1,
              let selectedIndexPath = candidateCollectionView.selectionIndexPaths.first,
              let application = pinnedApplication(at: selectedIndexPath as NSIndexPath)
        else { return }
        pointerReorderPinnedApplicationURL = application.url
        guard let point else { return }
        preparePinnedApplicationDragImage(
            for: application,
            at: selectedIndexPath,
            in: candidateCollectionView,
            pointerLocation: point,
        )
    }

    @discardableResult
    func updatePinnedApplicationPointerReorder(
        in candidateCollectionView: NSCollectionView,
        at point: NSPoint,
    ) -> Bool {
        guard let applicationURL = pointerReorderPinnedApplicationURL
        else { return false }
        showPinnedApplicationDragImage(in: candidateCollectionView, at: point)

        let pinnedURLs = visiblePinnedApplicationURLs
        guard pinnedURLs.count > 1,
              let source = pinnedURLs.firstIndex(of: applicationURL)
        else { return false }
        let itemFrames = (0 ..< pinnedURLs.count).compactMap { item -> NSRect? in
            let indexPath = IndexPath(item: item, section: 0)
            return candidateCollectionView.collectionViewLayout?
                .layoutAttributesForItem(at: indexPath)?.frame ??
                candidateCollectionView.item(at: indexPath)?.view.frame
        }
        let destination = LauncherPinnedDropPolicy.insertionIndex(
            at: point,
            itemFrames: itemFrames,
        )
        guard itemFrames.count == pinnedURLs.count,
              let destination
        else {
            hidePinnedApplicationInsertionIndicator()
            return false
        }
        showPinnedApplicationInsertionIndicator(
            in: candidateCollectionView,
            at: destination,
            itemFrames: itemFrames,
        )
        guard
            destination != source,
            destination != source + 1
        else { return false }

        onMovePinnedApplication?(applicationURL, destination, pinnedURLs)
        return true
    }

    func endPinnedApplicationPointerReorder() {
        pointerReorderPinnedApplicationURL = nil
        pinnedDragImageView?.isHidden = true
        hidePinnedApplicationInsertionIndicator()
    }

    var pinnedApplicationDragPreviewFrame: NSRect? {
        guard let pinnedDragImageView, !pinnedDragImageView.isHidden else { return nil }
        return pinnedDragImageView.frame
    }

    private func preparePinnedApplicationDragImage(
        for application: ApplicationRecord,
        at indexPath: IndexPath,
        in candidateCollectionView: NSCollectionView,
        pointerLocation: NSPoint,
    ) {
        let nativeItemView = candidateCollectionView.item(at: indexPath)?.view
        let nativeImageView = nativeItemView.flatMap {
            Self.firstDescendant(named: "SearchUIImageView", in: $0)
        }
        let sourceFrame = nativeImageView.map {
            $0.convert($0.bounds, to: candidateCollectionView)
        } ?? NSRect(
            x: pointerLocation.x - 32,
            y: pointerLocation.y - 32,
            width: 64,
            height: 64,
        )
        let image = nativeImageView.flatMap(Self.snapshot) ??
            NSWorkspace.shared.icon(forFile: application.url.path)
        let dragImageView = pinnedDragImageView ?? {
            let view = LauncherPinnedDragImageView(frame: sourceFrame)
            view.imageScaling = .scaleProportionallyUpOrDown
            view.imageAlignment = .alignCenter
            view.alphaValue = 0.82
            view.wantsLayer = true
            view.layer?.shadowColor = NSColor.black.cgColor
            view.layer?.shadowOpacity = 0.35
            view.layer?.shadowOffset = NSSize(width: 0, height: -2)
            view.layer?.shadowRadius = 5
            view.setAccessibilityElement(false)
            pinnedDragImageView = view
            return view
        }()
        dragImageView.image = image
        dragImageView.frame = sourceFrame
        dragImageView.isHidden = true
        pinnedDragImageOffset = sourceFrame.contains(pointerLocation)
            ? NSPoint(
                x: pointerLocation.x - sourceFrame.minX,
                y: pointerLocation.y - sourceFrame.minY,
            )
            : NSPoint(x: sourceFrame.width / 2, y: sourceFrame.height / 2)
        if dragImageView.superview !== candidateCollectionView {
            dragImageView.removeFromSuperview()
            candidateCollectionView.addSubview(dragImageView, positioned: .above, relativeTo: nil)
        }
    }

    private func showPinnedApplicationDragImage(
        in candidateCollectionView: NSCollectionView,
        at point: NSPoint,
    ) {
        guard let pinnedDragImageView else { return }
        if pinnedDragImageView.superview !== candidateCollectionView {
            pinnedDragImageView.removeFromSuperview()
            candidateCollectionView.addSubview(
                pinnedDragImageView,
                positioned: .above,
                relativeTo: nil,
            )
        }
        pinnedDragImageView.setFrameOrigin(
            NSPoint(
                x: point.x - pinnedDragImageOffset.x,
                y: point.y - pinnedDragImageOffset.y,
            ),
        )
        pinnedDragImageView.isHidden = false
    }

    private func showPinnedApplicationInsertionIndicator(
        in candidateCollectionView: NSCollectionView,
        at insertionIndex: Int,
        itemFrames: [NSRect],
    ) {
        guard let frame = LauncherPinnedDropPolicy.indicatorFrame(
            at: insertionIndex,
            itemFrames: itemFrames,
        ) else {
            hidePinnedApplicationInsertionIndicator()
            return
        }
        let indicator = pinnedInsertionIndicatorView ?? {
            let view = LauncherPinnedInsertionIndicatorView(frame: frame)
            view.wantsLayer = true
            view.layer?.cornerRadius = LauncherPinnedDropPolicy.indicatorWidth / 2
            view.setAccessibilityElement(false)
            pinnedInsertionIndicatorView = view
            return view
        }()
        if indicator.superview !== candidateCollectionView {
            indicator.removeFromSuperview()
            candidateCollectionView.addSubview(
                indicator,
                positioned: pinnedDragImageView?.superview === candidateCollectionView
                    ? .below
                    : .above,
                relativeTo: pinnedDragImageView?.superview === candidateCollectionView
                    ? pinnedDragImageView
                    : nil,
            )
        }
        indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        indicator.frame = frame
        indicator.isHidden = false
    }

    private func hidePinnedApplicationInsertionIndicator() {
        pinnedInsertionIndicatorView?.isHidden = true
    }

    private func pinnedApplication(at indexPath: NSIndexPath) -> ApplicationRecord? {
        guard searchField.stringValue.isEmpty,
              indexPath.section == 0,
              currentSuggestionApplications.indices.contains(indexPath.item)
        else { return nil }
        let application = currentSuggestionApplications[indexPath.item]
        return isApplicationPinned?(application.url) == true ? application : nil
    }

    private var visiblePinnedApplicationURLs: [URL] {
        currentSuggestionApplications.compactMap { application in
            isApplicationPinned?(application.url) == true ? application.url : nil
        }
    }

    private func setPinnedBadge(_ pinned: Bool, on itemView: NSView) {
        guard let imageView = Self.firstDescendant(
            named: "SearchUIImageView",
            in: itemView,
        ),
            let image = imageView.perform(NSSelectorFromString("tlkImage"))?
            .takeUnretainedValue()
        else { return }

        let badgeSelector = NSSelectorFromString("badgeImage")
        let currentBadge = image.responds(to: badgeSelector)
            ? image.perform(badgeSelector)?.takeUnretainedValue()
            : nil
        if pinned {
            guard let pinnedBadgeImage,
                  currentBadge !== pinnedBadgeImage
            else { return }
            Self.setObject(pinnedBadgeImage, on: image, selector: "setBadgeImage:")
        } else {
            guard let pinnedBadgeImage,
                  currentBadge === pinnedBadgeImage
            else { return }
            Self.setObject(nil, on: image, selector: "setBadgeImage:")
        }

        Self.setObject(nil, on: imageView, selector: "setTlkImage:")
        Self.setObject(image, on: imageView, selector: "setTlkImage:")
    }

    func applicationURL(fromNativeMenu menu: NSMenu) -> URL? {
        let buttonSelector = NSSelectorFromString("commandButtonItem")
        let commandSelector = NSSelectorFromString("command")
        let dictionarySelector = NSSelectorFromString("dictionaryRepresentation")
        for item in menu.items where item.responds(to: buttonSelector) {
            guard let button = item.perform(buttonSelector)?.takeUnretainedValue(),
                  button.responds(to: commandSelector),
                  let command = button.perform(commandSelector)?.takeUnretainedValue(),
                  command.responds(to: dictionarySelector),
                  let representation = command.perform(dictionarySelector)?.takeUnretainedValue(),
                  let applicationURL = knownApplicationURL(inNativeValue: representation)
            else { continue }
            return applicationURL
        }
        return nil
    }

    func logUnresolvedApplicationMenu(_ menu: NSMenu?) {
        let itemCount = menu?.items.count ?? 0
        let inventoryCount = currentApplicationsByPath.count
        CornerlightTrace.lifecycle.error(
            "app menu unresolved items=\(itemCount, privacy: .public) inventory=\(inventoryCount, privacy: .public)",
        )
    }

    private func knownApplicationURL(inNativeValue value: Any) -> URL? {
        if let url = value as? URL,
           let application = currentApplicationsByPath[url.standardizedFileURL.path] {
            return application.url
        }
        if let string = value as? String,
           let url = URL(string: string),
           url.isFileURL,
           let application = currentApplicationsByPath[url.standardizedFileURL.path] {
            return application.url
        }
        if let dictionary = value as? NSDictionary {
            for nestedValue in dictionary.allValues {
                if let applicationURL = knownApplicationURL(inNativeValue: nestedValue) {
                    return applicationURL
                }
            }
        }
        if let array = value as? NSArray {
            for nestedValue in array {
                if let applicationURL = knownApplicationURL(inNativeValue: nestedValue) {
                    return applicationURL
                }
            }
        }
        return nil
    }

    func configureViewOptionsMenu(_ menu: NSMenu) {
        configureVisibilityOption(in: menu)
        configureUpdateAndSettingsOptions(in: menu)
        configureQuitOption(in: menu)
    }

    private func configureVisibilityOption(in menu: NSMenu) {
        let visibilityIdentifier = NSUserInterfaceItemIdentifier(
            "com.emrikol.Cornerlight.showHiddenApplications",
        )
        if let item = menu.items.first(where: { $0.identifier == visibilityIdentifier }) {
            item.state = showsHiddenApplications ? .on : .off
        } else {
            if !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false {
                menu.addItem(.separator())
            }
            let item = NSMenuItem(
                title: "Show Hidden Apps",
                action: #selector(SpotlightNativeMenuActionTarget.toggleShowsHiddenApplications(_:)),
                keyEquivalent: "",
            )
            item.identifier = visibilityIdentifier
            item.state = showsHiddenApplications ? .on : .off
            item.target = menuActionTarget
            menu.addItem(item)
        }
    }

    private func configureUpdateAndSettingsOptions(in menu: NSMenu) {
        let updateIdentifier = NSUserInterfaceItemIdentifier(
            "com.emrikol.Cornerlight.checkForUpdates",
        )
        let settingsIdentifier = NSUserInterfaceItemIdentifier("com.emrikol.Cornerlight.openSettings")
        let needsUpdateItem = !menu.items.contains { $0.identifier == updateIdentifier }
        let needsSettingsItem = !menu.items.contains { $0.identifier == settingsIdentifier }
        guard needsUpdateItem || needsSettingsItem else { return }

        if menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }
        if needsUpdateItem {
            let updateItem = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(SpotlightNativeMenuActionTarget.checkForUpdates(_:)),
                keyEquivalent: "",
            )
            updateItem.identifier = updateIdentifier
            updateItem.target = menuActionTarget
            menu.addItem(updateItem)
        }
        if needsSettingsItem {
            let settingsItem = NSMenuItem(
                title: "Settings…",
                action: #selector(SpotlightNativeMenuActionTarget.openSettings(_:)),
                keyEquivalent: ",",
            )
            settingsItem.identifier = settingsIdentifier
            settingsItem.keyEquivalentModifierMask = .command
            settingsItem.target = menuActionTarget
            menu.addItem(settingsItem)
        }
    }

    private func configureQuitOption(in menu: NSMenu) {
        let identifier = NSUserInterfaceItemIdentifier("com.emrikol.Cornerlight.quit")
        guard !menu.items.contains(where: { $0.identifier == identifier }) else { return }
        if menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }
        let item = NSMenuItem(
            title: "Quit Cornerlight",
            action: #selector(SpotlightNativeMenuActionTarget.quitApplication(_:)),
            keyEquivalent: "q",
        )
        item.identifier = identifier
        item.keyEquivalentModifierMask = .command
        item.target = menuActionTarget
        menu.addItem(item)
    }

    func setShowsHiddenApplications(_ showsHiddenApplications: Bool) {
        self.showsHiddenApplications = showsHiddenApplications
    }

    func toggleApplicationPin(_ applicationURL: URL) {
        let pinned = isApplicationPinned?(applicationURL) ?? false
        onSetApplicationPinned?(applicationURL, !pinned)
    }

    func toggleApplicationVisibility(_ applicationURL: URL) {
        let hidden = isApplicationHidden?(applicationURL) ?? false
        onSetApplicationHidden?(applicationURL, !hidden)
    }

    func toggleShowsHiddenApplications(_ sender: NSMenuItem) {
        showsHiddenApplications.toggle()
        sender.state = showsHiddenApplications ? .on : .off
        onSetShowsHiddenApplications?(showsHiddenApplications)
    }

    func openSettings() {
        onOpenSettings?()
    }

    func checkForUpdates() {
        onCheckForUpdates?()
    }

    func quitApplication() {
        onQuit?()
    }

    func resetQuery() {
        Self.call(true, on: viewController, selector: "goToAppsSearchWithResetQuery:")
        searchField.stringValue = ""
    }

    func purgeMemory() {
        _ = topHitResultsController.perform(NSSelectorFromString("purgeMemory"))
        _ = resultsController.perform(NSSelectorFromString("purgeMemory"))
    }

    private func scheduleDismissalCallback() {
        guard !dismissalCallbackScheduled else { return }
        dismissalCallbackScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            dismissalCallbackScheduled = false
            guard !panel.isVisible else { return }
            completeLifecycleDismissal()
            onNativeDismiss?()
        }
    }

    private func beginLifecycleDismissal() {
        endPinnedApplicationPointerReorder()
        let token = transitionGate.supersedeWithDismissal()
        lifecycleLease.begin(token)
    }

    private func completeLifecycleDismissal() {
        guard let token = lifecycleLease.takeDismissalToken() else { return }
        CornerlightTrace.lifecycle.notice("native Spotlight lifecycle hide completed")
        nativeTransitionDidComplete(token)
    }

    private func makeSection(
        title: String,
        identifier: String,
        style: Int32,
        applications: [ApplicationRecord],
    ) -> AnyObject? {
        guard !applications.isEmpty,
              let identityClass = NSClassFromString("ATXAppIdentity"),
              let builderClass = NSClassFromString("SPUISAppBrowseSectionBuilder")
        else { return nil }

        let identities: [AnyObject] = applications.compactMap { application in
            let identityClassObject = identityClass as AnyObject
            guard let allocated = identityClassObject
                .perform(NSSelectorFromString("alloc"))?
                .takeUnretainedValue()
            else { return nil }
            let selector = NSSelectorFromString("initWithBundleURL:")
            return unsafeBitCast(
                allocated.method(for: selector),
                to: IdentityInitializer.self,
            )(
                allocated,
                selector,
                application.url as NSURL,
            )?.takeRetainedValue()
        }
        guard identities.count == applications.count else { return nil }

        let selector = NSSelectorFromString(
            "appSectionWithTitle:identifier:style:appIdentities:",
        )
        let builderClassObject = builderClass as AnyObject
        return unsafeBitCast(
            builderClassObject.method(for: selector),
            to: SectionBuilder.self,
        )(
            builderClassObject,
            selector,
            title as NSString,
            identifier as NSString,
            style,
            identities as NSArray,
        )?.takeUnretainedValue()
    }

    private func tagSuggestionResults(in section: AnyObject) {
        let resultsSelector = NSSelectorFromString("results")
        let bundleIdentifierSelector = NSSelectorFromString("setSectionBundleIdentifier:")
        guard let results = section.perform(resultsSelector)?.takeUnretainedValue() as? NSArray
        else { return }
        for case let result as AnyObject in results where result.responds(to: bundleIdentifierSelector) {
            Self.setObject(
                "com.apple.spotlight.zkw" as NSString,
                on: result,
                selector: "setSectionBundleIdentifier:",
            )
        }
    }

    private static func firstDescendant<View: NSView>(
        of _: View.Type,
        in root: NSView,
    ) -> View? {
        if let root = root as? View {
            return root
        }
        for subview in root.subviews {
            if let match = firstDescendant(of: View.self, in: subview) {
                return match
            }
        }
        return nil
    }

    private static func firstDescendant(named className: String, in root: NSView) -> NSView? {
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

    private static func snapshot(_ view: NSView) -> NSImage? {
        guard view.bounds.width > 0,
              view.bounds.height > 0,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: representation)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(representation)
        return image
    }

    private static func makePinnedBadgeImage() -> AnyObject? {
        guard let symbol = NSImage(
            systemSymbolName: "pin.fill",
            accessibilityDescription: "Pinned",
        ),
            let imageClass = NSClassFromString("TLKImage")
        else { return nil }
        let imageClassObject = imageClass as AnyObject
        guard let allocated = imageClassObject
            .perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue()
        else { return nil }
        return allocated.perform(
            NSSelectorFromString("initWithImage:"),
            with: symbol,
        )?.takeRetainedValue()
    }

    private static func objectIvar(named name: String, on object: AnyObject) -> AnyObject? {
        guard let ivar = class_getInstanceVariable(type(of: object), name),
              let rawValue = Unmanaged.passUnretained(object).toOpaque()
              .advanced(by: ivar_getOffset(ivar))
              .load(as: UnsafeRawPointer?.self)
        else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(rawValue).takeUnretainedValue()
    }

    private static func set(_ value: Bool, on object: AnyObject, selector name: String) {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return }
        unsafeBitCast(object.method(for: selector), to: BoolSetter.self)(object, selector, value)
    }

    private static func call(_ value: Bool, on object: AnyObject, selector name: String) {
        set(value, on: object, selector: name)
    }

    private static func setObject(_ value: AnyObject?, on object: AnyObject, selector name: String) {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return }
        typealias ObjectSetter = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        unsafeBitCast(object.method(for: selector), to: ObjectSetter.self)(object, selector, value)
    }
}

enum LauncherStartupPolicy {
    static func shouldShowLauncher(
        arguments: [String],
        launchAtLoginEnabled: Bool = false,
    ) -> Bool {
        if arguments.contains("--show") {
            return true
        }
        if arguments.contains("--background") {
            return false
        }
        return !launchAtLoginEnabled
    }
}

enum LauncherInvocationKind: Equatable {
    case explicit
    case hotCorner
}

enum LauncherInvocationAction: Equatable {
    case present
    case toggle
    case explainInputMonitoring
}

enum LauncherInvocationPolicy {
    static func action(
        kind: LauncherInvocationKind,
        isLauncherPresented: Bool,
        inputMonitoringGranted: Bool,
    ) -> LauncherInvocationAction {
        if kind == .hotCorner {
            if isLauncherPresented {
                return .toggle
            }
            return inputMonitoringGranted ? .toggle : .explainInputMonitoring
        }
        return inputMonitoringGranted ? .present : .explainInputMonitoring
    }
}

enum InputMonitoringPermissionContent {
    static let messageText = "Cornerlight Needs Input Monitoring"
    static let informativeText = """
    Cornerlight needs Input Monitoring to reproduce Spotlight's keyboard-focus behavior and to dismiss when you click \
    outside the launcher.

    Cornerlight observes only mouse clicks while the launcher is open. It does not monitor system-wide keystrokes.
    """
    static let openButtonTitle = "Open Input Monitoring"
    static let cancelButtonTitle = "Not Now"
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
    )!
}

enum InputMonitoringPermissionRequestResult: Equatable {
    case granted
    case settingsOpened(Bool)
}

enum InputMonitoringPermissionRequestFlow {
    static func perform(
        requestAccess: () -> Bool,
        preflightAccess: () -> Bool,
        openSettings: (URL) -> Bool,
    ) -> InputMonitoringPermissionRequestResult {
        if requestAccess() || preflightAccess() {
            return .granted
        }
        return .settingsOpened(openSettings(InputMonitoringPermissionContent.settingsURL))
    }
}

struct InputMonitoringPromptPresentationState {
    private(set) var isPresenting = false

    mutating func begin() -> Bool {
        guard !isPresenting else { return false }
        isPresenting = true
        return true
    }

    mutating func finish() {
        isPresenting = false
    }
}

@MainActor
final class InputMonitoringPromptController {
    private var presentationState = InputMonitoringPromptPresentationState()

    var isGranted: Bool {
        CGPreflightListenEventAccess()
    }

    func present(onGranted: @escaping @MainActor () -> Void) {
        guard presentationState.begin() else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = InputMonitoringPermissionContent.messageText
        alert.informativeText = InputMonitoringPermissionContent.informativeText
        alert.addButton(withTitle: InputMonitoringPermissionContent.openButtonTitle)
        alert.addButton(withTitle: InputMonitoringPermissionContent.cancelButtonTitle)

        NSApp.activate()
        let response = alert.runModal()
        presentationState.finish()

        guard response == .alertFirstButtonReturn else {
            NSApp.deactivate()
            return
        }

        let result = InputMonitoringPermissionRequestFlow.perform(
            requestAccess: { CGRequestListenEventAccess() },
            preflightAccess: { CGPreflightListenEventAccess() },
            openSettings: { NSWorkspace.shared.open($0) },
        )
        switch result {
        case .granted:
            onGranted()
        case let .settingsOpened(didOpen):
            if !didOpen {
                NSApp.deactivate()
            }
        }
    }
}

@MainActor
protocol LauncherPresenting: AnyObject {
    var isPresented: Bool { get }

    func show()
    func toggle()
    func dismiss()
    func dismiss(reason: Int, completion: (() -> Void)?)
    func applicationLostFocus()
}

@MainActor
final class LauncherPresentationCoordinator {
    typealias Factory = @MainActor () -> any LauncherPresenting

    private let makeLauncher: Factory
    private var launcher: (any LauncherPresenting)?

    init(makeLauncher: @escaping Factory) {
        self.makeLauncher = makeLauncher
    }

    var hasLauncher: Bool {
        launcher != nil
    }

    var isLauncherPresented: Bool {
        launcher?.isPresented ?? false
    }

    func showLauncher() {
        if launcher == nil {
            launcher = makeLauncher()
        }
        guard launcher?.isPresented != true else { return }
        launcher?.show()
    }

    func toggleLauncher() {
        if launcher == nil {
            launcher = makeLauncher()
        }
        launcher?.toggle()
    }

    func applicationLostFocus() {
        launcher?.applicationLostFocus()
    }

    func dismissLauncher() {
        guard let launcher, launcher.isPresented else { return }
        launcher.dismiss()
    }

    func dismissLauncher(reason: Int, completion: (() -> Void)?) {
        guard let launcher, launcher.isPresented else {
            completion?()
            return
        }
        launcher.dismiss(reason: reason, completion: completion)
    }

    func shutdown() {
        launcher = nil
    }
}

@MainActor
private final class LauncherWindowController: NSObject, LauncherPresenting {
    var onOpenSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onQuit: (() -> Void)?

    private let nativeUI: SpotlightNativeLauncherUI
    private let recentApplicationStore: LauncherRecentApplicationStore
    private let pinnedApplicationStore: LauncherPinnedApplicationStore
    private let hiddenApplicationStore: LauncherHiddenApplicationStore
    private let applicationCatalogService: ApplicationCatalogService
    private var applications: [ApplicationRecord] = []
    private var suggestionBundleIdentifiers: [String] = []
    private var filteredApplications: [ApplicationRecord] = []
    private var contentLease = LauncherContentLease()
    private var showsHiddenApplications = false
    private var opensSettingsAfterDismissal = false
    private var checksForUpdatesAfterDismissal = false

    override convenience init() {
        self.init(
            recentApplicationStore: LauncherRecentApplicationStore(),
            pinnedApplicationStore: LauncherPinnedApplicationStore(),
            hiddenApplicationStore: LauncherHiddenApplicationStore(),
            applicationCatalogService: ApplicationCatalogService(),
        )
    }

    init(
        recentApplicationStore: LauncherRecentApplicationStore,
        pinnedApplicationStore: LauncherPinnedApplicationStore = LauncherPinnedApplicationStore(),
        hiddenApplicationStore: LauncherHiddenApplicationStore = LauncherHiddenApplicationStore(),
        applicationCatalogService: ApplicationCatalogService,
    ) {
        guard let nativeUI = SpotlightNativeLauncherUI() else {
            fatalError("macOS 26.6 Spotlight launcher UI is unavailable")
        }
        self.nativeUI = nativeUI
        self.recentApplicationStore = recentApplicationStore
        self.pinnedApplicationStore = pinnedApplicationStore
        self.hiddenApplicationStore = hiddenApplicationStore
        self.applicationCatalogService = applicationCatalogService
        applications = applicationCatalogService.applications
        showsHiddenApplications = hiddenApplicationStore.showsHiddenApplications
        super.init()
        configureCallbacks()
        nativeUI.setShowsHiddenApplications(showsHiddenApplications)
    }

    var isPresented: Bool {
        nativeUI.isPresented
    }

    func show() {
        guard !nativeUI.isPresented else { return }
        CornerlightTrace.lifecycle.notice("native Spotlight presentation show")
        prepareForPresentation()
        nativeUI.invoke()
    }

    func toggle() {
        let wasPresented = nativeUI.isPresented
        CornerlightTrace.lifecycle.notice(
            "native Spotlight app-delegate toggle presented=\(wasPresented, privacy: .public)",
        )
        if !wasPresented {
            prepareForPresentation()
        }
        nativeUI.invoke()
    }

    func dismiss() {
        hide()
    }

    func dismiss(reason: Int, completion: (() -> Void)?) {
        guard nativeUI.isPresented else {
            completion?()
            return
        }
        CornerlightTrace.lifecycle.notice(
            "native Spotlight reasoned hide reason=\(reason, privacy: .public)",
        )
        nativeUI.dismiss(reason: reason) {
            CornerlightTrace.lifecycle.notice(
                "native Spotlight reasoned hide completed reason=\(reason, privacy: .public)",
            )
            completion?()
        }
    }

    func applicationLostFocus() {
        CornerlightTrace.lifecycle.notice("native Spotlight app-delegate focus loss")
        nativeUI.applicationLostFocus()
    }

    func writeSnapshot(to url: URL) throws {
        let panel = nativeUI.panel
        guard let contentView = panel.contentView else { return }
        let previousAppearance = panel.appearance
        panel.appearance = NSAppearance(named: .darkAqua)
        defer { panel.appearance = previousAppearance }

        applications = ApplicationCatalog.scan()
        prepareContent()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        contentView.layoutSubtreeIfNeeded()
        contentView.display()

        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds),
              let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
        else { throw CocoaError(.fileWriteUnknown) }
        contentView.displayIgnoringOpacity(contentView.bounds, in: graphicsContext)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }

    private func hide() {
        guard nativeUI.isPresented else { return }
        CornerlightTrace.lifecycle.notice("native Spotlight presentation hide")
        nativeUI.dismiss()
    }

    private func prepareForPresentation() {
        contentLease.prepare()
        prepareContent()
    }

    private func finishNativeDismissal() {
        let retainsForQueuedPresentation = nativeUI
            .consumeQueuedPresentationContentRetention()
        guard contentLease.finishDismissal(
            retainsForQueuedPresentation: retainsForQueuedPresentation,
        ) else {
            if retainsForQueuedPresentation {
                CornerlightTrace.lifecycle.notice(
                    "native Spotlight dismissal retained content for queued reopen",
                )
            }
            return
        }
        let shouldOpenSettings = opensSettingsAfterDismissal
        let shouldCheckForUpdates = checksForUpdatesAfterDismissal
        opensSettingsAfterDismissal = false
        checksForUpdatesAfterDismissal = false
        CornerlightTrace.lifecycle.notice("native Spotlight dismissal finalized")
        releaseDismissedContent()
        if shouldOpenSettings {
            CornerlightTrace.lifecycle.notice("settings handoff after native dismissal")
            onOpenSettings?()
        } else if shouldCheckForUpdates {
            CornerlightTrace.lifecycle.notice("update handoff after native dismissal")
            onCheckForUpdates?()
        }
    }

    private func requestSettings() {
        CornerlightTrace.lifecycle.notice("settings requested from native launcher")
        guard nativeUI.isPresented else {
            onOpenSettings?()
            return
        }
        opensSettingsAfterDismissal = true
        hide()
    }

    private func requestUpdateCheck() {
        CornerlightTrace.lifecycle.notice("update check requested from native launcher")
        guard nativeUI.isPresented else {
            onCheckForUpdates?()
            return
        }
        checksForUpdatesAfterDismissal = true
        hide()
    }

    private func prepareContent() {
        nativeUI.resetQuery()
        refreshSuggestions()
        applyFilter()
    }

    private func catalogDidUpdate(_ applications: [ApplicationRecord]) {
        self.applications = applications
        guard contentLease.isLoaded else { return }
        refreshSuggestions()
        applyFilter()
    }

    private func refreshSuggestions() {
        suggestionBundleIdentifiers = LauncherSuggestionPolicy.prioritizedBundleIdentifiers(
            localRecents: recentApplicationStore.bundleIdentifiers,
            systemSuggestions: SpotlightApplicationSuggestionService.cachedBundleIdentifiers(),
        )
    }

    private func applyFilter() {
        let hiddenApplicationPaths = hiddenApplicationStore.hiddenApplicationPaths
        let visibleInventory = LauncherApplicationVisibilityPolicy.applications(
            in: applications,
            hiddenApplicationPaths: hiddenApplicationPaths,
            showsHiddenApplications: showsHiddenApplications,
        )
        let visibleSuggestionCandidates = LauncherSuggestionPolicy.applications(
            in: visibleInventory,
            pinnedApplicationPaths: pinnedApplicationStore.applicationPaths,
            matching: suggestionBundleIdentifiers,
        )
        filteredApplications = LauncherContentPolicy.visibleCatalog(
            applications: visibleInventory,
            suggestions: visibleSuggestionCandidates,
            query: nativeUI.searchField.stringValue,
        )
        let visibleSuggestions = nativeUI.searchField.stringValue.isEmpty
            ? visibleSuggestionCandidates
            : []
        nativeUI.update(
            suggestions: visibleSuggestions,
            applications: filteredApplications,
        )
    }

    private func releaseDismissedContent() {
        suggestionBundleIdentifiers.removeAll(keepingCapacity: false)
        filteredApplications.removeAll(keepingCapacity: false)
        nativeUI.update(
            suggestions: [],
            applications: [],
        )
        nativeUI.purgeMemory()
    }
}

private extension LauncherWindowController {
    func configureCallbacks() {
        applicationCatalogService.onUpdate = { [weak self] applications in
            self?.catalogDidUpdate(applications)
        }
        nativeUI.onQueryChange = { [weak self] in
            self?.applyFilter()
        }
        nativeUI.onNativeDismiss = { [weak self] in
            self?.finishNativeDismissal()
        }
        configurePinCallbacks()
        configureVisibilityCallbacks()
        nativeUI.onOpenSettings = { [weak self] in
            self?.requestSettings()
        }
        nativeUI.onCheckForUpdates = { [weak self] in
            self?.requestUpdateCheck()
        }
        nativeUI.onQuit = { [weak self] in
            self?.onQuit?()
        }
    }

    func configurePinCallbacks() {
        nativeUI.isApplicationPinned = { [weak self] applicationURL in
            self?.pinnedApplicationStore.isPinned(applicationURL) ?? false
        }
        nativeUI.canPinApplication = { [weak self] applicationURL in
            self?.canPin(applicationURL) ?? false
        }
        nativeUI.onSetApplicationPinned = { [weak self] applicationURL, pinned in
            guard let self else { return }
            if pinned {
                pinnedApplicationStore.removeUnavailableApplications(in: applications)
            }
            pinnedApplicationStore.setPinned(pinned, applicationURL: applicationURL)
            applyFilter()
        }
        nativeUI.onMovePinnedApplication = { [weak self] url, index, visibleURLs in
            guard let self else { return }
            pinnedApplicationStore.move(
                applicationURL: url,
                toVisibleInsertionIndex: index,
                visibleApplicationURLs: visibleURLs,
            )
            applyFilter()
        }
    }

    func configureVisibilityCallbacks() {
        nativeUI.isApplicationHidden = { [weak self] applicationURL in
            self?.hiddenApplicationStore.isHidden(applicationURL) ?? false
        }
        nativeUI.onSetApplicationHidden = { [weak self] applicationURL, hidden in
            guard let self else { return }
            hiddenApplicationStore.setHidden(hidden, applicationURL: applicationURL)
            applyFilter()
        }
        nativeUI.onSetShowsHiddenApplications = { [weak self] showsHidden in
            guard let self else { return }
            showsHiddenApplications = showsHidden
            hiddenApplicationStore.setShowsHiddenApplications(showsHidden)
            nativeUI.setShowsHiddenApplications(showsHidden)
            applyFilter()
        }
    }

    func canPin(_ applicationURL: URL) -> Bool {
        if pinnedApplicationStore.isPinned(applicationURL) {
            return true
        }
        let availablePaths = Set(applications.map(\.url.standardizedFileURL.path))
        let availablePinCount = pinnedApplicationStore.applicationPaths.count {
            availablePaths.contains($0)
        }
        return availablePinCount < LauncherSuggestionPolicy.maximumCount
    }
}

// MARK: - Settings

enum LauncherLoginItemStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

enum LauncherLoginItemAction: Equatable {
    case none
    case register
    case unregister
    case openSystemSettings
}

enum LauncherLoginItemActionPolicy {
    static func action(
        enabling: Bool,
        status: LauncherLoginItemStatus,
    ) -> LauncherLoginItemAction {
        if enabling {
            return switch status {
            case .disabled: .register
            case .requiresApproval: .openSystemSettings
            case .enabled, .unavailable: .none
            }
        }
        return switch status {
        case .enabled, .requiresApproval: .unregister
        case .disabled, .unavailable: .none
        }
    }
}

struct LauncherLoginItemPresentation: Equatable {
    let isEnabled: Bool
    let message: String
    let isError: Bool

    static func content(
        for status: LauncherLoginItemStatus,
        errorMessage: String? = nil,
    ) -> LauncherLoginItemPresentation {
        if let errorMessage {
            return LauncherLoginItemPresentation(
                isEnabled: status == .enabled,
                message: "Couldn’t update Login Items: \(errorMessage)",
                isError: true,
            )
        }
        return switch status {
        case .disabled:
            LauncherLoginItemPresentation(
                isEnabled: false,
                message: "Start Cornerlight automatically when you log in.",
                isError: false,
            )
        case .enabled:
            LauncherLoginItemPresentation(
                isEnabled: true,
                message: "Starts quietly in the background when you log in.",
                isError: false,
            )
        case .requiresApproval:
            LauncherLoginItemPresentation(
                isEnabled: false,
                message: "Approval is required in System Settings → General → Login Items.",
                isError: false,
            )
        case .unavailable:
            LauncherLoginItemPresentation(
                isEnabled: false,
                message: "Launch at Login is unavailable on this system.",
                isError: true,
            )
        }
    }
}

@MainActor
final class LauncherLoginItemService {
    enum EnableResult: Equatable {
        case updated
        case requiresApproval
    }

    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LauncherLoginItemStatus {
        Self.loginItemStatus(for: service.status)
    }

    static func loginItemStatus(for serviceStatus: SMAppService.Status) -> LauncherLoginItemStatus {
        switch serviceStatus {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        // mainApp can transiently report notFound before its first registration. Registration is
        // the authoritative operation, so keep the control actionable and surface any real error.
        case .notFound: .disabled
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws -> EnableResult {
        switch LauncherLoginItemActionPolicy.action(enabling: enabled, status: status) {
        case .register:
            do {
                try service.register()
            } catch {
                if status == .requiresApproval {
                    return .requiresApproval
                }
                guard status == .enabled else { throw error }
            }
            return status == .requiresApproval ? .requiresApproval : .updated
        case .unregister:
            do {
                try service.unregister()
            } catch {
                guard status == .disabled else { throw error }
            }
            return .updated
        case .openSystemSettings:
            return .requiresApproval
        case .none:
            return .updated
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

struct LauncherHiddenApplicationSetting: Equatable {
    let name: String
    let url: URL

    var path: String {
        url.standardizedFileURL.path
    }
}

enum LauncherHiddenApplicationSettingsPolicy {
    static func applications(for paths: Set<String>) -> [LauncherHiddenApplicationSetting] {
        paths.map { path in
            let url = URL(fileURLWithPath: path)
            return LauncherHiddenApplicationSetting(
                name: url.deletingPathExtension().lastPathComponent,
                url: url,
            )
        }
        .sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }
}

@MainActor
private final class LauncherHiddenApplicationCellView: NSTableCellView {
    private let appIconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let pathField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        appIconView.imageScaling = .scaleProportionallyUpOrDown
        appIconView.translatesAutoresizingMaskIntoConstraints = false

        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false

        pathField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pathField.textColor = .secondaryLabelColor
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.translatesAutoresizingMaskIntoConstraints = false

        let labels = NSStackView(views: [nameField, pathField])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.translatesAutoresizingMaskIntoConstraints = false

        addSubview(appIconView)
        addSubview(labels)
        imageView = appIconView
        textField = nameField

        NSLayoutConstraint.activate([
            appIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            appIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            appIconView.widthAnchor.constraint(equalToConstant: 30),
            appIconView.heightAnchor.constraint(equalToConstant: 30),
            labels.leadingAnchor.constraint(equalTo: appIconView.trailingAnchor, constant: 9),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with application: LauncherHiddenApplicationSetting) {
        nameField.stringValue = application.name
        pathField.stringValue = application.path
        toolTip = application.path
        if FileManager.default.fileExists(atPath: application.path) {
            appIconView.image = NSWorkspace.shared.icon(forFile: application.path)
        } else {
            appIconView.image = NSImage(
                systemSymbolName: "app.dashed",
                accessibilityDescription: application.name,
            )
        }
    }
}

/// The window owns one compact native settings surface.
@MainActor
private final class LauncherSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let hotCornerStore: LauncherHotCornerStore
    private let hiddenApplicationStore: LauncherHiddenApplicationStore
    private let loginItemService: LauncherLoginItemService
    private let availableCorners: () -> [LauncherHotCorner]
    private let onCornerChange: () -> Void
    private let automaticallyChecksForUpdates: () -> Bool
    private let setAutomaticallyChecksForUpdates: (Bool) -> Void
    private let launchAtLoginButton = NSButton(
        checkboxWithTitle: "Launch at Login",
        target: nil,
        action: nil,
    )
    private let loginItemStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let automaticUpdateButton = NSButton(
        checkboxWithTitle: "Automatically check for updates",
        target: nil,
        action: nil,
    )
    private let cornerPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hiddenTableView = NSTableView()
    private let emptyHiddenApplicationsLabel = NSTextField(
        labelWithString: "No hidden applications.",
    )
    private let unhideButton = NSButton(
        title: "Unhide",
        target: nil,
        action: nil,
    )
    private var hiddenApplications: [LauncherHiddenApplicationSetting] = []
    private var loginItemErrorMessage: String?

    init(
        hotCornerStore: LauncherHotCornerStore,
        hiddenApplicationStore: LauncherHiddenApplicationStore,
        loginItemService: LauncherLoginItemService,
        availableCorners: @escaping () -> [LauncherHotCorner],
        onCornerChange: @escaping () -> Void,
        automaticallyChecksForUpdates: @escaping () -> Bool,
        setAutomaticallyChecksForUpdates: @escaping (Bool) -> Void,
    ) {
        self.hotCornerStore = hotCornerStore
        self.hiddenApplicationStore = hiddenApplicationStore
        self.loginItemService = loginItemService
        self.availableCorners = availableCorners
        self.onCornerChange = onCornerChange
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.setAutomaticallyChecksForUpdates = setAutomaticallyChecksForUpdates

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 550),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
        )
        window.title = "Cornerlight Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("LaunchSettingsWindow")
        window.setContentSize(NSSize(width: 520, height: 550))
        window.center()

        super.init(window: window)
        window.delegate = self
        configureContent(in: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSettings() {
        loginItemErrorMessage = nil
        refreshLoginItemState()
        refreshAutomaticUpdateState()
        refreshAvailableCorners()
        refreshHiddenApplications()
        showWindow(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        let visible = window?.isVisible ?? false
        CornerlightTrace.lifecycle.notice("settings ordered front visible=\(visible, privacy: .public)")
    }

    func windowWillClose(_: Notification) {
        NSApp.deactivate()
    }

    func windowDidBecomeKey(_: Notification) {
        refreshLoginItemState()
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        do {
            let result = try loginItemService.setEnabled(sender.state == .on)
            loginItemErrorMessage = nil
            refreshLoginItemState()
            if result == .requiresApproval {
                loginItemService.openSystemSettings()
            }
        } catch {
            loginItemErrorMessage = error.localizedDescription
            refreshLoginItemState()
        }
    }

    @objc private func hotCornerChanged(_: NSPopUpButton) {
        guard let rawValue = cornerPopUp.selectedItem?.representedObject as? String,
              let corner = LauncherHotCorner(rawValue: rawValue),
              corner != hotCornerStore.selectedCorner
        else { return }
        hotCornerStore.selectedCorner = corner
        onCornerChange()
    }

    @objc private func automaticUpdateChanged(_ sender: NSButton) {
        setAutomaticallyChecksForUpdates(sender.state == .on)
        refreshAutomaticUpdateState()
    }

    @objc private func unhideSelectedApplications(_: NSButton) {
        let selectedApplications = hiddenTableView.selectedRowIndexes.compactMap { row in
            hiddenApplications.indices.contains(row) ? hiddenApplications[row] : nil
        }
        guard !selectedApplications.isEmpty else { return }
        for application in selectedApplications {
            hiddenApplicationStore.setHidden(false, applicationURL: application.url)
        }
        refreshHiddenApplications()
    }
}

private extension LauncherSettingsWindowController {
    private func configureContent(in window: NSWindow) {
        let contentView = NSView()
        window.contentView = contentView
        let generalGrid = makeGeneralGrid()
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        let hiddenApplicationsHeader = makeHiddenApplicationsHeader()
        let scrollView = makeHiddenApplicationsScrollView()

        emptyHiddenApplicationsLabel.textColor = .secondaryLabelColor
        emptyHiddenApplicationsLabel.translatesAutoresizingMaskIntoConstraints = false
        unhideButton.target = self
        unhideButton.action = #selector(unhideSelectedApplications(_:))
        unhideButton.isEnabled = false
        unhideButton.setAccessibilityLabel("Unhide selected applications")
        unhideButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [
            generalGrid,
            separator,
            hiddenApplicationsHeader,
            scrollView,
            emptyHiddenApplicationsLabel,
            unhideButton,
        ] {
            contentView.addSubview(view)
        }
        layoutContent(
            contentView,
            generalGrid: generalGrid,
            separator: separator,
            hiddenApplicationsHeader: hiddenApplicationsHeader,
            scrollView: scrollView,
        )
    }

    private func makeGeneralGrid() -> NSGridView {
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(launchAtLoginChanged(_:))
        launchAtLoginButton.setAccessibilityHelp(
            "Start Cornerlight quietly in the background when you log in.",
        )

        loginItemStatusLabel.textColor = .secondaryLabelColor
        loginItemStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        automaticUpdateButton.target = self
        automaticUpdateButton.action = #selector(automaticUpdateChanged(_:))
        automaticUpdateButton.setAccessibilityHelp(
            "Check Cornerlight's signed GitHub release feed for updates.",
        )

        let updateExplanation = NSTextField(
            wrappingLabelWithString: "Update checks contact GitHub. Cornerlight sends no analytics or telemetry.",
        )
        updateExplanation.textColor = .secondaryLabelColor

        let hotCornerLabel = NSTextField(labelWithString: "Hot Corner:")
        hotCornerLabel.alignment = .right
        hotCornerLabel.setContentHuggingPriority(.required, for: .horizontal)

        cornerPopUp.target = self
        cornerPopUp.action = #selector(hotCornerChanged(_:))
        cornerPopUp.translatesAutoresizingMaskIntoConstraints = false

        let explanation = NSTextField(
            wrappingLabelWithString: "Corners assigned in System Settings are unavailable.",
        )
        explanation.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [NSGridCell.emptyContentView, launchAtLoginButton],
            [NSGridCell.emptyContentView, loginItemStatusLabel],
            [NSGridCell.emptyContentView, automaticUpdateButton],
            [NSGridCell.emptyContentView, updateExplanation],
            [hotCornerLabel, cornerPopUp],
            [NSGridCell.emptyContentView, explanation],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    private func makeHiddenApplicationsHeader() -> NSStackView {
        let hiddenApplicationsLabel = NSTextField(labelWithString: "Hidden Apps")
        hiddenApplicationsLabel.font = .systemFont(
            ofSize: NSFont.systemFontSize,
            weight: .semibold,
        )
        hiddenApplicationsLabel.translatesAutoresizingMaskIntoConstraints = false

        let hiddenApplicationsExplanation = NSTextField(
            labelWithString: "Hidden apps are excluded from browsing and search.",
        )
        hiddenApplicationsExplanation.textColor = .secondaryLabelColor
        let header = NSStackView(views: [hiddenApplicationsLabel, hiddenApplicationsExplanation])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 3
        header.translatesAutoresizingMaskIntoConstraints = false
        return header
    }

    private func makeHiddenApplicationsScrollView() -> NSScrollView {
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("HiddenApplication"))
        tableColumn.resizingMask = .autoresizingMask
        hiddenTableView.addTableColumn(tableColumn)
        hiddenTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        hiddenTableView.headerView = nil
        hiddenTableView.rowHeight = 44
        hiddenTableView.allowsMultipleSelection = true
        hiddenTableView.dataSource = self
        hiddenTableView.delegate = self
        hiddenTableView.setAccessibilityLabel("Hidden applications")

        let scrollView = NSScrollView()
        scrollView.documentView = hiddenTableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }

    private func layoutContent(
        _ contentView: NSView,
        generalGrid: NSGridView,
        separator: NSBox,
        hiddenApplicationsHeader: NSStackView,
        scrollView: NSScrollView,
    ) {
        NSLayoutConstraint.activate([
            generalGrid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            generalGrid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            generalGrid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            cornerPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            separator.topAnchor.constraint(equalTo: generalGrid.bottomAnchor, constant: 22),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            hiddenApplicationsHeader.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 18),
            hiddenApplicationsHeader.leadingAnchor.constraint(equalTo: separator.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: hiddenApplicationsHeader.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: separator.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: separator.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 180),
            emptyHiddenApplicationsLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyHiddenApplicationsLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            unhideButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            unhideButton.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            unhideButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
        ])
    }

    private func refreshLoginItemState() {
        let status = loginItemService.status
        let presentation = LauncherLoginItemPresentation.content(
            for: status,
            errorMessage: loginItemErrorMessage,
        )
        launchAtLoginButton.state = presentation.isEnabled ? .on : .off
        launchAtLoginButton.isEnabled = status != .unavailable
        loginItemStatusLabel.stringValue = presentation.message
        loginItemStatusLabel.textColor = presentation.isError ? .systemRed : .secondaryLabelColor
    }

    private func refreshAutomaticUpdateState() {
        automaticUpdateButton.state = automaticallyChecksForUpdates() ? .on : .off
    }

    private func refreshAvailableCorners() {
        let corners = availableCorners()
        cornerPopUp.removeAllItems()

        guard let effectiveCorner = LauncherHotCornerAvailability.effectiveCorner(
            preferred: hotCornerStore.selectedCorner,
            available: corners,
        ) else {
            cornerPopUp.addItem(withTitle: "No Available Corners")
            cornerPopUp.isEnabled = false
            onCornerChange()
            return
        }

        cornerPopUp.isEnabled = true
        for corner in corners {
            let item = NSMenuItem(title: corner.displayName, action: nil, keyEquivalent: "")
            item.representedObject = corner.rawValue
            cornerPopUp.menu?.addItem(item)
        }
        if effectiveCorner != hotCornerStore.selectedCorner {
            hotCornerStore.selectedCorner = effectiveCorner
            onCornerChange()
        }
        cornerPopUp.selectItem(
            withTitle: effectiveCorner.displayName,
        )
    }

    private func refreshHiddenApplications() {
        hiddenApplications = LauncherHiddenApplicationSettingsPolicy.applications(
            for: hiddenApplicationStore.hiddenApplicationPaths,
        )
        hiddenTableView.reloadData()
        emptyHiddenApplicationsLabel.isHidden = !hiddenApplications.isEmpty
        unhideButton.isEnabled = false
    }
}

extension LauncherSettingsWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in _: NSTableView) -> Int {
        hiddenApplications.count
    }

    func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard hiddenApplications.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("HiddenApplicationCell")
        let cell = hiddenTableView.makeView(withIdentifier: identifier, owner: self)
            as? LauncherHiddenApplicationCellView ?? LauncherHiddenApplicationCellView()
        cell.identifier = identifier
        cell.configure(with: hiddenApplications[row])
        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        unhideButton.isEnabled = !hiddenTableView.selectedRowIndexes.isEmpty
    }
}

// MARK: - App lifecycle

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recentApplicationStore = LauncherRecentApplicationStore()
    private let pinnedApplicationStore = LauncherPinnedApplicationStore()
    private let hiddenApplicationStore = LauncherHiddenApplicationStore()
    private let hotCornerStore = LauncherHotCornerStore()
    private let applicationCatalogService = ApplicationCatalogService()
    private let loginItemService = LauncherLoginItemService()
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil,
    )
    private lazy var launcherCoordinator = LauncherPresentationCoordinator {
        let launcher = LauncherWindowController(
            recentApplicationStore: self.recentApplicationStore,
            pinnedApplicationStore: self.pinnedApplicationStore,
            hiddenApplicationStore: self.hiddenApplicationStore,
            applicationCatalogService: self.applicationCatalogService,
        )
        launcher.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        launcher.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates()
        }
        launcher.onQuit = {
            NSApp.terminate(nil)
        }
        return launcher
    }

    private let inputMonitoringPermission = InputMonitoringPromptController()
    private var recentApplicationObserver: LauncherRecentApplicationObserver?
    private var applicationDirectoryMonitor: ApplicationCatalogDirectoryMonitor?
    private var hotCorner: HotCornerController?
    private var settingsWindowController: LauncherSettingsWindowController?

    func applicationDidFinishLaunching(_: Notification) {
        if let snapshotURL = snapshotURLFromArguments() {
            do {
                let renderer = LauncherWindowController()
                try renderer.writeSnapshot(to: snapshotURL)
                print("Wrote \(snapshotURL.path)")
            } catch {
                FileHandle.standardError.write(Data("Snapshot failed: \(error)\n".utf8))
            }
            NSApp.terminate(nil)
            return
        }

        LauncherProcessLifetimePolicy.makeResident {
            ProcessInfo.processInfo.disableAutomaticTermination($0)
        }
        let directoryMonitor = ApplicationCatalogDirectoryMonitor(
            roots: ApplicationCatalog.defaultRoots,
        ) { [weak self] in
            self?.applicationCatalogService.applicationRootsDidChange()
        }
        if directoryMonitor.start() {
            applicationDirectoryMonitor = directoryMonitor
        } else {
            CornerlightTrace.lifecycle.error("application directory FSEvents monitor unavailable")
        }
        applicationCatalogService.start()

        let observer = LauncherRecentApplicationObserver(store: recentApplicationStore)
        observer.start()
        recentApplicationObserver = observer
        installHotCorner()
        if UserDefaults.standard.bool(forKey: "SUEnableAutomaticChecks") {
            _ = updaterController
        }

        // An explicit launch should show the UI. Login-item launches remain quiet.
        if LauncherStartupPolicy.shouldShowLauncher(
            arguments: CommandLine.arguments,
            launchAtLoginEnabled: loginItemService.status == .enabled,
        ) {
            invokeLauncher(kind: .explicit)
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        invokeLauncher(kind: .explicit)
        return true
    }

    func applicationWillTerminate(_: Notification) {
        applicationDirectoryMonitor?.stop()
        applicationDirectoryMonitor = nil
        applicationCatalogService.stop()
        recentApplicationObserver?.stop()
        recentApplicationObserver = nil
        hotCorner?.shutdown()
        hotCorner = nil
        settingsWindowController?.close()
        settingsWindowController = nil
        launcherCoordinator.shutdown()
    }

    /// These are the only delegate messages sent by SPApplication.sendEvent: before it
    /// performs Spotlight's own paired focus release and deactivation.
    @objc(applicationLostFocus)
    func spotlightApplicationLostFocus() {
        launcherCoordinator.applicationLostFocus()
    }

    @objc(dismissSpotlightWithReason:completion:)
    func dismissSpotlight(withReason reason: Int, completion: (() -> Void)?) {
        launcherCoordinator.dismissLauncher(reason: reason, completion: completion)
    }

    private func invokeLauncher(kind: LauncherInvocationKind) {
        let isPresented = launcherCoordinator.isLauncherPresented
        let kindDescription = String(describing: kind)
        let action = LauncherInvocationPolicy.action(
            kind: kind,
            isLauncherPresented: isPresented,
            inputMonitoringGranted: inputMonitoringPermission.isGranted,
        )
        let actionDescription = String(describing: action)
        CornerlightTrace.lifecycle.notice(
            "invoke \(kindDescription, privacy: .public)->\(actionDescription, privacy: .public)",
        )
        switch action {
        case .present:
            launcherCoordinator.showLauncher()
        case .toggle:
            launcherCoordinator.toggleLauncher()
        case .explainInputMonitoring:
            inputMonitoringPermission.present { [weak self] in
                self?.launcherCoordinator.showLauncher()
            }
        }
    }

    private func installHotCorner() {
        hotCorner?.shutdown()
        hotCorner = nil

        let availableCorners = LauncherSystemHotCornerAssignments.availableCorners()
        guard let corner = LauncherHotCornerAvailability.effectiveCorner(
            preferred: hotCornerStore.selectedCorner,
            available: availableCorners,
        ) else {
            CornerlightTrace.lifecycle.error("no unassigned macOS Hot Corner is available")
            return
        }
        if corner != hotCornerStore.selectedCorner {
            hotCornerStore.selectedCorner = corner
        }
        hotCorner = HotCornerController(corner: corner) { [weak self] in
            self?.invokeLauncher(kind: .hotCorner)
        }
    }

    private func showSettings() {
        CornerlightTrace.lifecycle.notice("settings window requested")
        if settingsWindowController == nil {
            settingsWindowController = LauncherSettingsWindowController(
                hotCornerStore: hotCornerStore,
                hiddenApplicationStore: hiddenApplicationStore,
                loginItemService: loginItemService,
                availableCorners: LauncherSystemHotCornerAssignments.availableCorners,
                onCornerChange: { [weak self] in
                    self?.installHotCorner()
                },
                automaticallyChecksForUpdates: { [weak self] in
                    self?.updaterController.updater.automaticallyChecksForUpdates ?? false
                },
                setAutomaticallyChecksForUpdates: { [weak self] enabled in
                    self?.updaterController.updater.automaticallyChecksForUpdates = enabled
                },
            )
        }
        settingsWindowController?.showSettings()
    }

    private func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    private func snapshotURLFromArguments() -> URL? {
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "--snapshot") else { return nil }
        let pathIndex = CommandLine.arguments.index(after: flagIndex)
        guard CommandLine.arguments.indices.contains(pathIndex) else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[pathIndex])
    }
}

let application = SpotlightExecutableRuntime.sharedApplication()
private let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
