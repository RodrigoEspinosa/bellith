import XCTest
@testable import Bellith

final class CreativeProjectHistoryTests: XCTestCase {
    @MainActor func testRememberedMissingFolderIsNotAutomaticallyOpened() throws {
        let suite = "BellithHistoryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let missing = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)")
        CreativeProjectHistory(defaults: defaults).remember(missing)
        let model = CreativeWorkspaceModel(defaults: defaults)
        XCTAssertEqual(model.recentProjects.first?.id, missing.path)
        XCTAssertTrue(model.isSample)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        model.clearRecentProjects()
        XCTAssertTrue(model.recentProjects.isEmpty)
        XCTAssertEqual(model.assets.count, CreativeAsset.examples.count)
    }

    @MainActor func testFailedExplicitReopenPreservesCurrentProject() async throws {
        let suite = "BellithHistoryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CreativeWorkspaceModel(defaults: defaults)
        let current = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: current) }
        try Data().write(to: current.appendingPathComponent("take.wav"))
        model.openProject(current)
        for _ in 0..<200 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNil(model.error)
        XCTAssertEqual(model.assets.map(\.relativePath), ["take.wav"])
        XCTAssertEqual(model.recentProjects.first?.url, current)
        model.openProject(URL(fileURLWithPath: "/tmp/\(UUID().uuidString)"))
        for _ in 0..<200 where model.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.root, current)
        XCTAssertEqual(model.projectName, current.lastPathComponent)
        XCTAssertEqual(model.assets.map(\.relativePath), ["take.wav"])
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.recentProjects.first?.url, current)
    }

    func testCorruptOrRemoteHistoryDoesNotBecomeAnOpenTarget() throws {
        let suite = "BellithHistoryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CreativeProjectHistory(defaults: defaults)
        defaults.set(Data("invalid".utf8), forKey: CreativeProjectHistory.key)
        XCTAssertTrue(store.read().isEmpty)
        let remote = CreativeRecentProject(url: URL(string: "https://example.com/project")!, openedAt: Date())
        defaults.set(try JSONEncoder().encode([remote]), forKey: CreativeProjectHistory.key)
        XCTAssertTrue(store.read().isEmpty)
        XCTAssertTrue(store.remember(remote.url).isEmpty)
    }
}
