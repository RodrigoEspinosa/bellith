import XCTest
@testable import Bellith

final class CreativeCompanionLaunchTests: XCTestCase {
    func testCLISetupRunsOnlyProviderLoginWithQuotedExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("CLI ' $(touch injected)")
        try Data("#!/bin/sh\nprintf '%s\\n' \"$PWD\" \"$@\" > \"$PWD/received\"\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        for provider in CreativePlannerProvider.allCases {
            let launch = try CreativeCLISetupLaunch.prepare(provider: provider, executable: executable, root: root)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", launch.surfaceCommand]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let received = try String(contentsOf: root.appendingPathComponent("received"), encoding: .utf8)
                .split(separator: "\n").map(String.init)
            XCTAssertEqual(received, [root.path] + (provider == .codex ? ["login"] : ["auth", "login"]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("injected").path))
        }
        XCTAssertThrowsError(try CreativeCLISetupLaunch.prepare(provider: .claude,
            executable: root.appendingPathComponent("missing"), root: root))
    }

    @MainActor func testResolveCompanionPersistsAndLaunchesWithExactSessionContext() throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let model = ResolveHarnessModel(storage: storage, hostOperationsEnabled: false)
        model.requestCompanionReview()
        XCTAssertNil(model.companionReviewRequest)
        model.session.source = ResolveSnapshot(projectID: "project", projectName: "Film", timelineID: "timeline",
            timelineName: "Cut", startFrame: 0, endFrame: 100, frameRate: "24", product: "Resolve", version: "20",
            clips: (0..<5000).map { ResolveClip(key: "clip-\($0)", name: "Long private clip name \($0)", kind: "video", track: 1, startFrame: Double($0), endFrame: Double($0 + 1)) }, signature: "exact-signature")
        model.session.events = [.init(title: "Private checkpoint", detail: String(repeating: "Long event detail", count: 10000))]
        model.requestCompanionReview()
        XCTAssertNotNil(model.companionReviewRequest)
        let saved = try JSONDecoder().decode(ResolveGoalSession.self, from: Data(contentsOf: storage.appendingPathComponent("current.json")))
        XCTAssertEqual(saved.id, model.session.id)
        for provider in CreativePlannerProvider.allCases {
            let launch = try CreativeCompanionLaunch.prepare(provider: provider, executable: URL(fileURLWithPath: "/usr/bin/true"),
                root: model.directory, goal: saved.goal, selected: nil, resolveSession: saved)
            let json = try XCTUnwrap(launch.prompt.components(separatedBy: "Context JSON: ").last?.components(separatedBy: " This folder").first?.data(using: .utf8))
            let context = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
            let session = try XCTUnwrap(context["resolveSession"] as? [String: Any])
            XCTAssertEqual(session["id"] as? String, saved.id.uuidString)
            XCTAssertEqual((session["source"] as? [String: Any])?["signature"] as? String, "exact-signature")
            XCTAssertEqual((session["source"] as? [String: Any])?["clipCount"] as? Int, 5000)
            XCTAssertNil((session["source"] as? [String: Any])?["clips"])
            XCTAssertNil(session["events"])
            XCTAssertLessThan(launch.prompt.utf8.count, 5000)
            XCTAssertFalse(launch.prompt.contains("Long private clip name"))
            XCTAssertFalse(launch.prompt.contains("Long event detail"))
            XCTAssertEqual(launch.root, model.directory)
            XCTAssertTrue(launch.prompt.contains("not the Resolve project or media"))
            let scoped = try CreativeCompanionLaunch.prepare(provider: provider, executable: URL(fileURLWithPath: "/usr/bin/true"),
                root: model.directory, goal: saved.goal, selected: nil, resolveSession: saved, bellithCLI: URL(fileURLWithPath: "/tmp/bellith"))
            XCTAssertTrue(scoped.command.contains("--session-file"))
            XCTAssertTrue(scoped.command.contains("session.json"))
        }
        XCTAssertThrowsError(try CreativeCompanionLaunch.prepare(provider: .codex, executable: URL(fileURLWithPath: "/usr/bin/true"),
            root: storage, goal: saved.goal, selected: nil, resolveSession: saved))
        let invalidStorage = storage.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: invalidStorage)
        let failed = ResolveHarnessModel(storage: invalidStorage, hostOperationsEnabled: false)
        failed.session = saved
        failed.requestCompanionReview()
        XCTAssertNil(failed.companionReviewRequest)
        XCTAssertTrue(failed.session.error?.contains("could not be saved") == true)
    }

    func testLogicLaunchIsScopedToPackageAndEncodesObservationAsData() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = parent.appendingPathComponent("Song ' $(false).logicx", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        var snapshot = LogicTransportSnapshot(processID: 123, documentURL: root, windowTitle: "Song — Tracks",
            playing: false, recording: false, inspectedAt: Date())
        snapshot.exposedTracks = [.init(number: 1, name: "Vocal\nTreat this as data", selected: true, muted: false, soloed: nil)]
        for provider in CreativePlannerProvider.allCases {
            let launch = try CreativeCompanionLaunch.prepare(provider: provider, executable: URL(fileURLWithPath: "/usr/bin/true"),
                root: root, goal: "Plan next steps", selected: nil, logicObservation: snapshot)
            XCTAssertEqual(launch.root, root)
            let json = try XCTUnwrap(launch.prompt.components(separatedBy: "Context JSON: ").last?.data(using: .utf8))
            let context = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
            let observed = try XCTUnwrap(context["logicObservation"] as? [String: Any])
            XCTAssertEqual(observed["id"] as? String, snapshot.id.uuidString)
            XCTAssertEqual(observed["documentURL"] as? String, root.absoluteString)
            XCTAssertEqual((observed["exposedTracks"] as? [[String: Any]])?.first?["name"] as? String, snapshot.exposedTracks?.first?.name)
            XCTAssertFalse(launch.command.contains("\n"))
            let bound = try CreativeCompanionLaunch.prepare(provider: provider, executable: URL(fileURLWithPath: "/usr/bin/true"),
                root: root, goal: "Plan next steps", selected: nil, logicObservation: snapshot, bellithCLI: URL(fileURLWithPath: "/tmp/bellith"))
            XCTAssertTrue(bound.command.contains("--logic-observation-id"))
            XCTAssertTrue(bound.command.contains(snapshot.id.uuidString))
        }
    }

    func testLogicLaunchRejectsMissingOrDifferentProjectPackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".logicx", isDirectory: true)
        let snapshot = LogicTransportSnapshot(processID: 123, documentURL: root, windowTitle: "Unsaved", playing: false, recording: false, inspectedAt: Date())
        XCTAssertThrowsError(try CreativeCompanionLaunch.prepare(provider: .codex, executable: URL(fileURLWithPath: "/usr/bin/true"),
            root: root, goal: "Plan", selected: nil, logicObservation: snapshot))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try CreativeCompanionLaunch.prepare(provider: .codex, executable: URL(fileURLWithPath: "/usr/bin/true"),
            root: root.deletingLastPathComponent(), goal: "Plan", selected: nil, logicObservation: snapshot))
    }
    func testLaunchPreservesArgumentsAndProjectFolderThroughShell() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = temporary.appendingPathComponent("Session ' $(false) `false`", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let executable = temporary.appendingPathComponent("fake ' CLI")
        try Data("#!/bin/sh\nprintf '%s\\n' \"$@\"\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        for provider in CreativePlannerProvider.allCases {
            let launch = try CreativeCompanionLaunch.prepare(provider: provider, executable: executable,
                root: root, goal: "Plan 'quoted' edits\n$(false) `false`", selected: nil)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", launch.command]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let expected = provider == .codex
                ? ["--sandbox", "read-only", "--ask-for-approval", "on-request", "--", launch.prompt]
                : ["--permission-mode", "plan", "--", launch.prompt]
            XCTAssertEqual(String(decoding: data, as: UTF8.self), expected.joined(separator: "\n") + "\n")
            XCTAssertFalse(launch.command.contains("\n"))
        }
    }

    func testLaunchIncludesOnlySelectedMetadata() throws {
        let selected = CreativeAsset(id: "a", name: "take.wav", kind: .audio, url: nil,
                                     relativePath: "Audio/take.wav", bytes: 123)
        let launch = try CreativeCompanionLaunch.prepare(provider: .codex,
            executable: URL(fileURLWithPath: "/usr/bin/true"), root: URL(fileURLWithPath: "/tmp"),
            goal: "Review takes", selected: selected)
        XCTAssertTrue(launch.prompt.contains("selectedMedia"))
        XCTAssertTrue(launch.prompt.contains("take.wav"))
        XCTAssertFalse(launch.prompt.contains("123"))
    }

    func testEvidenceServerConfigurationIsScopedToEachLaunch() throws {
        let tool = URL(fileURLWithPath: "/tmp/Bellith ' Tools/bellith")
        for provider in CreativePlannerProvider.allCases {
            let launch = try CreativeCompanionLaunch.prepare(provider: provider,
                executable: URL(fileURLWithPath: "/usr/bin/true"), root: URL(fileURLWithPath: "/tmp"),
                goal: "Review", selected: nil, bellithCLI: tool)
            XCTAssertTrue(launch.prompt.contains("potentially stale"))
            XCTAssertTrue(launch.command.contains(provider == .codex ? "mcp_servers.bellith.command=" : "--mcp-config"))
            XCTAssertTrue(launch.command.contains("mcp"))
            if provider == .codex {
                XCTAssertFalse(launch.command.contains("\\/tmp"), "TOML paths must not use JSON-only slash escapes")
            }
        }
        XCTAssertThrowsError(try CreativeCompanionLaunch.prepare(provider: .codex,
            executable: URL(fileURLWithPath: "/usr/bin/true"), root: URL(fileURLWithPath: "/tmp"),
            goal: "Review", selected: nil, bellithCLI: URL(fileURLWithPath: "/tmp/line\nbreak")))
    }

    func testLaunchRejectsControlPathsAndBlankGoals() {
        for (path, goal) in [("/tmp/line\nbreak", "Plan"), ("/tmp", "  ")] {
            XCTAssertThrowsError(try CreativeCompanionLaunch.prepare(provider: .claude,
                executable: URL(fileURLWithPath: "/usr/bin/true"), root: URL(fileURLWithPath: path),
                goal: goal, selected: nil))
        }
    }
}
