import AppKit
import SwiftUI

@MainActor
final class StudioModel: ObservableObject {
    enum Destination: String, CaseIterable, Identifiable {
        case home, demo, resolve, logic, media
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: return "Start here"
            case .demo: return "Try the workflow"
            case .resolve: return "DaVinci Resolve"
            case .logic: return "Logic Pro"
            case .media: return "Media library"
            }
        }
        var symbol: String {
            switch self {
            case .home: return "house"
            case .demo: return "play.rectangle"
            case .resolve: return "film.stack"
            case .logic: return "waveform"
            case .media: return "folder"
            }
        }
    }
    @Published var destination: Destination = .home
    @Published private(set) var connections: [CreativeAppConnection] = []
    @Published private(set) var checking = false
    let media: CreativeWorkspaceModel
    let resolve: ResolveHarnessModel
    let logic: LogicTransportModel
    let demo = StudioDemoModel()
    let previewOnly: Bool

    init(previewOnly: Bool = false, storage: URL? = nil, defaults: UserDefaults = .standard) {
        self.previewOnly = previewOnly
        media = CreativeWorkspaceModel(defaults: defaults)
        resolve = ResolveHarnessModel(storage: storage?.appendingPathComponent("Resolve"), hostOperationsEnabled: !previewOnly)
        logic = LogicTransportModel(operationsEnabled: !previewOnly,
            file: storage?.appendingPathComponent("Logic/current.json") ?? LogicTransportInbox.defaultFile)
    }

    func checkApps() {
        guard !checking, !previewOnly else { return }
        checking = true
        Task {
            connections = await CreativeAppInspector.inspect()
            checking = false
        }
    }

    func requestCompanion() {
        switch destination {
        case .resolve: resolve.requestCompanionReview()
        case .logic: logic.requestCompanionReview()
        case .media:
            guard !media.isSample, !media.busy else { return }
            media.reviewingCompanion = true
        case .home, .demo: break
        }
    }
}

/// Entirely in memory. Exercises the same typed plan validation without a CLI or host.
@MainActor
final class StudioDemoModel: ObservableObject {
    enum Phase { case start, proposal, reviewed, result }
    @Published private(set) var phase: Phase = .start
    @Published private(set) var working: ResolveSnapshot?
    @Published private(set) var error: String?
    @Published var removeTestClip = false
    let source = ResolveSnapshot(projectID: "demo-project", projectName: "After hours · Demo",
        timelineID: "demo-original", timelineName: "Assembly", startFrame: 0, endFrame: 1440,
        frameRate: "24", product: "Bellith demonstration", version: "Synthetic",
        clips: [ResolveClip(key: "opening", name: "Opening take", kind: "video", track: 1, startFrame: 0, endFrame: 480),
                ResolveClip(key: "camera-test", name: "Camera test", kind: "video", track: 1, startFrame: 480, endFrame: 720),
                ResolveClip(key: "closing", name: "Closing take", kind: "video", track: 1, startFrame: 720, endFrame: 1440)],
        signature: "demo-original", markers: [])
    @Published private(set) var plan: ResolveEditPlan?

    func prepare() {
        guard phase == .start else { return }
        plan = ResolveEditPlan(summary: removeTestClip
            ? "Create a working copy and remove Camera test. Preserve the gap and all other clips."
            : "Create a working copy and add an opening review note. Keep every clip in place.",
            blockedReason: "", removeClipKeys: removeTestClip ? ["camera-test"] : [],
            markerNotes: removeTestClip ? [] : [.init(frame: 0, name: "Opening review", note: "Watch the opening and decide whether the pacing works.")])
        phase = .proposal
    }

    func review() {
        guard phase == .proposal, let plan else { return }
        do { try plan.validate(against: source); phase = .reviewed }
        catch { self.error = error.localizedDescription }
    }

    func applySimulation() {
        guard phase == .reviewed, let plan else { return }
        do {
            try plan.validate(against: source)
            working = ResolveSnapshot(projectID: source.projectID, projectName: source.projectName,
                timelineID: "demo-working", timelineName: "Bellith · Demo working copy",
                startFrame: source.startFrame, endFrame: source.endFrame, frameRate: source.frameRate,
                product: source.product, version: source.version,
                clips: source.clips.filter { !plan.removeClipKeys.contains($0.key) }, signature: "demo-result",
                markers: plan.markerNotes.map { $0.marker(copyName: "Bellith · Demo working copy") })
            phase = .result
        } catch { self.error = error.localizedDescription }
    }

