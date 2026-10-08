import Foundation
@main struct Smoke {
    @MainActor static func main() async throws {
        do {
            try await run()
        } catch {
            fputs(error.localizedDescription + "\n", stderr)
            exit(1)
        }
    }

    @MainActor private static func run() async throws {
        let snapshot = ResolveSnapshot(projectID: "fixture", projectName: "Synthetic fixture", timelineID: "source", timelineName: "Source", startFrame: 0, endFrame: 24, frameRate: "24", product: "Resolve", version: "fixture", clips: [ResolveClip(key: "clip-a", name: "Camera test.wav", kind: "audio", track: 1, startFrame: 0, endFrame: 24)], signature: "fixture", markers: [])
        guard CommandLine.arguments.count >= 3,
              let provider = CreativePlannerProvider.allCases.first(where: {
                  $0.rawValue.lowercased() == CommandLine.arguments[1]
              }) else { throw HarnessError.message("Usage: planner-smoke <codex|claude> <artifact-directory>") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let noteMode = CommandLine.arguments.contains("notes")
        let goal = noteMode ? "Make a copy and add a marker at frame offset 12 named Check audio with note Listen locally." : "Make a copy and remove the clip named Camera test.wav"
        let plan = try await ResolveGoalPlanner().plan(goal: goal, snapshot: snapshot, directory: directory, provider: provider)
        guard plan.blockedReason.isEmpty, noteMode ? (plan.removeClipKeys.isEmpty && plan.markerNotes == [ResolveMarkerNote(frame: 12, name: "Check audio", note: "Listen locally.")]) : plan.removeClipKeys == ["clip-a"] else { throw HarnessError.message("Unexpected removal plan") }
        print("\(provider.rawValue): schema-constrained plan passed")
    }
}
