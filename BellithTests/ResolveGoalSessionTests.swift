import XCTest
@testable import Bellith

final class ResolveGoalSessionTests: XCTestCase {
    @MainActor func testMissingAccessDoesNotStartInspectionOrAppendRepeatedFailures() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = ResolveHarnessModel(storage: root)
        model.accessibilityAvailable = false
        let id = model.session.id
        let phase = model.session.phase
        let eventCount = model.session.events.count
        model.inspect()
        model.inspect()
        XCTAssertFalse(model.canInspect)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.session.id, id)
        XCTAssertEqual(model.session.phase, phase)
        XCTAssertEqual(model.session.events.count, eventCount)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    @MainActor
    func testPreviewCannotInspectPlanOrExecuteHostOperations() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = ResolveHarnessModel(storage: root, hostOperationsEnabled: false)
        model.session.source = snapshot()
        model.session.plan = ResolveEditPlan(summary: "Copy", blockedReason: "", removeClipKeys: [])
        model.session.phase = .review
        XCTAssertFalse(model.canRun)
        model.inspect()
        model.planWithCLI()
        model.runReviewedPlan()
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.session.phase, .review)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    private func snapshot(clips: [ResolveClip]? = nil) -> ResolveSnapshot {
        ResolveSnapshot(projectID: "project", projectName: "Fixture", timelineID: "source", timelineName: "Source",
                        startFrame: 0, endFrame: 48, frameRate: "24", product: "Resolve", version: "21.1",
                        clips: clips ?? [ResolveClip(key: "clip-a", name: "A", kind: "audio", track: 1, startFrame: 0, endFrame: 24)], signature: "source-layout")
    }

    func testUnknownRepeatedAndBlockedPlansAreRejected() {
        for plan in [
            ResolveEditPlan(summary: "Remove", blockedReason: "", removeClipKeys: ["missing"]),
            ResolveEditPlan(summary: "Remove", blockedReason: "", removeClipKeys: ["clip-a", "clip-a"]),
            ResolveEditPlan(summary: "Need footage", blockedReason: "Cannot judge speech from names", removeClipKeys: []),
        ] { XCTAssertThrowsError(try plan.validate(against: snapshot())) }
    }

    func testAmbiguousClipKeysAreRejected() {
        let clip = snapshot().clips[0]
        XCTAssertThrowsError(try ResolveEditPlan(summary: "Remove", blockedReason: "", removeClipKeys: [clip.key])
            .validate(against: snapshot(clips: [clip, clip])))
    }

    func testCopyOnlyAndKnownRemovalAreAccepted() throws {
        try ResolveEditPlan(summary: "Copy", blockedReason: "", removeClipKeys: []).validate(against: snapshot())
        try ResolveEditPlan(summary: "Remove", blockedReason: "", removeClipKeys: ["clip-a"]).validate(against: snapshot())
    }

    func testInterruptedMutationRequiresAttentionWithoutLosingCheckpoint() throws {
        var session = ResolveGoalSession()
        session.source = snapshot()
        session.phase = .editing
        let restored = try JSONDecoder().decode(ResolveGoalSession.self, from: JSONEncoder().encode(session))
        session = restored
        session.recoverAfterLaunch()
        XCTAssertEqual(session.phase, .needsAttention)
        XCTAssertEqual(session.source?.timelineID, "source")
        XCTAssertNotNil(session.error)
    }

    func testReviewSessionDoesNotResumeExecutionAfterRelaunch() {
        var session = ResolveGoalSession()
        session.phase = .review
        session.recoverAfterLaunch()
        XCTAssertEqual(session.phase, .review)
    }

    private func recoverySnapshot(id: String, clips: [ResolveClip], tracks: [Int] = [0, 1, 0],
                                  fps: String = "24", end: Double = 48) throws -> ResolveSnapshot {
        let signature = String(decoding: try JSONSerialization.data(withJSONObject: [
            "keys": clips.map(\.key).sorted(), "tracks": tracks, "start": 0, "finish": end, "fps": fps,
            "enabledByKey": Dictionary(clips.compactMap { clip in clip.enabled.map { (clip.key, $0) } }, uniquingKeysWith: { first, _ in first }),
        ], options: .sortedKeys), as: UTF8.self)
        return ResolveSnapshot(projectID: "project", projectName: "Fixture", timelineID: id,
                               timelineName: id == "source" ? "Source" : "Bellith - fixture",
                               startFrame: 0, endFrame: end, frameRate: fps, product: "Resolve", version: "21.1",
                               clips: clips, signature: signature)
    }

    func testWorkingCopyReconciliationRejectsUnexpectedEnabledStateChange() throws {
        let clip = ResolveClip(key: "clip-a", name: "A", kind: "audio", track: 1, startFrame: 0, endFrame: 24, enabled: true)
        let source = try recoverySnapshot(id: "source", clips: [clip])
        var disabled = clip
        disabled.enabled = false
        let working = try recoverySnapshot(id: "copy", clips: [disabled])
        let plan = ResolveEditPlan(summary: "Copy only", blockedReason: "", removeClipKeys: [])
        XCTAssertThrowsError(try ResolveWorkingCopyRecovery.reconcile(source: source, observed: working,
            plan: plan, copyName: "Bellith - fixture", recordedID: "copy"))
        let decoded = try JSONDecoder().decode(ResolveClip.self, from: JSONEncoder().encode(disabled))
        XCTAssertEqual(decoded.enabled, false)
    }

    func testClipSourceRangeDecodePreservesUnknownAndZero() throws {
        let legacy = Data(#"{"key":"a","name":"A","kind":"video","track":1,"startFrame":0,"endFrame":24}"#.utf8)
        var clip = try JSONDecoder().decode(ResolveClip.self, from: legacy)
        XCTAssertNil(clip.sourceStartFrame)
        XCTAssertNil(clip.sourceEndFrame)
        XCTAssertNil(clip.mediaPoolItemID)
        clip.sourceStartFrame = 0
        clip.sourceEndFrame = 23
        clip.mediaPoolItemID = "synthetic-media-id"
        let decoded = try JSONDecoder().decode(ResolveClip.self, from: JSONEncoder().encode(clip))
        XCTAssertEqual(decoded.sourceStartFrame, 0)
        XCTAssertEqual(decoded.sourceEndFrame, 23)
        XCTAssertEqual(decoded.mediaPoolItemID, "synthetic-media-id")
        XCTAssertEqual(decoded, clip)
    }

    func testRecoveryDistinguishesUnappliedAndCompletedRemovals() throws {
        let clips = snapshot().clips
        let source = try recoverySnapshot(id: "source", clips: clips)
        let copy = try recoverySnapshot(id: "copy", clips: clips)
        let plan = ResolveEditPlan(summary: "Remove", blockedReason: "", removeClipKeys: ["clip-a"])
        XCTAssertEqual(try ResolveWorkingCopyRecovery.reconcile(source: source, observed: copy, plan: plan,
                          copyName: "Bellith - fixture", recordedID: "copy"), .unchanged)
        let edited = try recoverySnapshot(id: "copy", clips: [], end: 0)
        XCTAssertEqual(try ResolveWorkingCopyRecovery.reconcile(source: source, observed: edited, plan: plan,
                          copyName: "Bellith - fixture", recordedID: "copy"), .edited)
    }

    func testRecoveryRejectsTrackFrameRatePositionAndIdentityChanges() throws {
        let clips = snapshot().clips
        let source = try recoverySnapshot(id: "source", clips: clips)
        let moved = ResolveClip(key: "clip-a", name: "A", kind: "audio", track: 1, startFrame: 4, endFrame: 28)
        let plan = ResolveEditPlan(summary: "Copy", blockedReason: "", removeClipKeys: [])
        for observed in [try recoverySnapshot(id: "copy", clips: clips, tracks: [1, 1, 0]),
                         try recoverySnapshot(id: "copy", clips: clips, fps: "30"),
                         try recoverySnapshot(id: "copy", clips: [moved]), source,
                         try recoverySnapshot(id: "other", clips: clips)] {
            XCTAssertThrowsError(try ResolveWorkingCopyRecovery.reconcile(source: source, observed: observed,
                plan: plan, copyName: "Bellith - fixture", recordedID: "copy"))
        }
    }

    func testRecoveryRejectsPartialRemovalAndChangedSurvivor() throws {
        let a = snapshot().clips[0]
        let b = ResolveClip(key: "clip-b", name: "B", kind: "audio", track: 1, startFrame: 24, endFrame: 48)
        let c = ResolveClip(key: "clip-c", name: "C", kind: "audio", track: 1, startFrame: 48, endFrame: 72)
        let source = try recoverySnapshot(id: "source", clips: [a, b, c], end: 72)
        let plan = ResolveEditPlan(summary: "Remove A and B", blockedReason: "", removeClipKeys: [a.key, b.key])
        let changed = ResolveClip(key: c.key, name: c.name, kind: c.kind, track: c.track,
                                  startFrame: 36, endFrame: 60)
        for observed in [try recoverySnapshot(id: "copy", clips: [b, c], end: 72),
                         try recoverySnapshot(id: "copy", clips: [changed], end: 60)] {
            XCTAssertThrowsError(try ResolveWorkingCopyRecovery.reconcile(source: source, observed: observed,
                plan: plan, copyName: "Bellith - fixture", recordedID: "copy"))
        }
        let completed = try recoverySnapshot(id: "copy", clips: [c], end: 72)
        XCTAssertEqual(try ResolveWorkingCopyRecovery.reconcile(source: source, observed: completed,
            plan: plan, copyName: "Bellith - fixture", recordedID: "copy"), .edited)
    }

    func testRecoveryRejectsBlockedPlansAndUnrecognizedEvidence() throws {
        let source = try recoverySnapshot(id: "source", clips: snapshot().clips)
        let copy = try recoverySnapshot(id: "copy", clips: snapshot().clips)
        let blocked = ResolveEditPlan(summary: "Blocked", blockedReason: "Unsupported goal", removeClipKeys: [])
        XCTAssertThrowsError(try ResolveWorkingCopyRecovery.reconcile(source: source, observed: copy,
            plan: blocked, copyName: "Bellith - fixture", recordedID: nil))
        XCTAssertThrowsError(try ResolveWorkingCopyRecovery.reconcile(source: snapshot(), observed: copy,
            plan: ResolveEditPlan(summary: "Copy", blockedReason: "", removeClipKeys: []),
            copyName: "Bellith - fixture", recordedID: nil))
    }

    private func withMarkers(_ snapshot: ResolveSnapshot, markers: [ResolveMarker]) throws -> ResolveSnapshot {
        var copy = snapshot
        copy.markers = markers
        var signature = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(snapshot.signature.utf8)) as? [String: Any])
        signature["markers"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(markers))
        let updated = String(decoding: try JSONSerialization.data(withJSONObject: signature, options: .sortedKeys), as: UTF8.self)
        return ResolveSnapshot(projectID: copy.projectID, projectName: copy.projectName, timelineID: copy.timelineID,
            timelineName: copy.timelineName, startFrame: copy.startFrame, endFrame: copy.endFrame,
            frameRate: copy.frameRate, product: copy.product, version: copy.version, clips: copy.clips,
            signature: updated, markers: markers)
    }

    func testMarkerPlansRequireFreshFreeWholeFrameOffsetsAndSeparateOperations() throws {
        var source = snapshot()
        source.markers = [ResolveMarker(frame: 5, color: "Red", name: "Existing", note: "", duration: 1, customData: "")]
        for frame in [-1.0, 0.5, 5, 48, Double.infinity, Double.nan] {
            let plan = ResolveEditPlan(summary: "Note", blockedReason: "", removeClipKeys: [],
                markerNotes: [ResolveMarkerNote(frame: frame, name: "Review", note: "Listen")])
            XCTAssertThrowsError(try plan.validate(against: source))
        }
        let note = ResolveMarkerNote(frame: 12, name: "Review", note: "Listen locally")
        try ResolveEditPlan(summary: "Note", blockedReason: "", removeClipKeys: [], markerNotes: [note]).validate(against: source)
        XCTAssertThrowsError(try ResolveEditPlan(summary: "Mixed", blockedReason: "", removeClipKeys: ["clip-a"], markerNotes: [note]).validate(against: source))
        XCTAssertThrowsError(try ResolveEditPlan(summary: "Stale", blockedReason: "", removeClipKeys: [], markerNotes: [note]).validate(against: snapshot()))
    }

    func testMarkerRecoveryRequiresCompleteNotesAndPreservesExistingMarkers() throws {
        let existing = ResolveMarker(frame: 5, color: "Red", name: "Existing", note: "Keep", duration: 1, customData: "user")
        let source = try withMarkers(recoverySnapshot(id: "source", clips: snapshot().clips), markers: [existing])
        let untouched = try withMarkers(recoverySnapshot(id: "copy", clips: snapshot().clips), markers: [existing])
        let notes = [ResolveMarkerNote(frame: 10, name: "A", note: "Check"), ResolveMarkerNote(frame: 20, name: "B", note: "Check")]
        let plan = ResolveEditPlan(summary: "Two notes", blockedReason: "", removeClipKeys: [], markerNotes: notes)
        XCTAssertEqual(try ResolveWorkingCopyRecovery.reconcile(source: source, observed: untouched,
            plan: plan, copyName: "Bellith - fixture", recordedID: "copy"), .unchanged)
        let completed = try withMarkers(untouched, markers: [existing] + notes.map { $0.marker(copyName: "Bellith - fixture") })
        XCTAssertEqual(try ResolveWorkingCopyRecovery.reconcile(source: source, observed: completed,
            plan: plan, copyName: "Bellith - fixture", recordedID: "copy"), .edited)
        let partial = try withMarkers(untouched, markers: [existing, notes[0].marker(copyName: "Bellith - fixture")])
        XCTAssertThrowsError(try ResolveWorkingCopyRecovery.reconcile(source: source, observed: partial,
            plan: plan, copyName: "Bellith - fixture", recordedID: "copy"))
        let lostExisting = try withMarkers(untouched, markers: notes.map { $0.marker(copyName: "Bellith - fixture") })
        XCTAssertThrowsError(try ResolveWorkingCopyRecovery.reconcile(source: source, observed: lostExisting,
            plan: plan, copyName: "Bellith - fixture", recordedID: "copy"))
    }

    @MainActor
    func testCLIProposalImportsForReviewWithoutCreatingWorkingCopy() throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent("ProposalReview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let model = ResolveHarnessModel(storage: storage)
        model.session.source = snapshot()
        model.session.goal = "Remove A"
        let proposal = ResolvePlanProposal(sessionID: model.session.id, goal: model.session.goal,
            sourceSignature: model.session.source!.signature,
            plan: ResolveEditPlan(summary: "Remove A, leaving a gap", blockedReason: "", removeClipKeys: ["clip-a"]))
        let inbox = model.directory.appendingPathComponent("proposals", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let file = inbox.appendingPathComponent(proposal.id.uuidString + ".json")
        try JSONEncoder().encode(proposal).write(to: file)
        model.reviewLatestCLIProposal()
        XCTAssertEqual(model.session.phase, .review)
        XCTAssertEqual(model.session.plan, proposal.plan)
        XCTAssertNil(model.session.working)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.session.error)
        XCTAssertEqual(model.session.events.last?.title, "CLI proposal opened for review")
        let rejected = ResolvePlanProposal(sessionID: model.session.id, goal: "Different task",
            sourceSignature: model.session.source!.signature,
            plan: ResolveEditPlan(summary: "Wrong task", blockedReason: "", removeClipKeys: []))
        try JSONEncoder().encode(rejected).write(to: file)
        model.reviewLatestCLIProposal()
        XCTAssertNotNil(model.session.error)
        XCTAssertEqual(model.session.plan, proposal.plan)
        XCTAssertNil(model.session.working)
    }

    @MainActor
    func testProposalChoiceCanLoadOlderPlanAndRejectChangedPreview() throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent("ProposalChoice-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let model = ResolveHarnessModel(storage: storage)
        model.session.source = snapshot()
        let original = ResolveEditPlan(summary: "Current manual plan", blockedReason: "", removeClipKeys: [])
        model.session.plan = original
        let older = ResolvePlanProposal(submittedAt: Date(timeIntervalSince1970: 10), sessionID: model.session.id,
            goal: model.session.goal, sourceSignature: model.session.source!.signature,
            plan: ResolveEditPlan(summary: "Older removal proposal", blockedReason: "", removeClipKeys: ["clip-a"]))
        let newer = ResolvePlanProposal(submittedAt: Date(timeIntervalSince1970: 20), sessionID: model.session.id,
            goal: model.session.goal, sourceSignature: model.session.source!.signature,
            plan: ResolveEditPlan(summary: "Newer copy proposal", blockedReason: "", removeClipKeys: []))
        let inbox = model.directory.appendingPathComponent("proposals", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        for proposal in [older, newer] {
            try JSONEncoder().encode(proposal).write(to: inbox.appendingPathComponent(proposal.id.uuidString + ".json"))
        }
        XCTAssertEqual(try model.cliProposals().map(\.id), [newer.id, older.id])
        XCTAssertEqual(model.session.plan, original, "Listing proposals must not replace the active plan")
        XCTAssertTrue(model.reviewCLIProposal(id: older.id, expected: older))
        XCTAssertEqual(model.session.plan, older.plan)
        var changed = newer
        changed = ResolvePlanProposal(id: newer.id, submittedAt: newer.submittedAt, sessionID: newer.sessionID,
            goal: newer.goal, sourceSignature: newer.sourceSignature,
            plan: ResolveEditPlan(summary: "Changed after preview", blockedReason: "", removeClipKeys: ["clip-a"]))
        try JSONEncoder().encode(changed).write(to: inbox.appendingPathComponent(newer.id.uuidString + ".json"))
        XCTAssertFalse(model.reviewCLIProposal(id: newer.id, expected: newer))
        XCTAssertEqual(model.session.plan, older.plan)
        XCTAssertNil(model.session.working)
    }

    func testCLIProposalRequiresExactReviewableSessionGoalAndSource() throws {
        var session = ResolveGoalSession()
        session.source = snapshot()
        session.goal = "Remove A"
        let plan = ResolveEditPlan(summary: "Remove A on copy", blockedReason: "", removeClipKeys: ["clip-a"])
        let proposal = ResolvePlanProposal(sessionID: session.id, goal: session.goal,
            sourceSignature: session.source!.signature, plan: plan)
        try proposal.validate(for: session)
        session.phase = .review
        try proposal.validate(for: session)
        for phase in [ResolveGoalSession.Phase.planning, .duplicating, .editing, .paused, .needsAttention, .accepted] {
            var changed = session
            changed.phase = phase
            XCTAssertThrowsError(try proposal.validate(for: changed))
        }
        var changed = session
        changed.goal = "Another goal"
        XCTAssertThrowsError(try proposal.validate(for: changed))
        changed = session
        changed.id = UUID()
        XCTAssertThrowsError(try proposal.validate(for: changed))
        changed = session
        changed.working = snapshot()
        XCTAssertThrowsError(try proposal.validate(for: changed))
        let stale = ResolvePlanProposal(sessionID: session.id, goal: session.goal, sourceSignature: "stale", plan: plan)
        XCTAssertThrowsError(try stale.validate(for: session))
    }

    func testClaudeStructuredOutputUsesSharedValidation() throws {
        let response = Data(#"{"is_error":false,"structured_output":{"summary":"Remove A, leaving a gap","blockedReason":"","removeClipKeys":["clip-a"]}}"#.utf8)
        let plan = try ResolvePlannerResponse.claude(response)
        try plan.validate(against: snapshot())
        XCTAssertEqual(plan.removeClipKeys, ["clip-a"])
    }

    func testClaudeAuthenticationFailurePreservesActionableReason() {
        let response = Data(#"{"is_error":true,"result":"OAuth session expired and could not be refreshed"}"#.utf8)
        XCTAssertThrowsError(try ResolvePlannerResponse.claude(response)) { error in
            XCTAssertTrue(error.localizedDescription.contains("OAuth session expired"))
        }
    }

    func testClaudeMissingAndMalformedStructuredOutputAreRejected() {
        for response in [#"{"is_error":false,"result":"I edited your timeline"}"#,
                         #"{"structured_output":{"summary":"Copy"}}"#, "invalid"] {
            XCTAssertThrowsError(try ResolvePlannerResponse.claude(Data(response.utf8)))
        }
    }

    func testLuaLiteralEscapesCodeAndUTF8AsData() {
        XCTAssertEqual(ResolveLuaLiteral.string("\"\n\\"), "\"\\034\\010\\092\"")
        XCTAssertEqual(ResolveLuaLiteral.string("é"), "\"\\195\\169\"")
        let payload = "\"); os.execute('touch /tmp/not-allowed'); --"
        XCTAssertTrue(ResolveLuaLiteral.string(payload).hasPrefix("\"\\034"))
    }
}
