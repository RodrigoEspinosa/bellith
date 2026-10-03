import AppKit
import ApplicationServices
import Combine

@MainActor
final class ResolveHarnessModel: ObservableObject {
    @Published var session = ResolveGoalSession()
    @Published var busy = false
    @Published var pauseRequested = false
    @Published var accessibilityAvailable = AXIsProcessTrusted()
    @Published var provider: CreativePlannerProvider = .codex
    @Published private(set) var proposalReviewRequest: CreativeReviewRequest?
    @Published private(set) var companionReviewRequest: UUID?
    func requestCompanionReview() {
        guard !busy, session.source != nil else { return }
        do {
            try persist()
            companionReviewRequest = UUID()
        } catch { session.error = "Session could not be saved: \(error.localizedDescription)" }
    }
    func requestProposalReview(_ id: UUID?) { proposalReviewRequest = CreativeReviewRequest(proposalID: id) }
    func dismissProposalReview() { proposalReviewRequest = nil }
    func dismissCompanionReview() { companionReviewRequest = nil }
    let adapter = ResolveComputerAdapter()
    let planner = ResolveGoalPlanner()
    private var task: Task<Void, Never>?
    private let storage: URL
    let hostOperationsEnabled: Bool

    init(storage: URL? = nil, hostOperationsEnabled: Bool = true) {
        self.hostOperationsEnabled = hostOperationsEnabled
        self.storage = storage ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bellith/GoalSessions", isDirectory: true)
        let current = self.storage.appendingPathComponent("current.json")
        if FileManager.default.fileExists(atPath: current.path) {
            do {
                session = try JSONDecoder().decode(ResolveGoalSession.self, from: Data(contentsOf: current))
                session.recoverAfterLaunch()
            } catch {
                session.error = "The previous session could not be loaded: \(error.localizedDescription)"
            }
        }
    }

    var directory: URL { storage.appendingPathComponent(session.id.uuidString, isDirectory: true) }
    var canInspect: Bool { hostOperationsEnabled && !busy && accessibilityAvailable }
    var canRun: Bool { hostOperationsEnabled && accessibilityAvailable && !busy && [.review, .paused].contains(session.phase) && session.plan?.blockedReason.isEmpty == true }

    func refreshPermissions() { accessibilityAvailable = adapter.accessibilityAvailable }

    func newSession() {
        guard !busy else { return }
        session = ResolveGoalSession()
        saveOrReport()
    }

    func updateGoal(_ goal: String) {
        guard !busy, session.working == nil else { return }
        session.goal = goal
        session.plan = nil
        session.phase = .draft
        saveOrReport()
    }

    func inspect() {
        guard canInspect else { return }
        start(.inspecting) {
            var fields: [String: String] = [:]
            if let source = self.session.source {
                fields = ["projectID": source.projectID, "sourceID": source.timelineID, "sourceSignature": source.signature]
            }
            let observed = try await self.adapter.invoke(operation: "inspect", directory: self.directory, fields: fields)
            if let source = self.session.source {
                guard observed.projectID == source.projectID else { throw HarnessError.message("A different project is open. Start a new session to work on it.") }
                if observed.timelineID == source.timelineID && self.session.working == nil {
                    guard observed.signature == source.signature else { throw HarnessError.message("The original timeline changed. Start a new session to make a fresh plan.") }
                    self.session.phase = self.session.plan == nil ? .draft : .review
                } else if observed.timelineName == self.session.copyName,
                          self.session.working == nil || observed.timelineID == self.session.working?.timelineID {
                    guard let plan = self.session.plan else {
                        throw HarnessError.message("No reviewed plan is saved for this working copy. Start a new session.")
                    }
                    let result = try ResolveWorkingCopyRecovery.reconcile(
                        source: source, observed: observed, plan: plan, copyName: self.session.copyName,
                        recordedID: self.session.working?.timelineID)
                    self.session.working = observed
                    self.session.phase = result == .edited ? .readyForReview : .paused
                    self.record("Working copy reconciled", result == .edited
                        ? "The inspected copy matches the reviewed result. Playback review is still required."
                        : "The inspected copy matches the source. Reviewed removals have not been applied.")
                } else {
                    throw HarnessError.message("Select this session’s original or working timeline in Resolve, then inspect again.")
                }
            } else {
                self.session.source = observed
                self.session.phase = .draft
            }
            self.record("Timeline inspected", "\(observed.projectName) / \(observed.timelineName) · \(observed.clips.count) items · Resolve \(observed.version)")
        }
    }

