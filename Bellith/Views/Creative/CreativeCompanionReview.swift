import AppKit
import SwiftUI

struct CreativeCompanionReview: View {
    let root: URL
    let title: String
    let selected: CreativeAsset?
    var logicObservation: LogicTransportSnapshot? = nil
    var resolveSession: ResolveGoalSession? = nil
    var companionLaunchEnabled = true
    var startCompanion: (CreativeCompanionLaunch) -> Bool
    @Binding var companionProvider: CreativePlannerProvider
    @Binding var companionGoal: String
    @Environment(\.dismiss) private var dismiss
    @State private var companionCopied = false
    @State private var checkingApps = false
    @State private var creativeApps: [CreativeAppConnection] = []
    @State private var companionError: String?
    @State private var showingApps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Work with your AI companion", systemImage: "sparkles").font(.title2)
                    Text(title).font(.headline)
                    Picker("CLI", selection: $companionProvider) {
                        ForEach(CreativePlannerProvider.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    TextField("What would you like to work toward?", text: $companionGoal, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(3...6)
                        .accessibilityLabel("Companion goal")
                    Text(root.path).font(.caption).textSelection(.enabled)
                    if let resolveSession, let source = resolveSession.source {
                        GroupBox("Saved Resolve goal session") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(source.projectName + " / " + source.timelineName).font(.headline)
                                Text("\(source.clips.count) timeline items · \(source.frameRate) fps · \(resolveSession.phase.label)").font(.caption)
                                Text("Session " + resolveSession.id.uuidString).font(.caption).textSelection(.enabled)
                                Text("This folder contains session evidence. It is not the Resolve project or media. The launch includes session and timeline identities, signatures, and item counts. Full clip names, frame positions, marker text, plans, and checkpoint events are available through the saved-evidence tool; inspect Resolve again before applying a plan.")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let logicObservation {
                        Text("Logic observation · " + logicObservation.inspectedAt.formatted(date: .omitted, time: .standard)).font(.caption)
                        Text("Saved context only. Exposed track headers may be partial; no audio is attached.").font(.caption).foregroundStyle(.secondary)
                        Text(logicObservation.recording ? "Observed: recording" : (logicObservation.playing ? "Observed: playing" : "Observed: stopped")).font(.caption)
                        if let tracks = logicObservation.exposedTracks {
                            ForEach(tracks) { track in
                                Text("\(track.number). \(track.name) · mute \(track.muted.map { $0 ? "on" : "off" } ?? "unknown") · solo \(track.soloed.map { $0 ? "on" : "off" } ?? "unknown")")
                                    .font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        } else { Text("Track headers were not captured.").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let selected {
                        Text("Selected media: " + selected.relativePath).font(.caption).textSelection(.enabled)
                    }
                    GroupBox("Before you start") {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(sharedContextSummary, systemImage: "doc.text")
                            Label("The CLI uses its existing login and integrations. It may read files in this folder and send their contents to \(companionProvider.rawValue).", systemImage: "folder")
                            Label("Starts in read-only / plan mode. Bellith proposals wait for separate native review and approval.", systemImage: "hand.raised")
                        }.font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if companionProvider.executable == nil {
                        Label("Install and sign in to \(companionProvider.rawValue) CLI first.", systemImage: "exclamationmark.circle")
                    }
                    DisclosureGroup("Creative apps on this Mac", isExpanded: $showingApps) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(creativeApps) { app in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name + (app.version.map { " · " + $0 } ?? "")).font(.callout.bold())
                                    Text(app.state.label).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    if let title = app.windowTitle { Text(title).font(.caption).textSelection(.enabled) }
                                }
                            }
                            Button(checkingApps ? "Checking…" : "Check apps") {
                                Task { await refreshCreativeApps() }
                            }.disabled(checkingApps || !companionLaunchEnabled)
                            Text("A local availability check. It does not operate apps or verify editing access, and is not shared with the companion.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(.top, 10)
                    }
                    Text("Start opens an interactive companion terminal. Return to Studio to review supported proposals and their results.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 540)
            if let companionError { Label(companionError, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(companionCopied ? "Command copied" : "Copy launch command") {
                    guard let executable = companionProvider.executable else { return }
                    do {
                        let launch = try CreativeCompanionLaunch.prepare(provider: companionProvider,
                            executable: executable, root: root, goal: companionGoal, selected: selected, logicObservation: logicObservation, resolveSession: resolveSession, bellithCLI: Bundle.main.url(forResource: "bellith", withExtension: nil))
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(launch.command, forType: .string)
                        companionCopied = true
                    } catch { companionError = error.localizedDescription }
                }.disabled(!companionLaunchEnabled || companionProvider.executable == nil || companionGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Start companion") {
                    guard let executable = companionProvider.executable else { return }
                    do {
                        let launch = try CreativeCompanionLaunch.prepare(provider: companionProvider,
                            executable: executable, root: root, goal: companionGoal, selected: selected, logicObservation: logicObservation, resolveSession: resolveSession, bellithCLI: Bundle.main.url(forResource: "bellith", withExtension: nil))
                        guard startCompanion(launch) else {
                            throw HarnessError.message("The companion terminal could not be created. Copy the launch command to retry manually.")
                        }
                        dismiss()
                    } catch { companionError = error.localizedDescription }
                }.disabled(!companionLaunchEnabled || companionProvider.executable == nil || companionGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 590)
            .onChange(of: companionGoal) { _, _ in companionCopied = false }
            .onChange(of: companionProvider) { _, _ in companionCopied = false }
            .onAppear { companionCopied = false }

    }

    private var sharedContextSummary: String {
        if resolveSession != nil {
            return "Your goal and timeline identities are shared. Saved clip names, positions, marker text, plans, and checkpoint events can be fetched through Bellith's evidence tool. Bellith attaches no media files."
        }
        if logicObservation != nil {
            return "Your goal and saved Logic observation are shared, including the project path, playback state, and exposed track names and controls. Saved action receipts can be fetched. Bellith attaches no audio."
        }
        return "Your goal and selected file path are shared. Saved Resolve and Logic project evidence can also be fetched through Bellith's tools. Bellith attaches no media files."
    }

    @MainActor private func refreshCreativeApps() async {
        guard companionLaunchEnabled, !checkingApps else { return }
        checkingApps = true
        defer { checkingApps = false }
        let inspected = await CreativeAppInspector.inspect()
        guard !Task.isCancelled else { return }
        creativeApps = inspected
    }

}
