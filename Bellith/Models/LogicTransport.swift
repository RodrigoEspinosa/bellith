import Foundation

/// Contract for future reviewed track controls; not exposed as an executable MCP operation yet.
struct LogicTrackControlRequest: Codable, Equatable {
    enum Control: String, Codable { case mute, solo }
    let observationID: UUID
    let trackNumber: Int
    let trackName: String
    let control: Control
    let enabled: Bool

    func validate(expected: LogicTransportSnapshot, observed: LogicTransportSnapshot) throws {
        guard expected.id == observationID, expected.processID == observed.processID,
              expected.documentURL == observed.documentURL, !expected.recording, !observed.recording,
              expected.playing == observed.playing,
              expected.exposedTracks == observed.exposedTracks,
              let before = track(in: expected), let current = track(in: observed),
              value(before) != nil, value(before) == value(current),
              before.muted == current.muted, before.soloed == current.soloed else {
            throw LogicTransportError.message("The reviewed track or transport state changed or is unavailable. Inspect Logic and review again.")
        }
    }

    func validateAcknowledgement(expected: LogicTransportSnapshot, observed: LogicTransportSnapshot) throws {
        guard expected.id == observationID, expected.processID == observed.processID,
              expected.documentURL == observed.documentURL, !expected.recording, !observed.recording,
              expected.playing == observed.playing,
              let before = track(in: expected), let after = track(in: observed), value(before) != nil,
              value(after) == enabled,
              before.selected == after.selected,
              (control == .mute ? before.soloed == after.soloed : before.muted == after.muted),
              let originalTracks = expected.exposedTracks, let currentTracks = observed.exposedTracks,
              originalTracks.count == currentTracks.count,
              originalTracks.filter({ $0.number != trackNumber }) == currentTracks.filter({ $0.number != trackNumber }) else {
            throw LogicTransportError.message("Logic did not confirm the isolated track change. Check its current state before retrying.")
        }
    }

    private func track(in snapshot: LogicTransportSnapshot) -> LogicTrackObservation? {
        let matches = snapshot.exposedTracks?.filter { $0.number == trackNumber } ?? []
        guard matches.count == 1, matches[0].name == trackName else { return nil }
        return matches[0]
    }

    private func value(_ track: LogicTrackObservation) -> Bool? { control == .mute ? track.muted : track.soloed }
}

struct LogicTransportSnapshot: Codable, Equatable, Sendable {
    var id = UUID()
    let processID: Int32
    let documentURL: URL
    let windowTitle: String
    let playing: Bool
    let recording: Bool
    let inspectedAt: Date
    var exposedTracks: [LogicTrackObservation]? = nil
}

struct LogicTrackObservation: Codable, Equatable, Sendable, Identifiable {
    let number: Int
    let name: String
    let selected: Bool?
    let muted: Bool?
    let soloed: Bool?
    var id: Int { number }

    static func identity(description: String) -> (Int, String)? {
        guard description.count <= 1000,
              let range = description.range(of: "^Track [1-9][0-9]* “.+”$", options: .regularExpression),
              range == description.startIndex..<description.endIndex,
              let quote = description.firstIndex(of: "“"),
              let number = Int(description.dropFirst(6).prefix { $0.isNumber }) else { return nil }
        return (number, String(description[description.index(after: quote)..<description.index(before: description.endIndex)]))
    }
}

enum LogicTransportAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case play, stop
    var id: String { rawValue }
    var label: String { self == .play ? "Start playback" : "Stop playback" }

    func validate(expected: LogicTransportSnapshot, observed: LogicTransportSnapshot) throws {
        guard expected.processID == observed.processID, expected.documentURL == observed.documentURL else {
            throw LogicTransportError.message("The Logic project changed. Inspect again before controlling playback.")
        }
        guard !expected.recording, !observed.recording else {
            throw LogicTransportError.message("Logic is recording. Bellith will not interrupt or change a recording.")
        }
        guard expected.playing == observed.playing else {
            throw LogicTransportError.message("Playback changed since inspection. Inspect again before continuing.")
        }
    }

    var requestedPlaying: Bool { self == .play }

    func validateAcknowledgement(expected: LogicTransportSnapshot, observed: LogicTransportSnapshot) throws {
        guard expected.processID == observed.processID, expected.documentURL == observed.documentURL,
              !observed.recording, observed.playing == requestedPlaying else {
            throw LogicTransportError.message("The host result does not confirm the requested playback action. Check Logic before continuing.")
        }
    }

    /// The same Logic control changes its title when playback stops.
    static func recognizesStopControl(title: String, playing: Bool) -> Bool {
        title == "Stop" || (!playing && title == "Go to Beginning")
    }
}

