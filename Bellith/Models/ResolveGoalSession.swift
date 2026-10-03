import Foundation

struct ResolveClip: Codable, Equatable, Identifiable, Sendable {
    let key: String
    let name: String
    let kind: String
    let track: Int
    let startFrame: Double
    let endFrame: Double
    var enabled: Bool? = nil
    var sourceStartFrame: Double? = nil
    var sourceEndFrame: Double? = nil
    var mediaPoolItemID: String? = nil
    var id: String { key }
}

struct ResolveMarker: Codable, Equatable, Sendable {
    let frame: Double
    let color: String
    let name: String
    let note: String
    let duration: Double
    let customData: String
}

struct ResolveMarkerNote: Codable, Equatable, Sendable {
    let frame: Double
    let name: String
    let note: String

    func marker(copyName: String) -> ResolveMarker {
        ResolveMarker(frame: frame, color: "Blue", name: name, note: note, duration: 1,
                      customData: copyName + ":" + String(format: "%.0f", frame))
    }
}

struct ResolveSnapshot: Codable, Equatable, Sendable {
    let projectID: String
    let projectName: String
    let timelineID: String
    let timelineName: String
    let startFrame: Double
    let endFrame: Double
    let frameRate: String
    let product: String
    let version: String
    let clips: [ResolveClip]
    let signature: String
    var markers: [ResolveMarker]? = nil
}

struct ResolveEditPlan: Codable, Equatable, Sendable {
    var summary: String
    var blockedReason: String
    var removeClipKeys: [String]
    var markerNotes: [ResolveMarkerNote]

    init(summary: String, blockedReason: String, removeClipKeys: [String], markerNotes: [ResolveMarkerNote] = []) {
        self.summary = summary; self.blockedReason = blockedReason
        self.removeClipKeys = removeClipKeys; self.markerNotes = markerNotes
    }

    private enum CodingKeys: String, CodingKey { case summary, blockedReason, removeClipKeys, markerNotes }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        summary = try values.decode(String.self, forKey: .summary)
        blockedReason = try values.decode(String.self, forKey: .blockedReason)
        removeClipKeys = try values.decode([String].self, forKey: .removeClipKeys)
        markerNotes = try values.decodeIfPresent([ResolveMarkerNote].self, forKey: .markerNotes) ?? []
    }

    func validate(against snapshot: ResolveSnapshot) throws {
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HarnessError.message("The plan needs a summary.")
        }
        guard blockedReason.isEmpty else { throw HarnessError.message(blockedReason) }
        guard removeClipKeys.count <= 50, Set(removeClipKeys).count == removeClipKeys.count else {
            throw HarnessError.message("The plan contains too many or repeated removals.")
        }
        guard markerNotes.count <= 20, Set(markerNotes.map(\.frame)).count == markerNotes.count,
              markerNotes.isEmpty || removeClipKeys.isEmpty else {
            throw HarnessError.message("Use up to 20 distinct timeline notes, separately from clip removals.")
        }
        if !markerNotes.isEmpty {
            guard let existing = snapshot.markers else {
                throw HarnessError.message("Inspect Resolve again to capture existing markers before adding notes.")
            }
            let occupied = Set(existing.map(\.frame))
            guard markerNotes.allSatisfy({ $0.frame.isFinite && $0.frame.rounded() == $0.frame && $0.frame >= 0 && $0.frame <= Double(Int32.max)
                && $0.frame < snapshot.endFrame - snapshot.startFrame && !occupied.contains($0.frame)
                && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.name.count <= 120 && $0.note.count <= 2000 }) else {
                throw HarnessError.message("Notes need unique, unoccupied whole-frame offsets within the timeline, a title, and bounded text.")
            }
        }
        let counts = Dictionary(grouping: snapshot.clips, by: \.key)
        guard removeClipKeys.allSatisfy({ counts[$0]?.count == 1 }) else {
            throw HarnessError.message("The plan references a missing or ambiguous clip. Inspect and plan again.")
        }
    }

    static let schema = #"{"type":"object","additionalProperties":false,"required":["summary","blockedReason","removeClipKeys","markerNotes"],"properties":{"summary":{"type":"string"},"blockedReason":{"type":"string"},"removeClipKeys":{"type":"array","items":{"type":"string"}},"markerNotes":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["frame","name","note"],"properties":{"frame":{"type":"number"},"name":{"type":"string"},"note":{"type":"string"}}}}}}"#
}

