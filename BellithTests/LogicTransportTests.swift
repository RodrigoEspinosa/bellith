import XCTest
@testable import Bellith

final class LogicTransportTests: XCTestCase {
    @MainActor func testUnresolvedReceiptCannotBeOverwrittenByAnotherAction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("current.json")
        let old = snapshot()
        var pending = LogicTransportAttempt(action: .play, expected: old, proposalID: nil)
        pending.startedAt = Date().addingTimeInterval(-10)
        let inbox = LogicTransportInbox(file: file)
        try inbox.saveAttempt(pending)
        let fresh = snapshot()
        let model = LogicTransportModel(file: file, snapshot: fresh, operations: .init(
            inspect: { fresh }, perform: { _, value in XCTFail("Recovery review required"); return value }))
        model.apply(.stop)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.snapshot, fresh)
        XCTAssertEqual(model.lastAttempt?.id, pending.id)
        XCTAssertEqual(try inbox.readAttempt()?.id, pending.id)
        XCTAssertTrue(model.requiresRecoveryReview)
        model.reviewInterruptedState()
        XCTAssertFalse(model.requiresRecoveryReview)
        XCTAssertEqual(model.lastAttempt?.phase, .reviewed)
    }
    func testCancellationReachesDetachedLogicOperation() async throws {
        let entered = expectation(description: "Worker entered")
        let caller = Task {
            try await LogicTransportAdapter.runOperation {
                entered.fulfill()
                try await Task.sleep(for: .seconds(30))
                XCTFail("Cancelled worker must not reach the host action")
                return true
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        caller.cancel()
        do {
            _ = try await caller.value
            XCTFail("Cancelled operation must throw")
        } catch is CancellationError {
            // Cancellation reaches the detached worker instead of waiting 30 seconds.
        }
    }

    @MainActor func testTrackProposalQueueAndImportAreBoundAndNonExecuting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("current.json")
        var observed = snapshot()
        observed.exposedTracks = [.init(number: 1, name: "Vocals", selected: true, muted: false, soloed: false)]
        let inbox = LogicTransportInbox(file: file)
        try inbox.save(observed)
        let original = try Data(contentsOf: file)
        let request = LogicTrackControlRequest(observationID: observed.id, trackNumber: 1, trackName: "Vocals", control: .mute, enabled: true)
        let proposal = try inbox.submitTrack(request, reason: "User requested muting vocals for comparison")
        XCTAssertEqual(try Data(contentsOf: file), original)
        let model = LogicTransportModel(operationsEnabled: false, file: file, snapshot: observed)
        XCTAssertTrue(model.loadTrackProposal(proposal))
        XCTAssertEqual(model.reviewedTrackRequest, request)
        XCTAssertEqual(model.reviewedTrackProposal, proposal)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.lastTrackAttempt)
        let edited = LogicTrackControlProposal(id: proposal.id, request: request, reason: "Changed after preview")
        try JSONEncoder().encode(edited).write(to: inbox.trackProposalsDirectory.appendingPathComponent(proposal.id.uuidString + ".json"))
        XCTAssertFalse(model.loadTrackProposal(proposal))
        model.reviewTrack(.init(observationID: observed.id, trackNumber: 1, trackName: "Vocals", control: .solo, enabled: true))
        XCTAssertNil(model.reviewedTrackProposal, "A different manual request must not inherit CLI attribution")
        XCTAssertThrowsError(try inbox.submitTrack(request, reason: " "))
        try inbox.save(nil)
        XCTAssertThrowsError(try inbox.submitTrack(request, reason: "No current observation"))
        XCTAssertFalse(model.applyReviewedTrack())
    }
    func testTrackInterruptionReviewDoesNotVerifyOrRetryOriginalAction() throws {
        var expected = snapshot()
        expected.exposedTracks = [.init(number: 1, name: "Vocal", selected: true, muted: false, soloed: false)]
        let request = LogicTrackControlRequest(observationID: expected.id, trackNumber: 1, trackName: "Vocal", control: .mute, enabled: true)
        var attempt = LogicTrackControlAttempt(request: request, expected: expected)
        attempt.startedAt = Date().addingTimeInterval(-10)
        var fresh = snapshot()
        fresh.exposedTracks = expected.exposedTracks
        try attempt.reviewCurrentState(fresh)
        XCTAssertEqual(attempt.phase, .reviewed)
        XCTAssertFalse(attempt.actionOutcomeVerified)
        XCTAssertFalse(attempt.requiresInspection)
        XCTAssertNil(attempt.observed)
        XCTAssertEqual(attempt.reviewedSnapshot, fresh)
        XCTAssertNotNil(attempt.reviewedAt)
        XCTAssertEqual(try JSONDecoder().decode(LogicTrackControlAttempt.self, from: JSONEncoder().encode(attempt)), attempt)
        for invalid in [expected, snapshot(project: "other"), snapshot(recording: true), snapshot()] {
            var pending = LogicTrackControlAttempt(request: request, expected: expected)
            pending.startedAt = Date().addingTimeInterval(-10)
            XCTAssertThrowsError(try pending.reviewCurrentState(invalid))
            XCTAssertEqual(pending.phase, .pending)
        }
    }
    @MainActor func testCancelledPlaybackDoesNotAcknowledgeLateHostFeedback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("current.json")
        let expected = snapshot()
        let after = snapshot(playing: true)
        var model: LogicTransportModel!
        model = LogicTransportModel(file: file, snapshot: expected, operations: .init(
            inspect: { expected }, perform: { _, _ in
                model.cancelOperation()
                return after // Simulates feedback arriving after cancellation.
            }))
        model.apply(.play)
        for _ in 0..<100 where model.busy { await Task.yield() }
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.result)
        XCTAssertEqual(model.lastAttempt?.phase, .needsAttention)
        XCTAssertNil(model.lastAttempt?.observed)
        XCTAssertEqual(try LogicTransportInbox(file: file).readAttempt()?.phase, .needsAttention)
        XCTAssertTrue(model.error?.contains("inspect Logic before retrying") == true)
    }

    @MainActor func testCancellationBeforeInspectionClearsSavedContextWithoutHostCall() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("current.json")
        let expected = snapshot()
        let inbox = LogicTransportInbox(file: file)
        try inbox.save(expected)
        var calls = 0
        let model = LogicTransportModel(file: file, snapshot: expected, operations: .init(
            inspect: { calls += 1; return expected }, perform: { _, _ in expected }))
        model.inspect()
        model.cancelOperation()
        for _ in 0..<100 where model.busy { await Task.yield() }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(try inbox.read())
        XCTAssertNil(model.lastAttempt)
        XCTAssertNotNil(model.error)
    }

    @MainActor func testCancelledTrackDoesNotAcknowledgeLateHostFeedback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("current.json")
        var expected = snapshot()
        expected.exposedTracks = [.init(number: 1, name: "Vocals", selected: true, muted: false, soloed: false)]
        var after = expected
        after.exposedTracks = [.init(number: 1, name: "Vocals", selected: true, muted: true, soloed: false)]
        let request = LogicTrackControlRequest(observationID: expected.id, trackNumber: 1, trackName: "Vocals", control: .mute, enabled: true)
        var model: LogicTransportModel!
        model = LogicTransportModel(file: file, snapshot: expected, operations: .init(
            inspect: { expected }, perform: { _, _ in expected }, performTrack: { _, _ in
                model.cancelOperation()
                return after
            }))
        model.applyTrack(request)
        for _ in 0..<100 where model.busy { await Task.yield() }
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.lastTrackAttempt?.phase, .needsAttention)
        XCTAssertNil(model.lastTrackAttempt?.observed)
        XCTAssertEqual(try LogicTransportInbox(file: file).readTrackAttempt()?.phase, .needsAttention)
        XCTAssertNil(try LogicTransportInbox(file: file).read())
    }

    @MainActor func testTrackReceiptFailureBlocksHostInvocation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("block receipt directory".utf8).write(to: directory.appendingPathComponent("track-attempts"))
        var expected = snapshot()
        expected.exposedTracks = [.init(number: 1, name: "Vocal", selected: true, muted: false, soloed: false)]
        var calls = 0
        let model = LogicTransportModel(file: directory.appendingPathComponent("current.json"), snapshot: expected,
            operations: .init(inspect: { expected }, perform: { _, _ in expected }, performTrack: { _, _ in calls += 1; return expected }))
        model.applyTrack(.init(observationID: expected.id, trackNumber: 1, trackName: "Vocal", control: .mute, enabled: true))
        for _ in 0..<100 where model.busy { await Task.yield() }
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.snapshot)
    }
    @MainActor func testTrackAttemptPersistsBeforeHostAndNeverRetriesOnRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("current.json")
        var expected = snapshot()
        expected.exposedTracks = [.init(number: 1, name: "Vocal", selected: true, muted: false, soloed: false)]
        let request = LogicTrackControlRequest(observationID: expected.id, trackNumber: 1, trackName: "Vocal", control: .mute, enabled: true)
        var calls = 0
        let inbox = LogicTransportInbox(file: file)
        let operations = LogicTransportOperations(inspect: { expected }, perform: { _, _ in expected }, performTrack: { _, before in
            calls += 1
            XCTAssertEqual(try inbox.readTrackAttempt()?.phase, .pending)
            XCTAssertNil(try inbox.read())
            return before // A successful invocation without feedback must remain unverified.
        })
        let model = LogicTransportModel(file: file, snapshot: expected, operations: operations)
        model.reviewTrack(request)
        XCTAssertEqual(model.reviewedTrackRequest, request)
        let firstReview = model.trackReviewRequest
        model.reviewTrack(request)
        XCTAssertNotEqual(model.trackReviewRequest, firstReview, "The same request can reopen after cancelling review")
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(model.applyReviewedTrack(), "Unqualified track controls must not execute")
        XCTAssertEqual(model.snapshot, expected)
        model.applyTrack(request)
        for _ in 0..<100 where model.busy { await Task.yield() }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try inbox.readTrackAttempt()?.phase, .needsAttention)
        XCTAssertNil(model.snapshot)
        let restored = LogicTransportModel(file: file, operations: operations)
        XCTAssertTrue(restored.lastTrackAttempt?.requiresInspection == true)
        XCTAssertEqual(calls, 1)
        var after = expected
        after.exposedTracks?[0] = .init(number: 1, name: "Vocal", selected: true, muted: true, soloed: false)
        let successFile = directory.appendingPathComponent("fresh-session/current.json")
        let successInbox = LogicTransportInbox(file: successFile)
        let success = LogicTransportModel(file: successFile, snapshot: expected,
            operations: .init(inspect: { expected }, perform: { _, _ in expected }, performTrack: { _, _ in after }), trackControlsQualified: true)
        try successInbox.save(expected)
        let proposal = try successInbox.submitTrack(request, reason: "Explicit user comparison request")
        XCTAssertTrue(success.loadTrackProposal(proposal))
        success.reviewTrack(request)
        XCTAssertTrue(success.applyReviewedTrack())
        for _ in 0..<100 where success.busy { await Task.yield() }
        XCTAssertTrue(try successInbox.readTrackAttempt()?.actionOutcomeVerified == true)
        XCTAssertEqual(try successInbox.readTrackAttempt()?.proposal, proposal)
        XCTAssertEqual(success.snapshot, after)
    }
    func testTrackControlContractRequiresIdentityAndIsolatedFeedback() throws {
        var before = snapshot()
        before.exposedTracks = [.init(number: 1, name: "Vocals", selected: true, muted: false, soloed: false),
            .init(number: 2, name: "Guitar", selected: false, muted: false, soloed: false)]
        let request = LogicTrackControlRequest(observationID: before.id, trackNumber: 1, trackName: "Vocals", control: .mute, enabled: true)
        try request.validate(expected: before, observed: before)
        var siblingChanged = before
        siblingChanged.exposedTracks?[1] = .init(number: 2, name: "Guitar", selected: false, muted: true, soloed: false)
        XCTAssertThrowsError(try request.validate(expected: before, observed: siblingChanged))
        var selectionChanged = before
        selectionChanged.exposedTracks?[0] = .init(number: 1, name: "Vocals", selected: false, muted: false, soloed: false)
        XCTAssertThrowsError(try request.validate(expected: before, observed: selectionChanged))
        var coverageChanged = before
        coverageChanged.exposedTracks?.removeLast()
        XCTAssertThrowsError(try request.validate(expected: before, observed: coverageChanged))
        XCTAssertThrowsError(try request.validateAcknowledgement(expected: before, observed: before))
        var after = before
        after.id = UUID()
        after.exposedTracks?[0] = .init(number: 1, name: "Vocals", selected: true, muted: true, soloed: false)
        try request.validateAcknowledgement(expected: before, observed: after)
        XCTAssertThrowsError(try request.validate(expected: before, observed: after))
        after.exposedTracks?[1] = .init(number: 2, name: "Guitar", selected: false, muted: true, soloed: false)
        XCTAssertThrowsError(try request.validateAcknowledgement(expected: before, observed: after))
        var unknown = before
        unknown.exposedTracks?[0] = .init(number: 1, name: "Vocals", selected: true, muted: nil, soloed: false)
        XCTAssertThrowsError(try request.validate(expected: unknown, observed: unknown))
        var renamed = before
        renamed.exposedTracks?[0] = .init(number: 1, name: "New name", selected: true, muted: false, soloed: false)
        XCTAssertThrowsError(try request.validate(expected: before, observed: renamed))
        XCTAssertEqual(try JSONDecoder().decode(LogicTrackControlRequest.self, from: JSONEncoder().encode(request)), request)
    }
    @MainActor func testCompanionRefreshesCurrentProjectBeforeOpeningReview() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("current.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let fresh = snapshot(project: "new-project")
        var inspections = 0
        var actions = 0
        var old = snapshot()
        old.exposedTracks = [.init(number: 1, name: "Vocals", selected: true, muted: false, soloed: false)]
        let model = LogicTransportModel(file: file, snapshot: old, operations: .init(inspect: {
            inspections += 1
            return fresh
        }, perform: { _, observed in actions += 1; return observed }))
        try model.inbox.save(old)
        let request = LogicTrackControlRequest(observationID: old.id, trackNumber: 1, trackName: "Vocals", control: .mute, enabled: true)
        let proposal = try model.inbox.submitTrack(request, reason: "Compare without vocals")
        XCTAssertTrue(model.loadTrackProposal(proposal))
        model.requestCompanionReview()
        XCTAssertTrue(model.busy)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.companionReviewRequest)
        XCTAssertNil(model.reviewedTrackRequest)
        XCTAssertNil(model.reviewedTrackProposal)
        XCTAssertNil(model.trackReviewRequest)
        model.requestCompanionReview()
        for _ in 0..<100 where model.busy { await Task.yield() }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(inspections, 1)
        XCTAssertEqual(actions, 0)
        XCTAssertEqual(model.snapshot, fresh)
        XCTAssertNotNil(model.companionReviewRequest)
        XCTAssertEqual(try model.inbox.read(), fresh)
    }

    @MainActor func testFailedCompanionInspectionClearsSavedContextAndDoesNotOpenReview() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("current.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let old = snapshot()
        let model = LogicTransportModel(file: file, snapshot: old, operations: .init(inspect: {
            throw LogicTransportError.message("Logic project closed")
        }, perform: { _, observed in XCTFail("Must not press a control"); return observed }))
        try model.inbox.save(old)
        model.requestCompanionReview()
        for _ in 0..<100 where model.busy { await Task.yield() }
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.companionReviewRequest)
        XCTAssertNil(try model.inbox.read())
        XCTAssertEqual(model.error, "Logic project closed")
    }

    @MainActor func testCompanionRequestRequiresObservationAndDoesNotExecute() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("current.json")
        let missing = LogicTransportModel(operationsEnabled: false, file: file)
        missing.requestCompanionReview()
        XCTAssertNil(missing.companionReviewRequest)
        let observed = snapshot()
        let model = LogicTransportModel(operationsEnabled: false, file: file, snapshot: observed)
        model.requestCompanionReview()
        XCTAssertNotNil(model.companionReviewRequest)
        XCTAssertEqual(model.snapshot, observed)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.reviewedProposal)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    func testTrackHeaderIdentityPreservesNamesAndRejectsUnknownFormats() {
        XCTAssertEqual(LogicTrackObservation.identity(description: "Track 12 “Vocals — take 2”")?.0, 12)
        XCTAssertEqual(LogicTrackObservation.identity(description: "Track 12 “Vocals — take 2”")?.1, "Vocals — take 2")
        for value in ["Track 0 “A”", "Track -1 “A”", "Track 1 A", "Track 1 “A” extra", "Channel Strip 1 “A”", "Pista 1 “A”", "Track 1 “”"] {
            XCTAssertNil(LogicTrackObservation.identity(description: value))
        }
    }

    func testTrackEvidenceRoundTripAndOlderSnapshotCompatibility() throws {
        var observed = snapshot()
        observed.exposedTracks = [.init(number: 1, name: "Vocal", selected: true, muted: nil, soloed: false)]
        let data = try JSONEncoder().encode(observed)
        XCTAssertEqual(try JSONDecoder().decode(LogicTransportSnapshot.self, from: data), observed)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "exposedTracks")
        let restored = try JSONDecoder().decode(LogicTransportSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.exposedTracks)
    }
    func testCurrentStateReviewDoesNotClaimOriginalActionSucceeded() throws {
        let expected = snapshot()
        var attempt = LogicTransportAttempt(action: .play, expected: expected, proposalID: nil)
        attempt.startedAt = Date().addingTimeInterval(-10)
        let stoppedNow = snapshot()
        try attempt.reviewCurrentState(stoppedNow)
        XCTAssertEqual(attempt.phase, .reviewed)
        XCTAssertFalse(attempt.actionOutcomeVerified)
        XCTAssertFalse(attempt.requiresInspection)
        XCTAssertEqual(attempt.reviewedSnapshot, stoppedNow)
        XCTAssertNil(attempt.observed)
        XCTAssertNotNil(attempt.reviewedAt)
    }

    func testReviewNeedsNewSameProjectObservationOutsideRecording() {
        let expected = snapshot()
        for invalid in [expected, snapshot(project: "different"), snapshot(recording: true)] {
            var attempt = LogicTransportAttempt(action: .stop, expected: expected, proposalID: nil)
            attempt.startedAt = Date().addingTimeInterval(-10)
            XCTAssertThrowsError(try attempt.reviewCurrentState(invalid))
            XCTAssertEqual(attempt.phase, .pending)
        }
        var futureAttempt = LogicTransportAttempt(action: .stop, expected: expected, proposalID: nil)
        futureAttempt.startedAt = Date().addingTimeInterval(10)
        XCTAssertThrowsError(try futureAttempt.reviewCurrentState(snapshot()))
    }
    @MainActor func testAttemptIsDurableBeforeHostAndAcknowledgedAfterFeedback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = snapshot()
        let observed = snapshot(playing: true)
        let inbox = LogicTransportInbox(file: root.appendingPathComponent("current.json"))
        var calls = 0
        let operations = LogicTransportOperations(inspect: { expected }, perform: { action, supplied in
            calls += 1
            XCTAssertEqual(action, .play)
            XCTAssertEqual(supplied, expected)
            XCTAssertNil(try inbox.read())
            let pending = try XCTUnwrap(inbox.readAttempt())
            XCTAssertEqual(pending.phase, .pending)
            XCTAssertEqual(pending.expected, expected)
            return observed
        })
        let model = LogicTransportModel(file: inbox.file, snapshot: expected, operations: operations)
        model.apply(.play)
        for _ in 0..<100 where model.busy { await Task.yield() }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try inbox.readAttempt()?.phase, .acknowledged)
        XCTAssertEqual(try inbox.readAttempt()?.observed, observed)
        XCTAssertEqual(try inbox.read(), observed)
    }

    @MainActor func testFailedActionRemainsUnverifiedAndRelaunchDoesNotRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = snapshot()
        var calls = 0
        let operations = LogicTransportOperations(inspect: { expected }, perform: { _, _ in
            calls += 1
            throw LogicTransportError.message("No host acknowledgement")
        })
        let model = LogicTransportModel(file: root.appendingPathComponent("current.json"), snapshot: expected, operations: operations)
        model.apply(.play)
        for _ in 0..<100 where model.busy { await Task.yield() }
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(try model.inbox.read())
        XCTAssertEqual(try model.inbox.readAttempt()?.phase, .needsAttention)
        let restored = LogicTransportModel(file: model.inbox.file, operations: operations)
        XCTAssertTrue(restored.lastAttempt?.requiresInspection == true)
        XCTAssertNil(restored.snapshot)
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(restored.busy)
    }

    @MainActor func testReceiptWriteFailurePreventsHostInvocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("attempts"))
        var calls = 0
        let expected = snapshot()
        let operations = LogicTransportOperations(inspect: { expected }, perform: { _, _ in calls += 1; return expected })
        let model = LogicTransportModel(file: root.appendingPathComponent("current.json"), snapshot: expected, operations: operations)
        model.apply(.play)
        for _ in 0..<100 where model.busy { await Task.yield() }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.snapshot)
    }

    private func snapshot(pid: Int32 = 123, project: String = "fixture", playing: Bool = false, recording: Bool = false) -> LogicTransportSnapshot {
        .init(processID: pid, documentURL: URL(fileURLWithPath: "/tmp/\(project).logicx"), windowTitle: "Fixture - Tracks",
              playing: playing, recording: recording, inspectedAt: Date())
    }

    func testAcknowledgementMustMatchProjectAndRequestedState() throws {
        try LogicTransportAction.play.validateAcknowledgement(expected: snapshot(), observed: snapshot(playing: true))
        try LogicTransportAction.stop.validateAcknowledgement(expected: snapshot(playing: true), observed: snapshot())
        for invalid in [snapshot(), snapshot(pid: 456, playing: true), snapshot(project: "other", playing: true), snapshot(playing: true, recording: true)] {
            XCTAssertThrowsError(try LogicTransportAction.play.validateAcknowledgement(expected: snapshot(), observed: invalid))
        }
    }

    func testProjectProcessTransportAndRecordingConflictsBlockActions() {
        for action in LogicTransportAction.allCases {
            for changed in [snapshot(pid: 456), snapshot(project: "other"), snapshot(playing: true), snapshot(recording: true)] {
                XCTAssertThrowsError(try action.validate(expected: snapshot(), observed: changed))
            }
            XCTAssertThrowsError(try action.validate(expected: snapshot(recording: true), observed: snapshot()))
        }
    }

    func testUnchangedStoppedAndPlayingStatesCanBeReviewed() throws {
        for action in LogicTransportAction.allCases {
            try action.validate(expected: snapshot(), observed: snapshot())
            try action.validate(expected: snapshot(playing: true), observed: snapshot(playing: true))
        }
        XCTAssertTrue(LogicTransportAction.play.requestedPlaying)
        XCTAssertFalse(LogicTransportAction.stop.requestedPlaying)
    }

    func testObservedStopTitleChangeIsSafeOnlyWhenStopped() {
        XCTAssertTrue(LogicTransportAction.recognizesStopControl(title: "Stop", playing: true))
        XCTAssertTrue(LogicTransportAction.recognizesStopControl(title: "Go to Beginning", playing: false))
        XCTAssertFalse(LogicTransportAction.recognizesStopControl(title: "Go to Beginning", playing: true))
        XCTAssertFalse(LogicTransportAction.recognizesStopControl(title: "Record", playing: false))
    }

    @MainActor func testPreviewCannotInspectOrPerformTransport() {
        let model = LogicTransportModel(operationsEnabled: false)
        model.inspect()
        model.apply(.play)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.result)
    }

    @MainActor func testProposalQueueAndReviewDoNotControlHostOrChangeObservation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let observed = snapshot()
        let model = LogicTransportModel(operationsEnabled: false, file: root.appendingPathComponent("current.json"), snapshot: observed)
        try model.inbox.save(observed)
        let saved = try Data(contentsOf: model.inbox.file)
        let proposal = try model.inbox.submit(observationID: observed.id, action: .play, reason: "The user requested playback.")
        XCTAssertEqual(try Data(contentsOf: model.inbox.file), saved)
        XCTAssertEqual(try model.proposals(), [proposal])
        XCTAssertNil(model.reviewedProposal)
        XCTAssertTrue(model.loadProposal(proposal))
        XCTAssertEqual(model.reviewedProposal, proposal)
        XCTAssertEqual(model.snapshot, observed)
        XCTAssertFalse(model.busy)
        model.apply(.play)
        XCTAssertEqual(model.snapshot, observed)
        XCTAssertNil(model.result)
    }

    @MainActor func testReplacedObservationAndChangedProposalAreRejectedOnReview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let observed = snapshot()
        let inbox = LogicTransportInbox(file: root.appendingPathComponent("current.json"))
        try inbox.save(observed)
        let proposal = try inbox.submit(observationID: observed.id, action: .stop, reason: "Stop as requested.")
        let changedModel = LogicTransportModel(operationsEnabled: false, file: inbox.file, snapshot: snapshot())
        XCTAssertFalse(changedModel.loadProposal(proposal))
        XCTAssertNil(changedModel.reviewedProposal)
        let model = LogicTransportModel(operationsEnabled: false, file: inbox.file, snapshot: observed)
        var replaced = proposal
        replaced.submittedAt = proposal.submittedAt.addingTimeInterval(1)
        try JSONEncoder().encode(replaced).write(to: inbox.proposalsDirectory.appendingPathComponent(proposal.id.uuidString + ".json"))
        XCTAssertFalse(model.loadProposal(proposal))
        XCTAssertNil(model.reviewedProposal)
    }

    func testRecordingMissingObservationAndInvalidReasonsRejectSubmission() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = LogicTransportInbox(file: root.appendingPathComponent("current.json"))
        let observed = snapshot(recording: true)
        try inbox.save(observed)
        XCTAssertThrowsError(try inbox.submit(observationID: observed.id, action: .play, reason: "Play"))
        let stopped = snapshot()
        try inbox.save(stopped)
        XCTAssertThrowsError(try inbox.submit(observationID: UUID(), action: .stop, reason: "Stop"))
        for reason in [" \n ", String(repeating: "a", count: 2001)] {
            XCTAssertThrowsError(try inbox.submit(observationID: stopped.id, action: .stop, reason: reason))
        }
        try inbox.save(nil)
        XCTAssertNil(try inbox.read())
        XCTAssertThrowsError(try inbox.submit(observationID: stopped.id, action: .stop, reason: "Stop"))
    }
}
