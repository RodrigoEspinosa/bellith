import AppKit
import ApplicationServices
import SwiftUI

@MainActor
struct LogicTransportOperations {
    var inspect: () async throws -> LogicTransportSnapshot
    var perform: (LogicTransportAction, LogicTransportSnapshot) async throws -> LogicTransportSnapshot
    var performTrack: (LogicTrackControlRequest, LogicTransportSnapshot) async throws -> LogicTransportSnapshot = {
        try await LogicTransportAdapter.performTrack($0, expected: $1)
    }
    static let live = Self(inspect: { try await LogicTransportAdapter.inspect() },
                           perform: { try await LogicTransportAdapter.perform($0, expected: $1) })
}

@MainActor
final class LogicTransportModel: ObservableObject {
    @Published private(set) var snapshot: LogicTransportSnapshot?
    private var operationTask: Task<Void, Never>?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var result: String?
    @Published var companionProvider: CreativePlannerProvider = .codex
    @Published var companionGoal = "Help me plan the next steps for this Logic project."
    @Published private(set) var reviewedProposal: LogicTransportProposal?
    @Published private(set) var lastAttempt: LogicTransportAttempt?
    @Published private(set) var lastTrackAttempt: LogicTrackControlAttempt?
    @Published private(set) var reviewedTrackRequest: LogicTrackControlRequest?
    @Published private(set) var reviewedTrackProposal: LogicTrackControlProposal?
    @Published private(set) var trackReviewRequest: UUID?
    let trackControlsQualified: Bool
    var requiresRecoveryReview: Bool {
        lastAttempt?.requiresInspection == true || lastTrackAttempt?.requiresInspection == true
    }
    @Published private(set) var proposalReviewRequest: CreativeReviewRequest?
    @Published private(set) var trackProposalReviewRequest: CreativeReviewRequest?
    func requestTrackProposalReview(_ id: UUID?) { trackProposalReviewRequest = CreativeReviewRequest(proposalID: id) }
    @Published private(set) var companionReviewRequest: UUID?
    func requestProposalReview(_ id: UUID?) { proposalReviewRequest = CreativeReviewRequest(proposalID: id) }
    func requestCompanionReview() {
        guard !busy, snapshot != nil else { return }
        guard operationsEnabled else { companionReviewRequest = UUID(); return }
        snapshot = nil
        reviewedProposal = nil
        reviewedTrackRequest = nil
        reviewedTrackProposal = nil
        trackReviewRequest = nil
        result = nil
        companionReviewRequest = nil
        work { try await self.operations.inspect() } completion: {
            self.companionReviewRequest = UUID()
        }
    }
    func dismissProposalReview() { proposalReviewRequest = nil }
    func dismissTrackProposalReview() { trackProposalReviewRequest = nil }
    func dismissTrackReview() { trackReviewRequest = nil }
    func dismissCompanionReview() { companionReviewRequest = nil }
    let operationsEnabled: Bool
    let inbox: LogicTransportInbox
    private let operations: LogicTransportOperations

    init(operationsEnabled: Bool = true, file: URL = LogicTransportInbox.defaultFile, snapshot: LogicTransportSnapshot? = nil,
         operations: LogicTransportOperations = .live, trackControlsQualified: Bool = false) {
        self.operationsEnabled = operationsEnabled
        self.inbox = LogicTransportInbox(file: file)
        self.snapshot = snapshot
        self.operations = operations
        self.trackControlsQualified = trackControlsQualified
        do { lastAttempt = try inbox.readAttempt() }
        catch { self.error = "The previous playback receipt could not be read. Inspect Logic before continuing." }
        do { lastTrackAttempt = try inbox.readTrackAttempt() }
        catch { self.error = "The previous track-control receipt could not be read. Inspect Logic before continuing." }
    }

    func proposals() throws -> [LogicTransportProposal] { try inbox.list() }
    func trackProposals() throws -> [LogicTrackControlProposal] { try inbox.listTrackProposals() }