/// Reconcile an interrupted operation from fresh inspection, never from clip counts alone.
enum ResolveWorkingCopyRecovery {
    enum Result: Equatable { case unchanged, edited }

    private struct Layout: Decodable {
        var keys: [String]
        var tracks: [Int]
        var start: Double
        var finish: Double
        var fps: String
        var markers: [ResolveMarker]?
        var enabledByKey: [String: Bool]?

        init(_ snapshot: ResolveSnapshot) throws {
            self = try JSONDecoder().decode(Self.self, from: Data(snapshot.signature.utf8))
            guard keys.sorted() == snapshot.clips.map(\.key).sorted(), tracks.count == 3,
                  tracks.allSatisfy({ $0 >= 0 }), start == snapshot.startFrame,
                  finish == snapshot.endFrame, fps == snapshot.frameRate, markers == snapshot.markers,
                  (enabledByKey ?? [:]) == Dictionary(snapshot.clips.compactMap { clip in
                      clip.enabled.map { (clip.key, $0) }
                  }, uniquingKeysWith: { first, _ in first }) else {
                throw HarnessError.message("Inspection evidence is inconsistent. Inspect Resolve again before continuing.")
            }
        }
    }

    static func reconcile(source: ResolveSnapshot, observed: ResolveSnapshot,
                          plan: ResolveEditPlan, copyName: String, recordedID: String?) throws -> Result {
        try plan.validate(against: source)
        guard observed.projectID == source.projectID, observed.timelineID != source.timelineID,
              observed.timelineName == copyName,
              recordedID == nil || observed.timelineID == recordedID else {
            throw HarnessError.message("Select the session’s recorded working copy before continuing.")
        }
        let before = try Layout(source)
        let after = try Layout(observed)
        guard before.tracks == after.tracks, before.start == after.start, before.fps == after.fps else {
            throw HarnessError.message("The working copy’s tracks or timeline settings changed. Review it in Resolve before starting a new session.")
        }
        let original = source.clips.sorted { $0.key < $1.key }
        let actual = observed.clips.sorted { $0.key < $1.key }
        if !plan.markerNotes.isEmpty {
            guard actual == original, let originalMarkers = source.markers, let observedMarkers = observed.markers,
                  before.finish == after.finish else {
                throw HarnessError.message("The note working copy’s clip layout changed. Review it in Resolve.")
            }
            let expected = (originalMarkers + plan.markerNotes.map { $0.marker(copyName: copyName) }).sorted { $0.frame < $1.frame }
            if observedMarkers.sorted(by: { $0.frame < $1.frame }) == expected { return .edited }
            if observedMarkers == originalMarkers && observed.signature == source.signature { return .unchanged }
            throw HarnessError.message("Timeline notes are incomplete or changed. Inspect them in Resolve; do not retry blindly.")
        }
        if actual == original {
            guard source.signature == observed.signature else {
                throw HarnessError.message("The working copy’s layout changed. Review it in Resolve before continuing.")
            }
            return plan.removeClipKeys.isEmpty ? .edited : .unchanged
        }
        guard before.markers == after.markers else {
            throw HarnessError.message("Existing timeline markers changed. Review the working copy in Resolve.")
        }
        let removed = Set(plan.removeClipKeys)
        guard !removed.isEmpty, actual == original.filter({ !removed.contains($0.key) }) else {
            throw HarnessError.message("The working copy has unexpected edits. Review it in Resolve before starting a new session.")
        }
        // Removing the last item may legitimately shorten GetEndFrame(). Other layout
        // settings and every surviving clip must still match the reviewed source.
        guard after.finish <= before.finish, actual.isEmpty || after.finish >= after.start else {
            throw HarnessError.message("The working copy’s timeline extent is unexpected. Review it in Resolve.")
        }
        return .edited
    }
}

