import AppKit
import SwiftUI

struct ResolveHarnessView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: ResolveHarnessModel
    @State private var reviewingProposals = false
    @State private var reviewingCompanion = false
    @State private var companionProvider: CreativePlannerProvider = .codex
    @State private var companionGoal = ""
    @State private var clipSearch = ""
    @State private var selectedClipsOnly = false
    var embeddedInStudio = false
    var startCompanion: (CreativeCompanionLaunch) -> Bool = { _ in false }
    var openMedia: () -> Void
    var openTerminal: () -> Void
    private var accent: Color {
        embeddedInStudio ? .accentColor : (colorScheme == .dark ? Color(nsColor: RebrandTokens.Color.copperGlow) : Color(red: 0.48, green: 0.24, blue: 0.17))
    }
    private var surface: Color { Color(nsColor: embeddedInStudio ? .controlBackgroundColor : RebrandTokens.Color.paneBg) }

    var body: some View {
        HStack(spacing: 0) {
            if !embeddedInStudio {
                sidebar.frame(width: 210)
                Divider()
            }
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                HSplitView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if !model.accessibilityAvailable { connection }
                            goalEditor
                            if model.accessibilityAvailable { connection }
                            if let error = model.session.error {
                                Label(error, systemImage: "exclamationmark.circle")
                                    .font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
                            }
                            if let source = model.session.source { timeline(source) }
                            if let plan = model.session.plan { planReview(plan) }
                            activity
                        }.padding(24)
                    }.frame(minWidth: 400)
                    inspector.frame(minWidth: 235, idealWidth: 280, maxWidth: 360)
                }
                Divider()
                footer
            }
        }
        .frame(minWidth: embeddedInStudio ? 700 : 930, minHeight: embeddedInStudio ? 0 : 680)
        .background(Color(nsColor: embeddedInStudio ? .windowBackgroundColor : RebrandTokens.Color.windowBg))
        .foregroundStyle(embeddedInStudio ? Color.primary : Color(nsColor: RebrandTokens.Color.fg))
        .tint(accent)
        .sheet(isPresented: $reviewingProposals, onDismiss: model.dismissProposalReview) { ResolveProposalReview(model: model) }
        .sheet(isPresented: $reviewingCompanion, onDismiss: model.dismissCompanionReview) {
            CreativeCompanionReview(root: model.directory, title: model.session.source?.projectName ?? "Resolve goal session", selected: nil,
                resolveSession: model.session, companionLaunchEnabled: model.hostOperationsEnabled, startCompanion: startCompanion,
                companionProvider: $companionProvider, companionGoal: $companionGoal)
        }
        .onChange(of: model.companionReviewRequest, initial: true) { _, request in
            if request != nil { companionProvider = model.provider; companionGoal = model.session.goal; reviewingCompanion = true }
        }
        .onChange(of: model.proposalReviewRequest, initial: true) { _, request in if request != nil { reviewingProposals = true } }
        .onChange(of: model.session.id) { _, _ in clipSearch = ""; selectedClipsOnly = false }
        .onAppear { model.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermissions() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.path").foregroundStyle(accent)
                Text("BELLITH").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(2)
            }.padding(.top, 12)
            VStack(alignment: .leading, spacing: 9) {
                eyebrow("CREATIVE TOOLS")
                Label("DaVinci Resolve", systemImage: "film.stack")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                Text("Goal sessions").font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 12)
            }
            VStack(alignment: .leading, spacing: 8) {
                eyebrow("CURRENT SESSION")
                Text(model.session.source?.projectName ?? "Connect your project")
                    .font(.system(size: 12, weight: .medium)).lineLimit(2)
                Text(model.session.phase.label).font(.system(size: 11)).foregroundStyle(.secondary)
                Button("New session", systemImage: "plus", action: model.newSession).disabled(model.busy)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "scope").font(.title2).foregroundStyle(accent)
                Text("You set the direction.")
                    .font(.system(size: 13, weight: .medium))
                Text("A goal, a visible plan, and an editable result in your creative tools.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }
            Divider()
            Button("Media library", systemImage: "square.stack", action: openMedia).buttonStyle(.plain)
            Button("Terminal", systemImage: "terminal", action: openTerminal).buttonStyle(.plain)
            Button("AI companion…", systemImage: "sparkles", action: model.requestCompanionReview)
                .disabled(model.busy || model.session.source == nil)
        }.font(.system(size: 12)).padding(20)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("An editing session with a goal").font(.system(size: 20, weight: .semibold))
                Text("DaVinci Resolve  /  \(model.session.source?.timelineName ?? "No timeline inspected")")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if model.busy { ProgressView().controlSize(.small) }
            if model.busy {
                Button(model.pauseRequested ? "Pausing…" : "Pause", action: model.pause).disabled(model.pauseRequested)
            }
            Text(model.session.phase.label).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(accent.opacity(0.12), in: Capsule())
        }.padding(24).fixedSize(horizontal: false, vertical: true)
    }

    private var goalEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("01 / DIRECTION")
            Text("What should we work toward?").font(.system(size: 18, weight: .medium))
            TextEditor(text: Binding(get: { model.session.goal }, set: model.updateGoal))
                .font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(10).frame(height: 90)
                .background(surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.15)))
                .disabled(model.busy || model.session.working != nil)
                .accessibilityLabel("Editing goal")
            Text("Tool set: create a working copy, remove named whole clips while preserving gaps, or add notes at explicit frame offsets. Example: “Make a copy and remove the clip named Camera test.”")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            HStack {
                Button("Inspect Resolve", systemImage: "viewfinder", action: model.inspect)
                    .disabled(!model.canInspect).help("Enable Bellith in Accessibility settings, then open a timeline in Resolve.").keyboardShortcut("i", modifiers: [.command, .shift])
                Picker("Planner", selection: $model.provider) {
                    ForEach(CreativePlannerProvider.allCases) { Text($0.rawValue).tag($0) }
                }.fixedSize().disabled(model.busy)
                Button("Plan with \(model.provider.rawValue)", systemImage: "sparkle", action: model.planWithCLI)
                    .disabled(!model.hostOperationsEnabled || model.busy || model.provider.executable == nil || model.session.source == nil || model.session.working != nil || model.session.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Menu("More") {
                    Button("Prepare a copy-only plan", action: model.copyOnlyPlan)
                        .disabled(model.session.source == nil || model.session.working != nil)
                    Button("Review CLI proposals…", action: showProposals)
                        .disabled(model.session.source == nil || model.session.working != nil)
                    Button("Show session files", action: model.revealSession)
                }.fixedSize().disabled(model.busy)
            }
            Text("Planning sends your goal and timeline metadata, including clip names, frame positions, and existing marker text, to \(model.provider.rawValue) using your existing CLI login. Media files and screen images stay on your Mac.")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
        }
    }

    private func showProposals() { model.requestProposalReview(nil) }

    private var connection: some View {
        HStack(spacing: 12) {
            Image(systemName: model.accessibilityAvailable ? "checkmark.shield" : "hand.raised")
                .foregroundStyle(accent).font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.accessibilityAvailable ? "Accessibility enabled" : "Set up Resolve access")
                    .font(.system(size: 12, weight: .semibold))
                if !model.accessibilityAvailable {
                    Text("Enable Bellith in System Settings → Privacy & Security → Accessibility, then return here to inspect your timeline.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("Resolve \(model.adapter.installedVersion) · Lua Console · \(model.provider.executable != nil ? "\(model.provider.rawValue) installed" : "\(model.provider.rawValue) not found")")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.accessibilityAvailable {
                Button("Enable Accessibility", action: model.adapter.requestAccessibility).disabled(!model.hostOperationsEnabled)
            } else {
                Button("Open Resolve", action: model.adapter.openResolve).disabled(!model.hostOperationsEnabled)
            }
        }.padding(14).background(surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func timeline(_ snapshot: ResolveSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("02 / OBSERVED CONTEXT")
            HStack {
                Label(snapshot.timelineName, systemImage: "rectangle.stack").font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(snapshot.clips.count) items · \(snapshot.frameRate) fps").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("Source: \(snapshot.projectName). Every edit is made on a separate working timeline.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func planReview(_ plan: ResolveEditPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("03 / REVIEWABLE PLAN")
            Text(plan.summary).font(.system(size: 13)).textSelection(.enabled)
            Label("Duplicate and verify the original timeline", systemImage: "square.on.square")
                .font(.system(size: 12))
            if let source = model.session.source, !source.clips.isEmpty, plan.markerNotes.isEmpty {
                DisclosureGroup("\(plan.removeClipKeys.count) whole items selected for removal") {
                    let selectedKeys = Set(plan.removeClipKeys)
                    let query = clipSearch.trimmingCharacters(in: .whitespacesAndNewlines)
                    let visibleClips = source.clips.enumerated().filter { _, clip in
                        (!selectedClipsOnly || selectedKeys.contains(clip.key)) &&
                        (query.isEmpty || "\(clip.name) \(clip.kind) \(clip.track) \(clip.key)".localizedStandardContains(query))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Find a clip by name, kind, track, or key", text: $clipSearch)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("Search timeline clips")
                        Toggle("Selected only", isOn: $selectedClipsOnly).toggleStyle(.checkbox)
                        Text("Showing \(visibleClips.count) of \(source.clips.count) items · \(plan.removeClipKeys.count) total removals. Filters do not change the plan.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if visibleClips.isEmpty { Text("No clips match these filters.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.top, 8)
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(visibleClips, id: \.offset) { _, clip in
                            Toggle(isOn: Binding(get: { model.session.plan?.removeClipKeys.contains(clip.key) == true }, set: { _ in model.toggleRemoval(clip.key) })) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(clip.name).font(.system(size: 12))
                                    Text("\(clip.kind) \(clip.track) · frames \(Int(clip.startFrame))–\(Int(clip.endFrame))")
                                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                    if let start = clip.sourceStartFrame, let end = clip.sourceEndFrame {
                                        Text("Source frames \(String(format: "%.0f", start))–\(String(format: "%.0f", end)) · \(clip.enabled.map { $0 ? "enabled" : "disabled" } ?? "enabled state unavailable")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(clip.key).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }.toggleStyle(.checkbox).disabled(model.busy || model.session.phase != .review)
                        }
                    }.padding(.top, 8)
                }.font(.system(size: 12))
            }
            ForEach(Array(plan.markerNotes.enumerated()), id: \.offset) { _, marker in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blue marker · offset \(String(format: "%.0f", marker.frame)) frames · \(marker.name)").font(.system(size: 12, weight: .medium))
                    Text(marker.note).font(.system(size: 12)).textSelection(.enabled)
                }
            }
            Label("Check remaining clip positions and preserve the source", systemImage: "checkmark.shield")
                .font(.system(size: 12))
            HStack {
                if model.busy {
                    Button(model.pauseRequested ? "Pausing at checkpoint…" : "Pause after this step", action: model.pause)
                        .disabled(model.pauseRequested)
                } else if model.session.phase == .readyForReview {
                    Button("Review in Resolve", action: model.adapter.openResolve).disabled(!model.hostOperationsEnabled)
                    Button("Accept reviewed result", action: model.acceptReview).buttonStyle(.borderedProminent)
                } else if model.session.phase == .accepted {
                    Label("Review accepted", systemImage: "checkmark.circle").foregroundStyle(accent)
                } else {
                    Button(model.session.working == nil ? "Run reviewed plan" : "Resume reviewed plan", action: model.runReviewedPlan)
                        .buttonStyle(.borderedProminent).disabled(!model.canRun)
                }
            }
        }.padding(16).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow("ACTIVITY & EVIDENCE")
            if model.session.events.isEmpty {
                Text("Each tool action and verification result will appear here.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(model.session.events.reversed()) { event in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(accent).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(event.title).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(event.date, style: .time).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Text(event.detail).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                eyebrow("RESOLVE CONTEXT")
                Image(systemName: "film.stack").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(accent)
                Text(model.session.working?.timelineName ?? model.session.source?.timelineName ?? "Your timeline, in context")
                    .font(.system(size: 18, weight: .medium)).textSelection(.enabled)
                if let observed = model.session.working ?? model.session.source {
                    Text(observed.projectName).font(.system(size: 12)).foregroundStyle(.secondary)
                    Divider()
                    stat("Timeline items", "\(observed.clips.count)")
                    stat("Frame rate", observed.frameRate)
                    stat("Resolve", observed.version)
                    stat("Working copy", model.session.working == nil ? "Not created" : "Recorded")
                    Text("This is the last verified structural snapshot. Inspect again after making changes in Resolve.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                } else {
                    Text("Open a project and timeline in Resolve, then inspect it. Bellith reads its structure through the Lua Console.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Label("Source kept intact", systemImage: "lock")
                    Label("Pause at checkpoints", systemImage: "pause.circle")
                    Label("Session saved locally", systemImage: "internaldrive")
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Structural verification cannot judge pacing, continuity, or sound. Playback review is part of finishing the goal.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                Button("Open Resolve", action: model.adapter.openResolve).disabled(!model.hostOperationsEnabled)
            }.padding(22)
        }.background(surface)
    }

    private var footer: some View {
        HStack {
            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(accent)
            Text(model.busy ? "Keep Resolve focused while an action is running" : "Ready when you are")
            Spacer()
            Text("Session \(model.session.id.uuidString.prefix(8).lowercased())")
        }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 22).frame(height: 32)
    }

    private func eyebrow(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.1).foregroundStyle(.secondary)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }.font(.system(size: 11))
    }
}

final class ResolveHarnessWindowController: NSWindowController, NSWindowDelegate {
    let model: ResolveHarnessModel

    @MainActor
    init(openMedia: @escaping () -> Void, openTerminal: @escaping () -> Void, startCompanion: @escaping (CreativeCompanionLaunch) -> Bool = { _ in false }) {
        model = ResolveHarnessModel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Bellith — Resolve Goal Session"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 950, height: 710)
        window.contentView = NSHostingView(rootView: ResolveHarnessView(model: model, startCompanion: startCompanion, openMedia: openMedia, openTerminal: openTerminal))
        window.setFrameAutosaveName("ResolveGoalSession")
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @MainActor
    func windowWillClose(_ notification: Notification) { model.pause() }
}

private struct ResolveProposalReview: View {
    @ObservedObject var model: ResolveHarnessModel
    @Environment(\.dismiss) private var dismiss
    @State private var proposals: [ResolvePlanProposal] = []
    @State private var selectedProposalID: UUID?
    @State private var proposalError: String?

    private func refresh() {
        do {
            proposals = try model.cliProposals()
            if let requested = model.proposalReviewRequest?.proposalID {
                selectedProposalID = proposals.first(where: { $0.id == requested })?.id
                proposalError = selectedProposalID == nil ? "The requested proposal is unavailable in this session. Inspect and request a fresh proposal." : nil
            } else { selectedProposalID = proposals.first?.id; proposalError = nil }
        } catch { proposals = []; proposalError = error.localizedDescription }
    }

    private var selectedProposal: ResolvePlanProposal? { proposals.first { $0.id == selectedProposalID } }
    private var selectedProposalIssue: String? {
        guard let selectedProposal else { return "Select a proposal." }
        do { try selectedProposal.validate(for: model.session); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CLI plan proposals").font(.title2)
            Text("Choose a proposal to load into the plan review. Your current plan stays in place until you choose a replacement. No Resolve command is sent here.")
                .font(.caption).foregroundStyle(.secondary)
            HSplitView {
                List(selection: $selectedProposalID) {
                    ForEach(proposals) { proposal in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(proposal.plan.summary).lineLimit(3)
                            Text(proposal.submittedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                        }.tag(proposal.id)
                    }
                }.frame(minWidth: 210, idealWidth: 240)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let selectedProposal {
                            Text(selectedProposal.plan.summary).font(.headline).textSelection(.enabled)
                            Text(selectedProposal.goal).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            Text("\(selectedProposal.plan.removeClipKeys.count) whole-clip removals · \(selectedProposal.plan.markerNotes.count) timeline notes")
                                .font(.caption)
                            if let source = model.session.source {
                                ForEach(source.clips.filter { selectedProposal.plan.removeClipKeys.contains($0.key) }) { clip in
                                    Text("Remove \(clip.name) · \(clip.kind) track \(clip.track)").font(.caption)
                                }
                            }
                            ForEach(Array(selectedProposal.plan.markerNotes.enumerated()), id: \.offset) { _, marker in
                                Text("Offset \(String(format: "%.0f", marker.frame)): \(marker.name)\n\(marker.note)")
                                    .font(.caption).textSelection(.enabled)
                            }
                            if let issue = selectedProposalIssue {
                                Label(issue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                            }
                        } else {
                            ContentUnavailableView("No proposal selected", systemImage: "doc.text", description: Text("Ask your CLI companion to submit a supported Resolve plan for this session."))
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minWidth: 320)
            }.frame(height: 330)
            if let proposalError { Text(proposalError).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Refresh", action: refresh)
                Spacer()
                Button(model.session.plan == nil ? "Load for plan review" : "Replace current plan for review") {
                    if let id = selectedProposalID, model.reviewCLIProposal(id: id, expected: selectedProposal) { dismiss() }
                    else { proposalError = model.session.error }
                }.disabled(selectedProposalIssue != nil || model.busy).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 700).onAppear(perform: refresh)
            .onChange(of: model.proposalReviewRequest) { _, _ in refresh() }
    }

}
