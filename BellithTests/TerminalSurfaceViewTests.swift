import AppKit
import Foundation
import XCTest
@testable import Bellith

final class TerminalSurfaceViewTests: XCTestCase {
    @MainActor
    func testCompanionLaunchStartsThroughGhosttyWithoutTypedInput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Companion ' \(UUID().uuidString).logicx")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-cli")
        try Data("#!/bin/sh\nprintf '%s\\n' \"$PWD\" \"$@\" > observed.txt\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let suite = "CompanionSurfaceTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = BellithSettings(defaults: defaults, settingsFileURL: root.appendingPathComponent("settings.json"))
        let config = TerminalConfig(settings: settings, configurationDirectory: root.appendingPathComponent("config"))
        let app = TerminalApp(config: config)
        XCTAssertNotNil(app.app)
        let observation = LogicTransportSnapshot(processID: 123, documentURL: root, windowTitle: "Synthetic — Tracks",
            playing: false, recording: false, inspectedAt: Date())
        let tool = root.appendingPathComponent("tool ' path/bellith")
        let output = root.appendingPathComponent("observed.txt")
        for provider in CreativePlannerProvider.allCases {
            if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
            let launch = try CreativeCompanionLaunch.prepare(provider: provider, executable: executable,
                root: root, goal: "Plan 'quoted' edits\n$(false)", selected: nil, logicObservation: observation, bellithCLI: tool)
            var surface: TerminalSurfaceView? = TerminalSurfaceView(app: app,
                startupCommand: launch.surfaceCommand, workingDirectory: root.path)
            defer { surface = nil; withExtendedLifetime(app) {} }
            XCTAssertTrue(surface?.isReady == true)
            let deadline = ContinuousClock().now.advanced(by: .seconds(10))
            while !FileManager.default.fileExists(atPath: output.path), ContinuousClock().now < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            let text = try String(contentsOf: output)
            let lines = text.components(separatedBy: "\n")
            if provider == .codex {
                XCTAssertEqual(Array(lines.prefix(5)), [root.path, "--sandbox", "read-only", "--ask-for-approval", "on-request"])
                XCTAssertEqual(lines[5], "-c")
                let encodedTool = String(decoding: try JSONEncoder().encode(tool.path), as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
                XCTAssertEqual(lines[6], "mcp_servers.bellith.command=" + encodedTool)
                XCTAssertEqual(lines[7], "-c")
                let argsJSON = try XCTUnwrap(lines[8].components(separatedBy: "mcp_servers.bellith.args=").last?.data(using: .utf8))
                XCTAssertEqual(try JSONDecoder().decode([String].self, from: argsJSON), ["mcp", "--creative-scope", "logic", "--logic-observation-id", observation.id.uuidString])
                XCTAssertEqual(lines[9], "--")
                XCTAssertEqual(lines[10], launch.prompt)
            } else {
                XCTAssertEqual(Array(lines.prefix(4)), [root.path, "--permission-mode", "plan", "--mcp-config"])
                let data = try XCTUnwrap(lines[4].data(using: .utf8))
                let config = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let servers = try XCTUnwrap(config["mcpServers"] as? [String: Any])
                let server = try XCTUnwrap(servers["bellith"] as? [String: Any])
                XCTAssertEqual(server["command"] as? String, tool.path)
                XCTAssertEqual(server["args"] as? [String], ["mcp", "--creative-scope", "logic", "--logic-observation-id", observation.id.uuidString])
                XCTAssertEqual(lines[5], "--")
                XCTAssertEqual(lines[6], launch.prompt)
            }
        }
    }

    func testTemporaryDropDirectoryURLLivesUnderSystemTempDirectory() {
        let baseDirectory = URL(fileURLWithPath: "/tmp/test-base", isDirectory: true)

        let directory = TerminalSurfaceView.temporaryDropDirectoryURL(baseDirectory: baseDirectory)

        XCTAssertEqual(directory.deletingLastPathComponent().deletingLastPathComponent(), baseDirectory)
        XCTAssertEqual(directory.deletingLastPathComponent().lastPathComponent, "BellithDrops")
    }

    func testTemporaryDropImageURLUsesRequestedExtension() {
        let directory = URL(fileURLWithPath: "/tmp/BellithDrops/session", isDirectory: true)

        let url = TerminalSurfaceView.temporaryDropImageURL(in: directory, fileExtension: "png")

        XCTAssertEqual(url.deletingLastPathComponent(), directory)
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("image-"))
    }

    func testCleanupTemporaryDropDirectoryRemovesDirectoryTree() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BellithTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedFile = directory.appendingPathComponent("image.png")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x00, 0x01, 0x02]).write(to: nestedFile)

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedFile.path))

        TerminalSurfaceView.cleanupTemporaryDropDirectory(at: directory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