    func reset() { phase = .start; working = nil; plan = nil; error = nil; removeTestClip = false }
}

struct StudioView: View {
    @ObservedObject var model: StudioModel
    var openTerminal: () -> Void
    var startCompanion: (CreativeCompanionLaunch) -> Bool
    var startCLISetup: (CreativePlannerProvider) -> Bool = { _ in false }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Bellith Studio", systemImage: "waveform.path").font(.headline).padding(.horizontal, 14).padding(.top, 20)
                    Text("Your creative companion").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
                    List(selection: $model.destination) {
                        Section("Get started") {
                            row(.home)
                            row(.demo)
                        }
                        Section("Your work") {
                            row(.resolve)
                            row(.logic)
                            row(.media)
                        }
                    }.listStyle(.sidebar)
                    Divider()
                    Button(action: openTerminal) { Label("Open terminal", systemImage: "terminal").frame(maxWidth: .infinity, alignment: .leading) }
                        .buttonStyle(.plain).padding(14).disabled(model.previewOnly)
                }.frame(width: 220)
                Divider()
                VStack(spacing: 0) {
                    StudioWorkflowBar(studio: model, resolve: model.resolve, logic: model.logic, media: model.media)
                    Group {
                    switch model.destination {
                    case .home: StudioHomeView(model: model, openTerminal: openTerminal, startCLISetup: startCLISetup)
                    case .demo: StudioDemoView(model: model.demo)
                    case .resolve:
                        ResolveHarnessView(model: model.resolve, embeddedInStudio: true,
                            startCompanion: startCompanion, openMedia: { model.destination = .media }, openTerminal: openTerminal)
                    case .logic:
                        LogicTransportView(model: model.logic, startCompanion: startCompanion)
                    case .media:
                        CreativeWorkspaceView(model: model.media, openTerminal: openTerminal,
                            startCompanion: startCompanion, companionLaunchEnabled: !model.previewOnly, embeddedInStudio: true)
                    }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.accentColor)
    }
    private func row(_ destination: StudioModel.Destination) -> some View {
        Label(destination.title, systemImage: destination.symbol).tag(destination)
    }
}

enum StudioResolveGuidance {
    static func nextStep(session: ResolveGoalSession, busy: Bool, accessibilityAvailable: Bool) -> String {
        if busy { return "Working · wait for the checkpoint, or pause the session below." }
        if !accessibilityAvailable { return "1 · Enable Accessibility access below to inspect your Resolve timeline." }
        switch session.phase {
        case .paused:
            return "Paused · review the checkpoint below and inspect the recorded timeline before continuing."
        case .needsAttention, .duplicating, .editing:
            return "Needs review · check Resolve and the saved checkpoint below before continuing. Do not repeat the edit."
        case .readyForReview:
            return "4 · Review playback of the working timeline in Resolve before accepting the result."
        case .accepted:
            return "Result accepted · start a new session for another goal."
        case .draft, .inspecting, .planning, .review:
            if session.source == nil { return "1 · Open a timeline in Resolve, then choose Inspect Resolve below." }
            if session.plan == nil { return "2 · Set your goal, then ask the companion or planner for a proposal." }
            return "3 · Review the exact plan below before running it on a working copy."
        }
    }
}

