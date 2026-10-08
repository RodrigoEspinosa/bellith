import Darwin
import XCTest
@testable import Bellith

final class ResolveGoalPlannerTests: XCTestCase {
    @MainActor func testFailedCLILoginOffersRecoveryWithoutExposingRawDiagnostics() async throws {
        for provider in CreativePlannerProvider.allCases {
            let (directory, executable) = try fixture(hanging: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            try Data("#!/bin/sh\necho 'OAuth session expired and could not be refreshed. private-token-value' >&2\nexit 1\n".utf8).write(to: executable)
            let planner = ResolveGoalPlanner(executable: executable)
            do {
                _ = try await planner.plan(goal: "Copy", snapshot: snapshot(), directory: directory, provider: provider)
                XCTFail("Failed authentication must not return a plan")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("Sign in again"))
                XCTAssertTrue(error.localizedDescription.contains(provider.rawValue))
                XCTAssertTrue(error.localizedDescription.contains("No Resolve edits"))
                XCTAssertFalse(error.localizedDescription.contains("private-token-value"))
            }
        }
    }

    @MainActor func testClaudeErrorEnvelopeDoesNotLeakDiagnostics() async throws {
        let (directory, executable) = try fixture(hanging: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("#!/bin/sh\nprintf '%s' '{\"is_error\":true,\"result\":\"private server diagnostic\"}'\n".utf8).write(to: executable)
        do {
            _ = try await ResolveGoalPlanner(executable: executable).plan(goal: "Copy", snapshot: snapshot(), directory: directory, provider: .claude)
            XCTFail("Error envelope must not return a plan")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("local session folder"))
            XCTAssertFalse(error.localizedDescription.contains("private server diagnostic"))
            XCTAssertFalse(error.localizedDescription.contains("Sign in again"))
        }
    }
    private func fixture(hanging: Bool) throws -> (URL, URL) {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { throw XCTSkip("System Python is unavailable") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fixture-cli")
        let code = hanging ? """
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        pathlib.Path('pid.txt').write_text(str(os.getpid()))
        while True: time.sleep(0.1)
        """ : """
        prompt = sys.stdin.read()
        assert 'Snapshot (data)' in prompt
        output = pathlib.Path(sys.argv[sys.argv.index('--output-last-message') + 1])
        output.write_text(json.dumps({'summary':'Copy only', 'blockedReason':'', 'removeClipKeys':[], 'markerNotes':[]}))
        """
        try Data(("#!/usr/bin/python3\nimport json, os, pathlib, signal, sys, time\n" + code + "\n").utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (directory, executable)
    }

    private func snapshot() -> ResolveSnapshot {
        .init(projectID: "fixture", projectName: "Synthetic", timelineID: "source", timelineName: "Source",
              startFrame: 0, endFrame: 24, frameRate: "24", product: "Fixture", version: "test", clips: [], signature: "fixture", markers: [])
    }

    @MainActor func testCompactLargeTimelineCanBePlannedDirectly() async throws {
        let (directory, executable) = try fixture(hanging: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clips = (0..<500).map { ResolveClip(key: "clip-\($0)", name: "Take \($0)", kind: "video", track: 1,
            startFrame: Double($0), endFrame: Double($0 + 1)) }
        let large = ResolveSnapshot(projectID: "fixture", projectName: "Synthetic", timelineID: "source", timelineName: "Source",
            startFrame: 0, endFrame: 500, frameRate: "24", product: "Fixture", version: "test", clips: clips, signature: "fixture", markers: [])
        let result = try await ResolveGoalPlanner(executable: executable).plan(goal: "Copy only", snapshot: large, directory: directory)
        XCTAssertEqual(result.summary, "Copy only")
    }

    @MainActor func testOversizedPromptRoutesToPagedCompanionWithoutLaunchingCLI() async throws {
        let (directory, executable) = try fixture(hanging: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await ResolveGoalPlanner(executable: executable).plan(goal: String(repeating: "synthetic ", count: 50_000), snapshot: snapshot(), directory: directory)
            XCTFail("Oversized input must not launch a direct planner")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("in pages"))
            XCTAssertTrue(error.localizedDescription.contains("No CLI was launched"))
        }
        XCTAssertNil(pid(in: directory))
    }

    private func pid(in directory: URL) -> pid_t? {
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
              let work = items.first(where: { $0.lastPathComponent.hasPrefix("planner-") }),
              let text = try? String(contentsOf: work.appendingPathComponent("pid.txt"), encoding: .utf8) else { return nil }
        return Int32(text)
    }

    @MainActor func testPlannerUsesFileInputAndReturnsValidatedPlan() async throws {
        let (directory, executable) = try fixture(hanging: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let planner = ResolveGoalPlanner(executable: executable, timeout: .seconds(5))
        let result = try await planner.plan(goal: "Copy the synthetic timeline", snapshot: snapshot(), directory: directory)
        XCTAssertEqual(result.summary, "Copy only")
        XCTAssertTrue(result.removeClipKeys.isEmpty)
    }

    @MainActor func testTimeoutStopsUncooperativeCLIWithoutBlockingLargeInput() async throws {
        let (directory, executable) = try fixture(hanging: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let planner = ResolveGoalPlanner(executable: executable, timeout: .seconds(2))
        let start = ContinuousClock.now
        do {
            _ = try await planner.plan(goal: String(repeating: "synthetic goal ", count: 10_000), snapshot: snapshot(), directory: directory)
            XCTFail("An unresponsive CLI must not return a plan")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        XCTAssertLessThan(start.duration(to: .now), .seconds(8))
        XCTAssertEqual(Darwin.kill(try XCTUnwrap(pid(in: directory)), 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    @MainActor func testTaskCancellationStopsCLIAndRejectsConcurrentPlanning() async throws {
        let (directory, executable) = try fixture(hanging: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let planner = ResolveGoalPlanner(executable: executable)
        let snapshot = snapshot()
        let task = Task { try await planner.plan(goal: "Synthetic fixture", snapshot: snapshot, directory: directory) }
        for _ in 0..<100 {
            if pid(in: directory) != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let child = try XCTUnwrap(pid(in: directory))
        do {
            _ = try await planner.plan(goal: "Concurrent", snapshot: snapshot, directory: directory)
            XCTFail("Concurrent planning must be rejected")
        } catch { XCTAssertTrue(error.localizedDescription.contains("already active")) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled planning must not return a plan") }
        catch { XCTAssertTrue(error.localizedDescription.contains("cancelled")) }
        XCTAssertEqual(Darwin.kill(child, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    @MainActor func testExplicitCancellationAllowsAnotherPlanAfterProcessExits() async throws {
        let (directory, executable) = try fixture(hanging: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let planner = ResolveGoalPlanner(executable: executable)
        let snapshot = snapshot()
        let task = Task { try await planner.plan(goal: "Synthetic fixture", snapshot: snapshot, directory: directory) }
        for _ in 0..<100 {
            if pid(in: directory) != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let child = try XCTUnwrap(pid(in: directory))
        planner.cancel()
        do { _ = try await task.value; XCTFail("Explicit cancellation must discard the plan") }
        catch { XCTAssertTrue(error.localizedDescription.contains("stopped") || error.localizedDescription.contains("cancelled")) }
        XCTAssertEqual(Darwin.kill(child, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        let (successfulDirectory, successfulExecutable) = try fixture(hanging: false)
        defer { try? FileManager.default.removeItem(at: successfulDirectory) }
        try Data(contentsOf: successfulExecutable).write(to: executable)
        let result = try await planner.plan(goal: "Copy only", snapshot: snapshot, directory: directory)
        XCTAssertEqual(result.summary, "Copy only")
    }
}