    func planWithCLI() {
        guard let source = session.source, session.working == nil else { return }
        let provider = provider
        start(.planning) {
            let plan = try await self.planner.plan(goal: self.session.goal, snapshot: source, directory: self.directory, provider: provider)
            self.session.plan = plan
            self.session.phase = plan.blockedReason.isEmpty ? .review : .needsAttention
            self.session.error = plan.blockedReason.isEmpty ? nil : plan.blockedReason
            self.record("Plan proposed by \(provider.rawValue)", plan.summary)
        }
    }

    func cliProposals() throws -> [ResolvePlanProposal] {
        let inbox = directory.appendingPathComponent("proposals", isDirectory: true)
        guard FileManager.default.fileExists(atPath: inbox.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: inbox,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard urls.count <= 1000 else { throw HarnessError.message("This session has too many proposal files. Start a new session to continue.") }
        var proposals: [ResolvePlanProposal] = []
        for url in urls where url.pathExtension == "json" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 100_000 else { continue }
            if let proposal = try? JSONDecoder().decode(ResolvePlanProposal.self, from: Data(contentsOf: url)),
               url.deletingPathExtension().lastPathComponent == proposal.id.uuidString {
                proposals.append(proposal)
            }
        }
        return proposals.sorted {
            $0.submittedAt == $1.submittedAt ? $0.id.uuidString < $1.id.uuidString : $0.submittedAt > $1.submittedAt
        }
    }

    func reviewCLIProposal(id: UUID, expected: ResolvePlanProposal? = nil) -> Bool {
        guard !busy, session.working == nil else { return false }
        do {
            let matches = try cliProposals().filter { $0.id == id }
            guard matches.count == 1, let proposal = matches.first else {
                throw HarnessError.message("The selected proposal is missing or ambiguous. Refresh the proposal list.")
            }
            guard expected == nil || expected == proposal else {
                throw HarnessError.message("The proposal changed after preview. Refresh and review it again.")
            }
            try proposal.validate(for: session)
            session.plan = proposal.plan
            session.phase = .review
            session.error = nil
            record("CLI proposal opened for review", "Proposal \(proposal.id.uuidString): \(proposal.plan.summary)")
            saveOrReport()
            return session.error == nil
        } catch {
            session.error = error.localizedDescription
            return false
        }
    }

    func reviewLatestCLIProposal() {
        do {
            guard let proposal = try cliProposals().first else { throw HarnessError.message("No CLI proposal is available for this session.") }
            _ = reviewCLIProposal(id: proposal.id)
        } catch { session.error = error.localizedDescription }
    }

    func copyOnlyPlan() {
        guard !busy, session.source != nil, session.working == nil else { return }
        session.goal = "Create a working copy of the current timeline for a new edit."
        session.plan = ResolveEditPlan(summary: "Duplicate the inspected timeline and verify its clip layout. Leave the source unchanged.", blockedReason: "", removeClipKeys: [])
        session.phase = .review
        session.error = nil
        record("Working-copy plan prepared", "No clips will be removed.")
        saveOrReport()
    }

    func toggleRemoval(_ key: String) {
        guard !busy, session.phase == .review, var plan = session.plan, plan.markerNotes.isEmpty else { return }
        if plan.removeClipKeys.contains(key) { plan.removeClipKeys.removeAll { $0 == key } }
        else { plan.removeClipKeys.append(key) }
        plan.summary = "Create a working copy, then remove \(plan.removeClipKeys.count) selected whole clips, leaving gaps."
        session.plan = plan
        saveOrReport()
    }