private struct StudioWorkflowBar: View {
    @ObservedObject var studio: StudioModel
    @ObservedObject var resolve: ResolveHarnessModel
    @ObservedObject var logic: LogicTransportModel
    @ObservedObject var media: CreativeWorkspaceModel
    var body: some View {
        if [.resolve, .logic, .media].contains(studio.destination) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(studio.destination.title).font(.headline)
                        Text(nextStep).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if studio.destination == .resolve {
                        Button("New session", systemImage: "plus", action: resolve.newSession).disabled(resolve.busy)
                    }
                    Button("AI companion…", systemImage: "sparkles", action: studio.requestCompanion)
                        .disabled(!canStartCompanion)
                }.padding(.horizontal, 24).padding(.vertical, 14)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Divider()
            }
        }
    }
    private var canStartCompanion: Bool {
        switch studio.destination {
        case .resolve: return !resolve.busy && resolve.session.source != nil && !studio.previewOnly
        case .logic: return !logic.busy && logic.snapshot != nil && !studio.previewOnly
        case .media: return !media.busy && !media.isSample && !studio.previewOnly
        case .home, .demo: return false
        }
    }
    private var nextStep: String {
        switch studio.destination {
        case .resolve:
            return StudioResolveGuidance.nextStep(session: resolve.session, busy: resolve.busy,
                accessibilityAvailable: resolve.accessibilityAvailable)
        case .logic:
            if logic.busy { return "Working · cancellation cannot undo a host action already submitted." }
            if logic.lastAttempt?.requiresInspection == true || logic.lastTrackAttempt?.requiresInspection == true {
                return "Needs review · inspect Logic and acknowledge its current state below before planning another action."
            }
            if logic.snapshot == nil { return "1 · Open one saved project in Logic, then choose Inspect Logic below." }
            if logic.snapshot?.recording == true { return "Recording · finish recording in Logic, then inspect again before reviewing controls." }
            if logic.reviewedProposal != nil || logic.reviewedTrackRequest != nil { return "3 · Review the prepared request below. Track execution remains unavailable." }
            return "2 · Start a companion with a goal, or choose a playback action below."
        case .media:
            return media.isSample ? "1 · Open a media folder to preview files and start a project companion." : "2 · Select media to preview, then start a companion with your project goal."
        case .home, .demo: return ""
        }
    }
}

