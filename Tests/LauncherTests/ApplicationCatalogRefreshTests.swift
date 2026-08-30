@testable import Cornerlight
import Foundation
import Testing

struct ApplicationCatalogRefreshTests {
    @Test @MainActor
    func `catalog scans once at startup and only rescans after a change event`() async {
        let recorder = CatalogScanRecorder()
        let service = ApplicationCatalogService { isCancelled in
            recorder.scan(isCancelled: isCancelled)
        }
        defer { service.stop() }

        service.start()
        #expect(await waitUntil { service.applications.map(\.name) == ["Scan 1"] })
        #expect(recorder.count == 1)

        service.start()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(recorder.count == 1)

        service.applicationRootsDidChange()
        #expect(await waitUntil { service.applications.map(\.name) == ["Scan 2"] })
        #expect(recorder.count == 2)
    }

    @Test
    func `startup scan and change notifications coalesce into one current catalog`() {
        var state = ApplicationCatalogRefreshState()

        #expect(state.requestRefresh() == 1)
        #expect(state.requestRefresh() == nil)
        #expect(state.requestedRevision == 2)

        let obsoleteCompletion = state.finish(revision: 1)
        #expect(!obsoleteCompletion.acceptsResult)
        #expect(obsoleteCompletion.nextRevision == 2)

        let currentCompletion = state.finish(revision: 2)
        #expect(currentCompletion.acceptsResult)
        #expect(currentCompletion.nextRevision == nil)
    }

    @Test @MainActor
    func `a change notification cancels an obsolete scan before publishing the replacement`() async {
        let recorder = CancellationAwareCatalogScanRecorder()
        let service = ApplicationCatalogService { isCancelled in
            recorder.scan(isCancelled: isCancelled)
        }
        defer { service.stop() }

        service.start()
        #expect(await waitUntil { recorder.count == 1 })

        service.applicationRootsDidChange()
        #expect(await waitUntil { recorder.didCancelFirstScan })
        #expect(await waitUntil { service.applications.map(\.name) == ["Scan 2"] })
        #expect(recorder.count == 2)
    }

    @Test
    func `cancelled catalog scans stop before touching application roots`() {
        let applications = ApplicationCatalog.scan(
            roots: [URL(fileURLWithPath: "/Applications")],
            isCancelled: { true },
        )

        #expect(applications.isEmpty)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0 ..< 1000 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return false
    }
}

private final class CatalogScanRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int {
        lock.withLock { storedCount }
    }

    func scan(isCancelled: @Sendable () -> Bool) -> [ApplicationRecord] {
        guard !isCancelled() else { return [] }
        let count = lock.withLock {
            storedCount += 1
            return storedCount
        }
        return [
            ApplicationRecord(
                name: "Scan \(count)",
                url: URL(fileURLWithPath: "/Applications/Scan \(count).app"),
            ),
        ]
    }
}

private final class CancellationAwareCatalogScanRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0
    private var storedDidCancelFirstScan = false

    var count: Int {
        lock.withLock { storedCount }
    }

    var didCancelFirstScan: Bool {
        lock.withLock { storedDidCancelFirstScan }
    }

    func scan(isCancelled: @Sendable () -> Bool) -> [ApplicationRecord] {
        let count = lock.withLock {
            storedCount += 1
            return storedCount
        }
        if count == 1 {
            while !isCancelled() {
                Thread.sleep(forTimeInterval: 0.001)
            }
            lock.withLock {
                storedDidCancelFirstScan = true
            }
            return []
        }
        return [
            ApplicationRecord(
                name: "Scan \(count)",
                url: URL(fileURLWithPath: "/Applications/Scan \(count).app"),
            ),
        ]
    }
}