struct LogicTransportProposal: Codable, Equatable, Identifiable {
    var id = UUID()
    var submittedAt = Date()
    let observationID: UUID
    let action: LogicTransportAction
    let reason: String

    func validate(for snapshot: LogicTransportSnapshot?) throws {
        guard let snapshot, snapshot.id == observationID, !snapshot.recording,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 2000 else {
            throw LogicTransportError.message("The proposal does not match a reviewable Logic observation. Inspect again and request a fresh proposal.")
        }
    }
}

struct LogicTransportAttempt: Codable, Equatable, Identifiable {
    enum Phase: String, Codable { case pending, acknowledged, needsAttention, reviewed }
    var id = UUID()
    var startedAt = Date()
    var phase: Phase = .pending
    let action: LogicTransportAction
    let expected: LogicTransportSnapshot
    let proposalID: UUID?
    var observed: LogicTransportSnapshot?
    var error: String?
    var reviewedAt: Date?
    var reviewedSnapshot: LogicTransportSnapshot?

    var requiresInspection: Bool { phase == .pending || phase == .needsAttention }
    var actionOutcomeVerified: Bool { phase == .acknowledged }

    mutating func reviewCurrentState(_ snapshot: LogicTransportSnapshot) throws {
        guard requiresInspection, snapshot.id != expected.id, snapshot.inspectedAt >= startedAt,
              snapshot.documentURL == expected.documentURL, !snapshot.recording else {
            throw LogicTransportError.message("Inspect the same Logic project again, outside recording, before acknowledging its current state.")
        }
        phase = .reviewed
        reviewedAt = Date()
        reviewedSnapshot = snapshot
    }
}

/// Shared by the app and CLI. Queuing never changes the observed host state.
struct LogicTrackControlAttempt: Codable, Equatable, Identifiable {
    var id = UUID()
    var startedAt = Date()
    var phase: LogicTransportAttempt.Phase = .pending
    let request: LogicTrackControlRequest
    let expected: LogicTransportSnapshot
    var proposal: LogicTrackControlProposal? = nil
    var observed: LogicTransportSnapshot?
    var error: String?
    var reviewedAt: Date?
    var reviewedSnapshot: LogicTransportSnapshot?
    var requiresInspection: Bool { phase == .pending || phase == .needsAttention }
    var actionOutcomeVerified: Bool { phase == .acknowledged }

    mutating func reviewCurrentState(_ snapshot: LogicTransportSnapshot) throws {
        let tracks = snapshot.exposedTracks?.filter { $0.number == request.trackNumber } ?? []
        guard requiresInspection, snapshot.id != expected.id, snapshot.inspectedAt >= startedAt,
              snapshot.documentURL == expected.documentURL, !snapshot.recording,
              tracks.count == 1, tracks[0].name == request.trackName,
              (request.control == .mute ? tracks[0].muted : tracks[0].soloed) != nil else {
            throw LogicTransportError.message("Inspect the same Logic project and named track again, outside recording, before acknowledging its current state.")
        }
        phase = .reviewed
        reviewedAt = Date()
        reviewedSnapshot = snapshot
    }
}

struct LogicTrackControlProposal: Codable, Equatable, Identifiable {
    var id = UUID()
    var submittedAt = Date()
    let request: LogicTrackControlRequest
    let reason: String
    func validate(for snapshot: LogicTransportSnapshot?) throws {
        guard let snapshot, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 2000 else {
            throw LogicTransportError.message("Inspect Logic and supply a supported track request with a brief reason.")
        }
        try request.validate(expected: snapshot, observed: snapshot)
    }
}