private struct StudioHomeView: View {
    @ObservedObject var model: StudioModel
    var openTerminal: () -> Void
    var startCLISetup: (CreativePlannerProvider) -> Bool
    @State private var showingSetup = false
    @State private var setupError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Start a creative session").font(.largeTitle.bold())
                    Text("Choose your workspace. Give your companion a goal. Review what changes.")
                        .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your workspace").font(.headline)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) { workspaces }
                        VStack(spacing: 14) { workspaces }
                    }
                }
                GroupBox {
                    HStack(spacing: 16) {
                        Image(systemName: "play.rectangle").font(.title2).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Want to try it first?").font(.headline)
                            Text("Review a sample edit. No setup or project files needed.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Button("Try demo") { model.destination = .demo }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    DisclosureGroup(isExpanded: $showingSetup) {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("AI companion").font(.headline)
                                ForEach(CreativePlannerProvider.allCases) { provider in
                                    HStack {
                                        Label(provider.rawValue, systemImage: "terminal")
                                        Spacer()
                                        Text(provider.executable == nil ? "Not installed" : "Installed · login not checked")
                                            .font(.callout).foregroundStyle(.secondary)
                                        Button("Sign in") {
                                            setupError = startCLISetup(provider) ? nil : "Could not open the sign-in terminal. Check that the CLI is installed."
                                        }.disabled(model.previewOnly || provider.executable == nil)
                                            .accessibilityLabel("Sign in to " + provider.rawValue)
                                    }
                                }
                                Text("Sign in opens the provider CLI in a terminal. Complete authentication there; Bellith does not collect credentials.")
                                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                if let setupError { Text(setupError).font(.callout).foregroundStyle(.orange) }
                                Button("Open terminal for setup", action: openTerminal).disabled(model.previewOnly)
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Creative apps").font(.headline)
                                Text("Open a saved project in Resolve or Logic, then inspect it from its workspace.")
                                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                ForEach(model.connections) { app in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.name).font(.subheadline.bold())
                                        Text(app.state.label).font(.callout).foregroundStyle(.secondary)
                                    }
                                }
                                Button(model.checking ? "Checking…" : "Check apps", action: model.checkApps)
                                    .disabled(model.checking || model.previewOnly)
                                Text("Checks availability only. Permissions and host controls stay unchanged.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.top, 18).frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        HStack {
                            Label("Setup & connections", systemImage: "slider.horizontal.3").font(.headline)
                            Spacer()
                            Text(providerSummary).font(.callout).foregroundStyle(.secondary)
                        }
                    }.padding(12)
                }
                Label("Live app control is still being tested. Track execution in Logic is not enabled yet.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(32).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var providerSummary: String {
        let installed = CreativePlannerProvider.allCases.filter { $0.executable != nil }.map { $0.rawValue }
        return installed.isEmpty ? "CLI setup needed" : installed.joined(separator: " + ") + " installed"
    }

    @ViewBuilder private var workspaces: some View {
        workflow(.resolve, detail: "Plan an edit on a working copy.", capability: "Clip removals and timeline notes.", action: "Open Resolve")
        workflow(.logic, detail: "Work with your music project.", capability: "Playback and track proposals.", action: "Open Logic")
        workflow(.media, detail: "Explore your project's files.", capability: "Audio, video, artwork and delivery.", action: "Open media")
    }

    private func workflow(_ destination: StudioModel.Destination, detail: String, capability: String, action: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: destination.symbol).font(.system(size: 26)).foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(destination.title).font(.title3.bold())
                    Text(detail).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Text(capability).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                Button(action) { model.destination = destination }
                    .accessibilityLabel("Open " + destination.title + " workspace")
            }.padding(14).frame(minWidth: 225, maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StudioDemoView: View {
    @ObservedObject var model: StudioDemoModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Try the workflow").font(.largeTitle.bold())
                    Spacer()
                    Button("Start over", action: model.reset)
                }
                Label("Demo · synthetic timeline · no host or AI connection", systemImage: "play.rectangle")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Walk through a creative request. The suggestion is a prepared example, and the result is simulated entirely in memory.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                GroupBox("1 · Set a direction") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Keep the originals intact. Make a working copy to review the opening.").font(.headline)
                        Toggle("Remove the Camera test clip instead of adding a review note", isOn: $model.removeTestClip).disabled(model.phase != .start)
                        timeline(model.source, label: "Original timeline")
                        if model.phase == .start {
                            Button("Show example proposal", action: model.prepare).buttonStyle(.borderedProminent)
                        }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let plan = model.plan {
                    GroupBox("2 · Review the suggestion") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(plan.summary).font(.headline).textSelection(.enabled)
                            Text("\(plan.removeClipKeys.count) whole-clip removals · \(plan.markerNotes.count) review notes · a separate working copy")
                                .font(.caption).foregroundStyle(.secondary)
                            if model.phase == .proposal {
                                Text("A proposal is not approval. Review its exact changes before continuing.")
                                Button("Review these changes", action: model.review).buttonStyle(.borderedProminent)
                            } else { Label("Changes reviewed", systemImage: "checkmark.circle").foregroundStyle(.green) }
                            if model.phase == .reviewed {
                                Text("In a live workflow, this is where you explicitly approve a host action. Here it only changes the demo.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Apply to demo working copy", action: model.applySimulation).buttonStyle(.borderedProminent)
                            }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let working = model.working {
                    GroupBox("3 · Check the result") {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Demo result ready · original unchanged", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                            timeline(working, label: "Working copy")
                            ForEach(Array((working.markers ?? []).enumerated()), id: \.offset) { _, marker in
                                Label("\(marker.name) · frame \(Int(marker.frame))", systemImage: "bookmark")
                                Text(marker.note).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("A structural check can verify clip positions and notes. You still decide whether the pacing and sound work by reviewing playback in the host app.")
                                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Text("Next: choose DaVinci Resolve or Logic Pro in the sidebar to inspect your own project.").font(.callout)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let error = model.error { Text(error).foregroundStyle(.orange) }
            }.padding(32).frame(maxWidth: 940, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    private func timeline(_ snapshot: ResolveSnapshot, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.bold())
            ForEach(snapshot.clips) { clip in
                HStack {
                    Label(clip.name, systemImage: "film")
                    Spacer()
                    Text("Frames \(Int(clip.startFrame))–\(Int(clip.endFrame))").font(.caption.monospaced()).foregroundStyle(.secondary)
                }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

@MainActor
final class StudioWindowController: NSWindowController {
    let model: StudioModel
    init(previewOnly: Bool = false, storage: URL? = nil,
         openTerminal: @escaping () -> Void, startCompanion: @escaping (CreativeCompanionLaunch) -> Bool,
         startCLISetup: @escaping (CreativePlannerProvider) -> Bool = { _ in false }) {
        model = StudioModel(previewOnly: previewOnly, storage: storage)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Bellith — Studio"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1140, height: 740)
        let hosting = NSHostingView(rootView: StudioView(model: model, openTerminal: openTerminal, startCompanion: startCompanion, startCLISetup: startCLISetup))
        // The window owns its geometry. A section's ideal size must not resize it.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.setFrameAutosaveName(previewOnly ? "StudioPreview" : "Studio")
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func show(_ destination: StudioModel.Destination) {
        model.destination = destination
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