    func runReviewedPlan() {
        guard canRun, let source = session.source, let plan = session.plan else { return }
        start(session.working == nil ? .duplicating : .editing) {
            try plan.validate(against: source)
            if self.session.working == nil {
                self.record("Creating working copy", self.session.copyName)
                try self.persist() // Intent must reach disk before a mutation can be sent.
                let copy = try await self.adapter.invoke(operation: "duplicate", directory: self.directory, fields: [
                    "projectID": source.projectID, "timelineID": source.timelineID,
                    "expectedSignature": source.signature, "copyName": self.session.copyName,
                ])
                self.session.working = copy
                self.record("Working copy verified", "\(copy.clips.count) items match the source. Original timeline is unchanged.")
                try self.persist()
            }
            if self.pauseRequested {
                self.session.phase = .paused
                self.record("Paused", "Stopped at the working-copy checkpoint.")
                return
            }
            guard let copy = self.session.working else { throw HarnessError.message("No working timeline is recorded.") }
            if !plan.removeClipKeys.isEmpty {
                self.session.phase = .editing
                self.record("Applying reviewed removals", "\(plan.removeClipKeys.count) whole items; gaps are preserved.")
                try self.persist()
                let result = try await self.adapter.invoke(operation: "removeClips", directory: self.directory, fields: [
                    "projectID": source.projectID, "timelineID": copy.timelineID,
                    "expectedSignature": copy.signature, "copyName": self.session.copyName,
                    "sourceID": source.timelineID, "sourceSignature": source.signature,
                ], removeKeys: plan.removeClipKeys)
                self.session.working = result
                self.record("Edit verified", "Requested items are absent, remaining clip positions match, and the original is unchanged.")
            }
            if !plan.markerNotes.isEmpty {
                self.session.phase = .editing
                self.record("Adding reviewed timeline notes", "\(plan.markerNotes.count) one-frame Blue markers on the working copy.")
                try self.persist()
                let result = try await self.adapter.invoke(operation: "addMarkers", directory: self.directory, fields: [
                    "projectID": source.projectID, "timelineID": copy.timelineID,
                    "expectedSignature": copy.signature, "copyName": self.session.copyName,
                    "sourceID": source.timelineID, "sourceSignature": source.signature,
                ], markerNotes: plan.markerNotes)
                self.session.working = result
                self.record("Timeline notes verified", "Reviewed marker text and positions match; existing notes, clips, and the original are unchanged.")
            }
            self.session.phase = .readyForReview
            self.record("Ready for playback review", "Structural checks passed. Watch and listen in Resolve before accepting the result.")
        }
    }

    func pause() {
        guard busy else { return }
        pauseRequested = true
        if session.phase == .planning { planner.cancel() }
        record("Pause requested", "Any submitted Resolve operation will finish and be checked before stopping.")
        saveOrReport()
    }

    func acceptReview() {
        guard !busy, session.phase == .readyForReview else { return }
        session.phase = .accepted
        record("Review accepted", "You accepted the working copy. The source timeline remains available in Resolve.")
        saveOrReport()
    }

    func revealSession() { NSWorkspace.shared.activateFileViewerSelecting([directory]) }

    private func start(_ phase: ResolveGoalSession.Phase, operation: @escaping @MainActor () async throws -> Void) {
        guard hostOperationsEnabled, !busy else { return }
        busy = true
        pauseRequested = false
        session.phase = phase
        session.error = nil
        refreshPermissions()
        task = Task {
            do {
                try persist()
                try await operation()
                try persist()
            } catch {
                session.phase = .needsAttention
                session.error = error.localizedDescription
                record("Stopped for attention", error.localizedDescription)
                saveOrReport()
            }
            busy = false
        }
    }

    private func record(_ title: String, _ detail: String) {
        session.events.append(.init(title: title, detail: detail))
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: directory.appendingPathComponent("session.json"), options: .atomic)
        try data.write(to: storage.appendingPathComponent("current.json"), options: .atomic)
    }

    private func saveOrReport() {
        do { try persist() } catch { session.error = "Session could not be saved: \(error.localizedDescription)" }
    }
}
