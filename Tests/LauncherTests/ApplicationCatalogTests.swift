@testable import Cornerlight
import Foundation
import Testing

struct ApplicationCatalogTests {
    @Test
    func `default roots are the complete launcher search scope`() {
        #expect(ApplicationCatalog.defaultRoots.map(\.standardizedFileURL.path) == [
            "/Applications",
            "/System/Applications",
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Applications", directoryHint: .isDirectory)
                .standardizedFileURL.path,
        ])
    }

    @Test
    func `missing application roots produce an empty catalog`() {
        let missingRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)

        #expect(ApplicationCatalog.scan(roots: [missingRoot]).isEmpty)
    }

    @Test
    func `scans nested application bundles and ignores other files`() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let utilities = root.appending(path: "Utilities", directoryHint: .isDirectory)
        let nestedApp = utilities.appending(path: "Activity Monitor.app", directoryHint: .isDirectory)
        let ordinaryFolder = root.appending(path: "Not An App", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nestedApp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ordinaryFolder, withIntermediateDirectories: true)

        let results = ApplicationCatalog.scan(roots: [root])

        #expect(results.map(\.name) == ["Activity Monitor"])
        #expect(results.first?.url.standardizedFileURL == nestedApp.standardizedFileURL)
    }

    @Test
    func `skips application bundle descendants`() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let outer = root.appending(path: "Outer.app", directoryHint: .isDirectory)
        let nested = outer
            .appending(path: "Contents", directoryHint: .isDirectory)
            .appending(path: "Helpers", directoryHint: .isDirectory)
            .appending(path: "Helper.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let results = ApplicationCatalog.scan(roots: [root])

        #expect(results.map(\.name) == ["Outer"])
    }

    @Test
    func `hidden application bundles are ignored`() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appending(path: ".Hidden.app", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: root.appending(path: "Visible.app", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )

        #expect(ApplicationCatalog.scan(roots: [root]).map(\.name) == ["Visible"])
    }

    @Test
    func `the launcher includes Cornerlight in its complete inventory`() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let launcher = root.appending(path: "Cornerlight.app", directoryHint: .isDirectory)
        let other = root.appending(path: "Other.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: launcher, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        let results = ApplicationCatalog.scan(roots: [root])

        #expect(results.map(\.name) == ["Cornerlight", "Other"])
    }

    @Test
    func `overlapping roots do not duplicate an application`() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appending(path: "Only Once.app", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )

        let results = ApplicationCatalog.scan(roots: [root, root])

        #expect(results.map(\.name) == ["Only Once"])
    }

    @Test
    func `catalog sorting is deterministic when application names match`() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstDirectory = root.appending(path: "A", directoryHint: .isDirectory)
        let secondDirectory = root.appending(path: "B", directoryHint: .isDirectory)
        let first = firstDirectory.appending(path: "Same.app", directoryHint: .isDirectory)
        let second = secondDirectory.appending(path: "Same.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let results = ApplicationCatalog.scan(roots: [root])

        #expect(results.map(\.url.standardizedFileURL.path) == [first.path, second.path])
    }

    @Test
    func `application bundle identifier comes from its bundle information`() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let application = root.appending(path: "Editor.app", directoryHint: .isDirectory)
        let contents = application.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": "com.example.Editor",
            ],
            format: .binary,
            options: 0,
        )
        try data.write(to: contents.appending(path: "Info.plist"))

        let result = ApplicationCatalog.scan(roots: [root]).first

        #expect(result?.bundleIdentifier == "com.example.Editor")
    }

    @Test
    func `filters case and diacritics and ranks prefixes first`() {
        let apps = [
            ApplicationRecord(name: "Visual Studio Code", url: URL(fileURLWithPath: "/Visual.app")),
            ApplicationRecord(name: "CodeEdit", url: URL(fileURLWithPath: "/CodeEdit.app")),
            ApplicationRecord(name: "Xcode", url: URL(fileURLWithPath: "/Xcode.app")),
            ApplicationRecord(name: "Cöde Runner", url: URL(fileURLWithPath: "/Runner.app")),
        ]

        let results = ApplicationCatalog.filter(apps, query: "code")

        #expect(results.map(\.name) == ["Cöde Runner", "CodeEdit", "Visual Studio Code", "Xcode"])
    }

    @Test
    func `empty query preserves catalog order`() {
        let apps = [
            ApplicationRecord(name: "B", url: URL(fileURLWithPath: "/B.app")),
            ApplicationRecord(name: "A", url: URL(fileURLWithPath: "/A.app")),
        ]

        #expect(ApplicationCatalog.filter(apps, query: "   ") == apps)
    }

    @Test
    func `a search with no matches returns no applications`() {
        let apps = [
            ApplicationRecord(name: "Mail", url: URL(fileURLWithPath: "/Mail.app")),
        ]

        #expect(ApplicationCatalog.filter(apps, query: "calendar").isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
