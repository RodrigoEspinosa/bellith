import AppKit
import XCTest
@testable import Bellith

final class StudioTests: XCTestCase {
    @MainActor func testNavigationKeepsScrollViewportsInsideWindow() throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let controller = StudioWindowController(previewOnly: true, storage: storage,
            openTerminal: {}, startCompanion: { _ in false })
        let window = try XCTUnwrap(controller.window)
        let host = try XCTUnwrap(window.contentView)
        defer { window.close() }

        func scrollViews(in view: NSView) -> [NSScrollView] {
            view.subviews.flatMap { child -> [NSScrollView] in
                if let scroll = child as? NSScrollView { return [scroll] }
                return scrollViews(in: child)
            }
        }

        for size in [NSSize(width: 1430, height: 772), NSSize(width: 1140, height: 712)] {
            window.setContentSize(size)
            for destination in [StudioModel.Destination.home, .logic, .resolve, .media, .logic, .home] {
                controller.model.destination = destination
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                host.layoutSubtreeIfNeeded()
                let viewports = scrollViews(in: host)
                XCTAssertFalse(viewports.isEmpty, "Missing navigation/content for \(destination)")
                for scroll in viewports where !scroll.isHiddenOrHasHiddenAncestor {
                    let rect = scroll.convert(scroll.bounds, to: host)
                    XCTAssertGreaterThan(rect.height, 0, "Collapsed viewport in \(destination)")
                    XCTAssertGreaterThanOrEqual(rect.minY, -1, "Viewport above/below window in \(destination): \(rect)")
                    XCTAssertLessThanOrEqual(rect.maxY, host.bounds.maxY + 1, "Viewport exceeds window in \(destination): \(rect)")
                }
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.path))
    }

    func testResolveRecoveryGuidanceTakesPriorityOverOrdinaryPlanning() {
        var session = ResolveGoalSession()
        for phase in [ResolveGoalSession.Phase.needsAttention, .duplicating, .editing] {
            session.phase = phase
            let hint = StudioResolveGuidance.nextStep(session: session, busy: false, accessibilityAvailable: true)
            XCTAssertTrue(hint.contains("saved checkpoint"))
            XCTAssertTrue(hint.contains("Do not repeat"))
            XCTAssertFalse(hint.contains("ask the companion"))
        }
        session.phase = .paused
        XCTAssertTrue(StudioResolveGuidance.nextStep(session: session, busy: false, accessibilityAvailable: true).contains("Paused"))
        session.phase = .accepted
        XCTAssertTrue(StudioResolveGuidance.nextStep(session: session, busy: false, accessibilityAvailable: true).contains("new session"))
        session.phase = .readyForReview
        XCTAssertTrue(StudioResolveGuidance.nextStep(session: session, busy: false, accessibilityAvailable: true).contains("Review playback"))
    }
    @MainActor func testDemoRequiresReviewAndPreservesOriginal() throws {
        let model = StudioDemoModel()
        let original = model.source
        model.removeTestClip = true
        model.applySimulation()
        XCTAssertNil(model.working)
        model.prepare()
        XCTAssertEqual(model.plan?.removeClipKeys, ["camera-test"])
        model.applySimulation()
        XCTAssertNil(model.working, "Proposal preparation is not approval")
        model.review()
        model.applySimulation()
        let working = try XCTUnwrap(model.working)
        XCTAssertEqual(model.source, original)
        XCTAssertNotEqual(working.timelineID, original.timelineID)
        XCTAssertEqual(working.clips, original.clips.filter { $0.key != "camera-test" })
        XCTAssertEqual(working.endFrame, original.endFrame, "Removal preserves the gap")
        XCTAssertEqual(working.markers, [])
        model.reset()
        XCTAssertEqual(model.phase, .start)
        XCTAssertNil(model.working)
        XCTAssertNil(model.plan)
        XCTAssertEqual(model.source, original)
    }

    @MainActor func testDemoNotesKeepAllClipsAndNeverTouchStorage() throws {
        let model = StudioDemoModel()
        model.prepare()
        model.review()
        model.applySimulation()
        let working = try XCTUnwrap(model.working)
        XCTAssertEqual(working.clips, model.source.clips)
        XCTAssertEqual(working.markers?.count, 1)
        XCTAssertEqual(working.markers?.first?.frame, 0)
        XCTAssertEqual(model.source.markers, [])
        XCTAssertNil(model.error)
    }

    @MainActor func testStudioPreviewGatesLiveActionsAndRetainsNavigationContext() throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "Bellith-StudioTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = StudioModel(previewOnly: true, storage: storage, defaults: defaults)
        model.resolve.session.goal = "Keep this draft"
        model.logic.companionGoal = "Review the balance before changing tracks"
        model.logic.companionProvider = .claude
        model.media.companionGoal = "Plan a delivery of this project"
        model.media.companionProvider = .claude
        model.destination = .resolve
        XCTAssertFalse(model.resolve.hostOperationsEnabled)
        XCTAssertFalse(model.logic.operationsEnabled)
        XCTAssertFalse(model.logic.trackControlsQualified)
        model.destination = .demo
        model.demo.prepare()
        model.destination = .media
        model.destination = .resolve
        XCTAssertEqual(model.resolve.session.goal, "Keep this draft")
        XCTAssertEqual(model.logic.companionGoal, "Review the balance before changing tracks")
        XCTAssertEqual(model.logic.companionProvider, .claude)
        XCTAssertEqual(model.media.companionGoal, "Plan a delivery of this project")
        XCTAssertEqual(model.media.companionProvider, .claude)
        XCTAssertEqual(model.demo.phase, .proposal)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.path), "Opening Studio does not write demo files")
        model.checkApps()
        XCTAssertFalse(model.checking)
        XCTAssertTrue(model.connections.isEmpty)
    }
}