    func loadTrackProposal(_ expected: LogicTrackControlProposal) -> Bool {
        guard !busy else { return false }
        do {
            guard try trackProposals().filter({ $0.id == expected.id }) == [expected] else {
                throw LogicTransportError.message("The track proposal changed after preview. Refresh and review it again.")
            }
            try expected.validate(for: snapshot)
            reviewedTrackRequest = expected.request
            reviewedTrackProposal = expected
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func reviewInterruptedState() {
        guard !busy, let snapshot, var attempt = lastAttempt else { return }
        do {
            try attempt.reviewCurrentState(snapshot)
            try inbox.saveAttempt(attempt)
            lastAttempt = attempt
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func reviewInterruptedTrackState() {
        guard !busy, let snapshot, var attempt = lastTrackAttempt else { return }
        do {
            try attempt.reviewCurrentState(snapshot)
            try inbox.saveTrackAttempt(attempt)
            lastTrackAttempt = attempt
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func loadProposal(_ expected: LogicTransportProposal) -> Bool {
        guard !busy else { return false }
        do {
            guard try proposals().filter({ $0.id == expected.id }) == [expected] else {
                throw LogicTransportError.message("The proposal changed after preview. Refresh and review it again.")
            }
            try expected.validate(for: snapshot)
            reviewedProposal = expected
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func inspect() {
        guard operationsEnabled, !busy else { return }
        snapshot = nil
        reviewedProposal = nil
        reviewedTrackRequest = nil
        reviewedTrackProposal = nil
        result = nil
        work { try await self.operations.inspect() }
    }

    func apply(_ action: LogicTransportAction) {
        guard operationsEnabled, !busy, let expected = snapshot, !expected.recording else { return }
        guard !requiresRecoveryReview else {
            error = "Review and acknowledge the inspected current state before submitting another Logic action."
            return
        }
        if let proposal = reviewedProposal, proposal.action == action {
            do { try proposal.validate(for: expected) }
            catch { self.error = error.localizedDescription; return }
        }
        snapshot = nil
        let attempt = LogicTransportAttempt(action: action, expected: expected, proposalID: reviewedProposal?.action == action ? reviewedProposal?.id : nil)
        reviewedProposal = nil
        result = nil
        work {
            self.lastAttempt = attempt
            try self.inbox.saveAttempt(attempt)
            do {
                let observed = try await self.operations.perform(action, expected)
                try Task.checkCancellation()
                try action.validateAcknowledgement(expected: expected, observed: observed)
                var acknowledged = attempt
                acknowledged.phase = .acknowledged
                acknowledged.observed = observed
                try self.inbox.saveAttempt(acknowledged)
                self.lastAttempt = acknowledged
                self.result = observed.playing ? "Logic confirmed playback is running." : "Logic confirmed playback is stopped."
                return observed
            } catch {
                var failed = attempt
                failed.phase = .needsAttention
                failed.error = self.operationError(error)
                self.lastAttempt = failed
                try? self.inbox.saveAttempt(failed)
                throw error
            }
        }
    }

    /// Internal until native review UI and host qualification are complete. Never resumes automatically.
    func applyTrack(_ request: LogicTrackControlRequest) {
        guard operationsEnabled, !busy, let expected = snapshot else { return }
        guard !requiresRecoveryReview else {
            error = "Review and acknowledge the inspected current state before submitting another Logic action."
            return
        }
        do { try request.validate(expected: expected, observed: expected) }
        catch { self.error = error.localizedDescription; return }
        snapshot = nil
        reviewedProposal = nil
        result = nil
        var attempt = LogicTrackControlAttempt(request: request, expected: expected)
        if reviewedTrackProposal?.request == request { attempt.proposal = reviewedTrackProposal }
        reviewedTrackProposal = nil
        reviewedTrackRequest = nil
        work {
            self.lastTrackAttempt = attempt
            try self.inbox.saveTrackAttempt(attempt)
            do {
                let observed = try await self.operations.performTrack(request, expected)
                try Task.checkCancellation()
                try request.validateAcknowledgement(expected: expected, observed: observed)
                var receipt = attempt
                receipt.phase = .acknowledged
                receipt.observed = observed
                try self.inbox.saveTrackAttempt(receipt)
                self.lastTrackAttempt = receipt
                return observed
            } catch {
                var receipt = attempt
                receipt.phase = .needsAttention
                receipt.error = self.operationError(error)
                self.lastTrackAttempt = receipt
                try? self.inbox.saveTrackAttempt(receipt)
                throw error
            }
        }
    }

    func reviewTrack(_ request: LogicTrackControlRequest) {
        guard !busy, let snapshot else { return }
        do {
            try request.validate(expected: snapshot, observed: snapshot)
            reviewedTrackRequest = request
            if reviewedTrackProposal?.request != request { reviewedTrackProposal = nil }
            trackReviewRequest = UUID()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func applyReviewedTrack() -> Bool {
        guard trackControlsQualified, operationsEnabled, !busy, !requiresRecoveryReview,
              let request = reviewedTrackRequest, let snapshot else { return false }
        do { try request.validate(expected: snapshot, observed: snapshot) }
        catch { self.error = error.localizedDescription; return false }
        reviewedTrackRequest = nil
        applyTrack(request)
        return true
    }

    func cancelOperation() {
        guard busy else { return }
        operationTask?.cancel()
    }

    private func operationError(_ error: Error) -> String {
        error is CancellationError
            ? "Operation cancelled. A submitted host action cannot be undone; inspect Logic before retrying."
            : error.localizedDescription
    }

    private func work(_ operation: @escaping @MainActor () async throws -> LogicTransportSnapshot,
                      completion: @escaping @MainActor () -> Void = {}) {
        busy = true
        error = nil
        operationTask = Task {
            defer { busy = false; operationTask = nil }
            do {
                try inbox.save(nil)
                try Task.checkCancellation()
                let observed = try await operation()
                try Task.checkCancellation()
                try inbox.save(observed)
                snapshot = observed
                completion()
            } catch { result = nil; self.error = operationError(error) }
        }
    }
}

struct LogicTransportView: View {
    @ObservedObject var model: LogicTransportModel
    var startCompanion: (CreativeCompanionLaunch) -> Bool = { _ in false }
    @State private var action: LogicTransportAction = .play
    @State private var reviewingProposals = false
    @State private var reviewingCompanion = false
    @State private var reviewingTrack = false
    @State private var reviewingTrackProposals = false
    @State private var accessibilityAvailable = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Logic project", systemImage: "waveform").font(.title2)
                    Text("Inspect your saved project to give the companion context. Review its playback or track proposals here; apply playback separately after checking the requested action.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !accessibilityAvailable {
                        GroupBox("Set up Logic access") {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "hand.raised").font(.title2)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Enable Bellith in System Settings → Privacy & Security → Accessibility. Then return here and inspect your saved Logic project.")
                                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    Button("Open Accessibility Settings") {
                                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }.disabled(!model.operationsEnabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }
                    }
                    if let snapshot = model.snapshot {
                        GroupBox("Observed project") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(snapshot.windowTitle).font(.headline)
                                Text(snapshot.documentURL.path).font(.caption).textSelection(.enabled)
                                Label(snapshot.recording ? "Recording · controls blocked" : (snapshot.playing ? "Playing" : "Stopped"),
                                    systemImage: snapshot.recording ? "record.circle" : (snapshot.playing ? "play.circle" : "stop.circle"))
                                Text("Inspected " + snapshot.inspectedAt.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary)
                                if let tracks = snapshot.exposedTracks {
                                    Text("Exposed track headers · partial context").font(.caption.bold())
                                    ForEach(tracks) { track in
                                        Text("\(track.number). \(track.name)" + (track.selected == true ? " · selected" : "") + (track.muted == true ? " · muted" : "") + (track.soloed == true ? " · solo" : ""))
                                            .font(.caption).textSelection(.enabled)
                                        Menu("Review track control…") {
                                            Button("Mute") { review(track, control: .mute, enabled: true, snapshot: snapshot) }
                                            Button("Unmute") { review(track, control: .mute, enabled: false, snapshot: snapshot) }
                                            Divider()
                                            Button("Solo") { review(track, control: .solo, enabled: true, snapshot: snapshot) }
                                            Button("Unsolo") { review(track, control: .solo, enabled: false, snapshot: snapshot) }
                                        }.disabled(model.busy || snapshot.recording)
                                            .accessibilityLabel("Review controls for track \(track.number), \(track.name)")
                                    }
                                } else { Text("Track headers were not captured.").font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange).textSelection(.enabled)
                    }
                    if let result = model.result { Label(result, systemImage: "checkmark.circle") }
                    if let request = model.reviewedTrackRequest {
                        GroupBox("Prepared track request") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(request.trackNumber). \(request.trackName) · \(request.control.rawValue) \(request.enabled ? "on" : "off")")
                                    .font(.caption).textSelection(.enabled)
                                if let proposal = model.reviewedTrackProposal {
                                    Text(proposal.reason).font(.caption).textSelection(.enabled)
                                }
                                Button("Review track request…") { model.reviewTrack(request) }.disabled(model.busy)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }
                    }
                    if let attempt = model.lastTrackAttempt, attempt.requiresInspection {
                        Label("Track \(attempt.request.trackNumber) · \(attempt.request.trackName): previous \(attempt.request.control.rawValue) request has no verified completion. Check Logic and inspect again. Bellith will not retry automatically.", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        Button("Acknowledge inspected track state", action: model.reviewInterruptedTrackState)
                            .disabled(model.busy || model.snapshot == nil || model.snapshot?.id == attempt.expected.id || model.snapshot?.recording == true)
                    } else if model.lastTrackAttempt?.phase == .reviewed {
                        Text("You reviewed the inspected track state. The earlier track action’s outcome remains unverified; it was not retried.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let attempt = model.lastAttempt, attempt.requiresInspection {
                        Label("Previous \(attempt.action.label.lowercased()) has no verified completion. Check Logic and inspect again; Bellith will not retry it automatically.", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        Button("Acknowledge inspected current state", action: model.reviewInterruptedState)
                            .disabled(model.busy || model.snapshot == nil || model.snapshot?.id == attempt.expected.id || model.snapshot?.recording == true)
                    } else if model.lastAttempt?.phase == .reviewed {
                        Text("You reviewed the inspected current state. The earlier action’s outcome remains unverified; it was not retried.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let proposal = model.reviewedProposal, proposal.action == action {
                        GroupBox("CLI proposal · awaiting your action") {
                            Text(proposal.reason).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(6)
                        }
                    }
                    Text("Playback actions are available; mute/solo requests can be reviewed, but track Apply is not enabled yet. Recording, region edits, plug-ins, and sound analysis are not supported. Open a single Tracks window with English transport controls visible.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(model.busy ? "Working…" : "Inspect Logic", action: model.inspect)
                    .disabled(model.busy || !model.operationsEnabled).keyboardShortcut("i", modifiers: .command)
                if model.busy {
                    Button("Cancel operation", action: model.cancelOperation)
                }
                Button("Playback proposals…") { model.requestProposalReview(nil) }
                    .disabled(model.busy || model.snapshot == nil)
                Button("AI companion…", action: model.requestCompanionReview)
                    .disabled(model.busy || model.snapshot == nil)
                Button("Track proposals…") { model.requestTrackProposalReview(nil) }
                    .disabled(model.busy || model.snapshot == nil)
                Spacer()
            }
            HStack {
                Picker("Action", selection: $action) {
                    ForEach(LogicTransportAction.allCases) { Text($0.label).tag($0) }
                }.labelsHidden().fixedSize().disabled(model.busy)
                Spacer()
                Button("Apply playback action") { model.apply(action) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || !model.operationsEnabled || model.requiresRecoveryReview || model.snapshot == nil || model.snapshot?.recording == true)
            }
        }.padding(24).frame(minWidth: 560, idealWidth: 600, minHeight: 440)
            .onAppear { accessibilityAvailable = AXIsProcessTrusted() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                accessibilityAvailable = AXIsProcessTrusted()
            }
            .sheet(isPresented: $reviewingProposals, onDismiss: model.dismissProposalReview) { LogicProposalReview(model: model) }
            .sheet(isPresented: $reviewingTrack, onDismiss: model.dismissTrackReview) { LogicTrackControlReview(model: model) }
            .sheet(isPresented: $reviewingTrackProposals, onDismiss: model.dismissTrackProposalReview) { LogicTrackProposalReview(model: model) }
            .sheet(isPresented: $reviewingCompanion, onDismiss: model.dismissCompanionReview) {
                if let snapshot = model.snapshot {
                    CreativeCompanionReview(root: snapshot.documentURL, title: snapshot.windowTitle, selected: nil,
                        logicObservation: snapshot, companionLaunchEnabled: model.operationsEnabled, startCompanion: startCompanion,
                        companionProvider: $model.companionProvider, companionGoal: $model.companionGoal)
                }
            }
            .onChange(of: model.proposalReviewRequest, initial: true) { _, request in if request != nil { reviewingProposals = true } }
            .onChange(of: model.trackProposalReviewRequest, initial: true) { _, request in if request != nil { reviewingTrackProposals = true } }
            .onChange(of: model.companionReviewRequest, initial: true) { _, request in if request != nil { reviewingCompanion = true } }
            .onChange(of: model.reviewedProposal) { _, proposal in if let proposal { action = proposal.action } }
            .onChange(of: model.trackReviewRequest, initial: true) { _, request in if request != nil { reviewingTrack = true } }
    }

    private func review(_ track: LogicTrackObservation, control: LogicTrackControlRequest.Control, enabled: Bool, snapshot: LogicTransportSnapshot) {
        model.reviewTrack(.init(observationID: snapshot.id, trackNumber: track.number, trackName: track.name, control: control, enabled: enabled))
    }
}

private struct LogicTrackProposalReview: View {
    @ObservedObject var model: LogicTransportModel
    @Environment(\.dismiss) private var dismiss
    @State private var proposals: [LogicTrackControlProposal] = []
    @State private var selectedID: UUID?
    @State private var error: String?
    private var selected: LogicTrackControlProposal? { proposals.first { $0.id == selectedID } }
    private var issue: String? {
        guard let selected else { return "Select a track proposal." }
        do { try selected.validate(for: model.snapshot); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Logic track proposals").font(.title2)
            Text("Loading prepares a request for separate review. It never changes Logic. Track execution remains unavailable pending live qualification.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(selection: $selectedID) {
                ForEach(proposals) { proposal in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(proposal.request.trackNumber). \(proposal.request.trackName) · \(proposal.request.control.rawValue) \(proposal.request.enabled ? "on" : "off")")
                        Text(proposal.reason).font(.caption).lineLimit(3)
                    }.tag(proposal.id)
                }
            }.frame(height: 240)
            if let selected { ScrollView { Text(selected.reason).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 120) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.orange) }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Refresh", action: refresh)
                Spacer()
                Button("Load for separate review") {
                    if let selected, model.loadTrackProposal(selected) { dismiss() }
                    else { error = model.error }
                }.disabled(issue != nil || model.busy)
            }
        }.padding(24).frame(width: 600).onAppear(perform: refresh)
            .onChange(of: model.trackProposalReviewRequest) { _, _ in refresh() }
    }
    private func refresh() {
        do {
            proposals = try model.trackProposals()
            if let requested = model.trackProposalReviewRequest?.proposalID {
                selectedID = proposals.first { $0.id == requested }?.id
                error = selectedID == nil ? "The requested track proposal is no longer available. Inspect and request a fresh proposal." : nil
            } else { selectedID = proposals.first?.id; error = nil }
        }
        catch { proposals = []; selectedID = nil; self.error = error.localizedDescription }
    }
}

private struct LogicTrackControlReview: View {
    @ObservedObject var model: LogicTransportModel
    @Environment(\.dismiss) private var dismiss
    private var issue: String? {
        guard let request = model.reviewedTrackRequest, let snapshot = model.snapshot else { return "Inspect Logic and review this track again." }
        do { try request.validate(expected: snapshot, observed: snapshot); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Logic track control").font(.title2)
            if let request = model.reviewedTrackRequest, let snapshot = model.snapshot {
                Text(snapshot.documentURL.path).font(.caption).textSelection(.enabled)
                Text("\(request.trackNumber). \(request.trackName)").font(.headline).textSelection(.enabled)
                let track = snapshot.exposedTracks?.first { $0.number == request.trackNumber }
                let current = request.control == .mute ? track?.muted : track?.soloed
                Text("\(request.control.rawValue.capitalized): \(current.map { $0 ? "on" : "off" } ?? "unknown") → \(request.enabled ? "on" : "off")")
                if let proposal = model.reviewedTrackProposal {
                    ScrollView { Text(proposal.reason).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 120)
                    Text("Proposal " + proposal.id.uuidString).font(.caption).textSelection(.enabled)
                }
                Text("Only this named track control is requested. Bellith rechecks the project, recording, playback, and exposed track states, and requires feedback after the action. This is a project change; no audio quality judgement is implied.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let issue { Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
            if !model.trackControlsQualified {
                Label("Apply is unavailable while live Logic track-control qualification is incomplete. Reviewing does not change Logic.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply reviewed track change") { if model.applyReviewedTrack() { dismiss() } }
                    .disabled(issue != nil || model.busy || !model.operationsEnabled || !model.trackControlsQualified)
            }
        }.padding(24).frame(width: 560)
    }
}

private struct LogicProposalReview: View {
    @ObservedObject var model: LogicTransportModel
    @Environment(\.dismiss) private var dismiss
    @State private var proposals: [LogicTransportProposal] = []
    @State private var selectedID: UUID?
    @State private var error: String?
    private var selected: LogicTransportProposal? { proposals.first { $0.id == selectedID } }
    private var issue: String? {
        guard let selected else { return "Select a proposal." }
        do { try selected.validate(for: model.snapshot); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Logic playback proposals").font(.title2)
            Text("Loading prepares a playback action for review. Apply it separately in the main panel. No Logic control is pressed here.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(selection: $selectedID) {
                ForEach(proposals) { proposal in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(proposal.action.label).font(.headline)
                        Text(proposal.reason).lineLimit(3)
                        Text(proposal.submittedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                    }.tag(proposal.id)
                }
            }.frame(height: 240)
            if let selected { ScrollView { Text(selected.reason).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 140) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.orange) }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Refresh", action: refresh)
                Spacer()
                Button("Load for review") {
                    if let selected, model.loadProposal(selected) { dismiss() }
                    else { error = model.error }
                }.disabled(issue != nil || model.busy).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 600).onAppear(perform: refresh)
            .onChange(of: model.proposalReviewRequest) { _, _ in refresh() }
    }

    private func refresh() {
        do {
            proposals = try model.proposals()
            if let requested = model.proposalReviewRequest?.proposalID {
                selectedID = proposals.first(where: { $0.id == requested })?.id
                error = selectedID == nil ? "The requested proposal is no longer available. Inspect and request a fresh proposal." : nil
            } else { selectedID = proposals.first?.id; error = nil }
        }
        catch { proposals = []; selectedID = nil; self.error = error.localizedDescription }
    }
}

@MainActor
final class LogicTransportWindowController: NSWindowController {
    let model = LogicTransportModel()
    init(startCompanion: @escaping (CreativeCompanionLaunch) -> Bool = { _ in false }) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 630, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Bellith — Logic Playback"
        window.minSize = NSSize(width: 600, height: 500)
        window.contentView = NSHostingView(rootView: LogicTransportView(model: model, startCompanion: startCompanion))
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
}