struct LogicTransportInbox {
    let file: URL
    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bellith/LogicTransport/current.json")
    }
    var proposalsDirectory: URL { file.deletingLastPathComponent().appendingPathComponent("proposals") }
    var attemptFile: URL { file.deletingLastPathComponent().appendingPathComponent("last-attempt.json") }
    var trackAttemptFile: URL { file.deletingLastPathComponent().appendingPathComponent("last-track-attempt.json") }
    var trackProposalsDirectory: URL { file.deletingLastPathComponent().appendingPathComponent("track-proposals") }

    func submitTrack(_ request: LogicTrackControlRequest, reason: String) throws -> LogicTrackControlProposal {
        let saved = try boundedData(file)
        let snapshot = try JSONDecoder().decode(LogicTransportSnapshot?.self, from: saved)
        let proposal = LogicTrackControlProposal(request: request, reason: reason)
        try proposal.validate(for: snapshot)
        try FileManager.default.createDirectory(at: trackProposalsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try boundedData(file) == saved else { throw LogicTransportError.message("Logic observation changed while submitting. Review a fresh request.") }
        try JSONEncoder().encode(proposal).write(to: trackProposalsDirectory.appendingPathComponent(proposal.id.uuidString + ".json"), options: .atomic)
        return proposal
    }

    func listTrackProposals() throws -> [LogicTrackControlProposal] {
        guard FileManager.default.fileExists(atPath: trackProposalsDirectory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: trackProposalsDirectory, includingPropertiesForKeys: nil)
        guard urls.count <= 1000 else { throw LogicTransportError.message("Too many track proposals. Review the inbox files before continuing.") }
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? boundedData(url), let proposal = try? JSONDecoder().decode(LogicTrackControlProposal.self, from: data),
                  url.deletingPathExtension().lastPathComponent == proposal.id.uuidString else { return nil }
            return proposal
        }.sorted { $0.submittedAt > $1.submittedAt }
    }

    func saveTrackAttempt(_ attempt: LogicTrackControlAttempt) throws {
        let directory = file.deletingLastPathComponent().appendingPathComponent("track-attempts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(attempt)
        try data.write(to: directory.appendingPathComponent(attempt.id.uuidString + ".json"), options: .atomic)
        try data.write(to: trackAttemptFile, options: .atomic)
    }

    func readTrackAttempt() throws -> LogicTrackControlAttempt? {
        guard FileManager.default.fileExists(atPath: trackAttemptFile.path) else { return nil }
        return try JSONDecoder().decode(LogicTrackControlAttempt.self, from: boundedData(trackAttemptFile))
    }

    func saveAttempt(_ attempt: LogicTransportAttempt) throws {
        let directory = file.deletingLastPathComponent().appendingPathComponent("attempts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(attempt)
        try data.write(to: directory.appendingPathComponent(attempt.id.uuidString + ".json"), options: .atomic)
        try data.write(to: attemptFile, options: .atomic)
    }

    func readAttempt() throws -> LogicTransportAttempt? {
        guard FileManager.default.fileExists(atPath: attemptFile.path) else { return nil }
        return try JSONDecoder().decode(LogicTransportAttempt.self, from: boundedData(attemptFile))
    }

    func save(_ snapshot: LogicTransportSnapshot?) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
    }

    func read() throws -> LogicTransportSnapshot? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(LogicTransportSnapshot?.self, from: boundedData(file))
    }

    func submit(observationID: UUID, action: LogicTransportAction, reason: String) throws -> LogicTransportProposal {
        let saved = try boundedData(file)
        let snapshot = try JSONDecoder().decode(LogicTransportSnapshot?.self, from: saved)
        let proposal = LogicTransportProposal(observationID: observationID, action: action, reason: reason)
        try proposal.validate(for: snapshot)
        try FileManager.default.createDirectory(at: proposalsDirectory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        guard try boundedData(file) == saved else {
            throw LogicTransportError.message("Logic observation changed while submitting. Request a fresh proposal.")
        }
        try JSONEncoder().encode(proposal).write(to: proposalsDirectory.appendingPathComponent(proposal.id.uuidString + ".json"), options: .atomic)
        return proposal
    }

    func list() throws -> [LogicTransportProposal] {
        guard FileManager.default.fileExists(atPath: proposalsDirectory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: proposalsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard urls.count <= 1000 else { throw LogicTransportError.message("Too many Logic proposals. Review the inbox files before continuing.") }
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? boundedData(url), let proposal = try? JSONDecoder().decode(LogicTransportProposal.self, from: data),
                  url.deletingPathExtension().lastPathComponent == proposal.id.uuidString else { return nil }
            return proposal
        }.sorted { $0.submittedAt == $1.submittedAt ? $0.id.uuidString < $1.id.uuidString : $0.submittedAt > $1.submittedAt }
    }

    private func boundedData(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 100_000 else {
            throw LogicTransportError.message("Logic evidence file is invalid or exceeds the size limit.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= 100_000 else { throw LogicTransportError.message("Logic evidence file exceeds the size limit.") }
        return data
    }
}

enum LogicTransportError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