/// Claude wraps schema output in a result envelope, including API failures on nonzero exit.
enum ResolvePlannerResponse {
    static func claude(_ data: Data) throws -> ResolveEditPlan {
        struct Envelope: Decodable {
            var is_error: Bool?
            var result: String?
            var structured_output: ResolveEditPlan?
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        if envelope.is_error == true {
            let detail = String((envelope.result ?? "No error detail returned.").prefix(800))
            throw HarnessError.message("Claude planning failed: \(detail) No Resolve edits were sent.")
        }
        guard let plan = envelope.structured_output else {
            throw HarnessError.message("Claude returned no structured plan. Check response.json and planner.log in the session folder. No edits were sent.")
        }
        return plan
    }
}

enum HarnessError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

struct ResolveGoalSession: Codable, Identifiable {
    enum Phase: String, Codable {
        case draft, inspecting, planning, review, duplicating, editing, paused, needsAttention, readyForReview, accepted
        var label: String {
            switch self {
            case .draft: return "Set a goal"
            case .inspecting: return "Inspecting Resolve"
            case .planning: return "Planning"
            case .review: return "Review the plan"
            case .duplicating: return "Creating working copy"
            case .editing: return "Applying edits"
            case .paused: return "Paused at checkpoint"
            case .needsAttention: return "Needs attention"
            case .readyForReview: return "Ready for your review"
            case .accepted: return "Review accepted"
            }
        }
    }
    struct Event: Codable, Identifiable {
        var id = UUID()
        var date = Date()
        var title: String
        var detail: String
    }
    var id = UUID()
    var goal = "Create a working copy of the current timeline for a new edit."
    var phase: Phase = .draft
    var source: ResolveSnapshot?
    var working: ResolveSnapshot?
    var plan: ResolveEditPlan?
    var events: [Event] = []
    var error: String?
    var copyName: String { "Bellith - \(id.uuidString)" }

    mutating func recoverAfterLaunch() {
        if [.inspecting, .planning, .duplicating, .editing].contains(phase) {
            phase = .needsAttention
            error = "The last operation was interrupted. Inspect Resolve before taking another action."
        }
    }
}

/// Values become Lua literals; user/model strings can never become executable code.
enum ResolveLuaLiteral {
    static func string(_ text: String) -> String {
        "\"" + text.utf8.map { byte in
            if byte >= 32 && byte <= 126 && byte != 34 && byte != 92 { return String(UnicodeScalar(byte)) }
            return String(format: "\\%03d", Int(byte))
        }.joined() + "\""
    }

    static func object(_ values: [String: String], arrays: [String: [String]] = [:]) -> String {
        let scalar = values.keys.sorted().map { "[\(string($0))]=\(string(values[$0]!))" }
        let lists = arrays.keys.sorted().map { "[\(string($0))]={\(arrays[$0]!.map(string).joined(separator: ","))}" }
        return "{" + (scalar + lists).joined(separator: ",") + "}"
    }
}

/// A CLI proposal is data for native review, never authorization to execute.
struct ResolvePlanProposal: Codable, Identifiable, Equatable {
    var id = UUID()
    var submittedAt = Date()
    let sessionID: UUID
    let goal: String
    let sourceSignature: String
    let plan: ResolveEditPlan

    func validate(for session: ResolveGoalSession) throws {
        guard session.id == sessionID, session.goal == goal, session.working == nil,
              [.draft, .review].contains(session.phase), let source = session.source,
              source.signature == sourceSignature else {
            throw HarnessError.message("The proposal does not match a reviewable session and inspected source. Inspect and request a fresh proposal.")
        }
        guard plan.summary.count <= 4000, plan.blockedReason.count <= 2000 else {
            throw HarnessError.message("The proposal text exceeds the review limit.")
        }
        try plan.validate(against: source)
    }
}
