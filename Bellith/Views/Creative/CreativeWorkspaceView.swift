import AppKit
import AVKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

final class CreativeWorkspaceModel: ObservableObject {
    @Published var assets = CreativeAsset.examples
    @Published var selection: String? = CreativeAsset.examples.first?.id
    @Published var projectName = "After hours"
    @Published var root: URL?
    @Published var filter: CreativeAsset.Kind?
    @Published var query = ""
    @Published var busy = false
    @Published var status = "Sample project · Open a folder to work with your own media"
    @Published var error: String?
    @Published var reviewingCompanion = false
    @Published var companionProvider: CreativePlannerProvider = .codex
    @Published var companionGoal = "Help me plan the next steps for this creative project."
    @Published var reviewingDelivery = false
    @Published var delivery: URL?
    @Published var searchRequest = 0
    @Published private(set) var recentProjects: [CreativeRecentProject]
    private let history: CreativeProjectHistory

    init(defaults: UserDefaults = .standard) {
        history = CreativeProjectHistory(defaults: defaults)
        recentProjects = history.read()
    }

    func clearRecentProjects() { history.clear(); recentProjects = [] }

    var isSample: Bool { root == nil }
    var visibleAssets: [CreativeAsset] {
        assets.filter { (filter == nil || $0.kind == filter) && (query.isEmpty || $0.relativePath.localizedCaseInsensitiveContains(query)) }
    }
    var selected: CreativeAsset? { assets.first { $0.id == selection } }

    func clearFilters() {
        filter = nil
        query = ""
        selection = assets.first?.id
    }

    func openFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder]
        panel.prompt = "Open project"
        panel.message = "Choose a folder of audio, video, or artwork. Bellith reads your media in place."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openProject(url)
        }
    }

    func openProject(_ url: URL) {
        guard !busy, url.isFileURL else { return }
        busy = true
        error = nil
        status = "Reading project…"
        Task { @MainActor in
            do {
                let found = try await Task.detached(priority: .userInitiated) { try CreativeProjectFiles.scan(url) }.value
                assets = found
                root = url
                projectName = url.lastPathComponent
                filter = nil
                query = ""
                selection = found.first?.id
                delivery = nil
                status = "\(found.count) media files · Originals stay in place"
                recentProjects = history.remember(url)
            } catch {
                self.error = error.localizedDescription
                status = "Could not open folder"
            }
            busy = false
        }
    }

    func exportDelivery() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder]
        panel.canCreateDirectories = true
        panel.prompt = "Create delivery"
        panel.message = "A new delivery folder will contain copies of all \(assets.count) project media files and a manifest."
        reviewingDelivery = false
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            self?.createDelivery(at: destination)
        }
    }

    private func createDelivery(at destination: URL) {
        busy = true
        status = "Copying delivery…"
        let snapshot = assets
        Task { @MainActor in
            do {
                delivery = try await Task.detached(priority: .userInitiated) {
                    try CreativeProjectFiles.deliver(snapshot, to: destination)
                }.value
                status = "Delivery ready · \(snapshot.count) files copied"
            } catch {
                self.error = error.localizedDescription
                status = "Delivery failed · Originals unchanged"
            }
            busy = false
        }
    }
}

/// Library + detail prototype. Uses Bellith's existing palette and compact frame,
/// with standard SwiftUI controls for selection, search, playback, and keyboard access.
struct CreativeWorkspaceView: View {
    @ObservedObject var model: CreativeWorkspaceModel
    @FocusState private var searchFocused: Bool
    var openTerminal: () -> Void
    var startCompanion: (CreativeCompanionLaunch) -> Bool
    var companionLaunchEnabled = true
    var embeddedInStudio = false
    private var accent: Color { embeddedInStudio ? .accentColor : Color(nsColor: RebrandTokens.Color.copperGlow) }
    private var surface: Color { Color(nsColor: embeddedInStudio ? .controlBackgroundColor : RebrandTokens.Color.paneBg) }

    var body: some View {
        VStack(spacing: 0) {
            if !embeddedInStudio {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").foregroundStyle(accent)
                Text("BELLITH").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(3)
                Text("/  Creative workspace").foregroundStyle(.secondary)
                Spacer()
                Text(model.isSample ? "SAMPLE" : "LOCAL PROJECT").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 4).background(accent.opacity(0.13), in: Capsule())
                Button(action: model.openFolder) { Label("Open folder", systemImage: "folder.badge.plus") }
                    .disabled(model.busy).keyboardShortcut("o")
            }
            .padding(.horizontal, 22).frame(height: 54)
            Divider()
            }
            HStack(spacing: 0) {
                if !embeddedInStudio {
                    sidebar.frame(width: 202)
                    Divider()
                }
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    if embeddedInStudio { libraryControls }
                    HStack(spacing: 12) {
                        metric("PROJECT MEDIA", value: "\(model.assets.count)", symbol: "square.stack.3d.up")
                        metric("AUDIO", value: "\(model.assets.filter { $0.kind == .audio }.count)", symbol: "waveform")
                        metric("VIDEO + ART", value: "\(model.assets.filter { $0.kind != .audio }.count)", symbol: "film")
                    }
                    HStack(spacing: 0) {
                        library.frame(minWidth: 250, idealWidth: 340, maxWidth: .infinity)
                        Divider()
                        inspector.frame(minWidth: 250, idealWidth: 310, maxWidth: .infinity)
                    }
                    .background(surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.09)))
                    deliveryStrip
                    if embeddedInStudio {
                        Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(24)
            }
            if !embeddedInStudio {
            Divider()
            HStack(spacing: 8) {
                if model.busy { ProgressView().controlSize(.mini) } else {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(accent)
                }
                Text(model.status).lineLimit(1)
                Spacer()
                Label("On your Mac", systemImage: "internaldrive")
            }
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            .padding(.horizontal, 20).frame(height: 30)
            }
        }
        .foregroundStyle(embeddedInStudio ? Color.primary : Color(nsColor: RebrandTokens.Color.fg))
        .background(Color(nsColor: embeddedInStudio ? .windowBackgroundColor : RebrandTokens.Color.windowBg))
        .tint(embeddedInStudio ? nil : accent)
        .frame(minWidth: embeddedInStudio ? 0 : 900, minHeight: embeddedInStudio ? 0 : 620)
        .sheet(isPresented: $model.reviewingCompanion) { companionReview }
        .sheet(isPresented: $model.reviewingDelivery) { deliveryReview }
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of: model.filter) { _, _ in model.selection = model.visibleAssets.first?.id }
        .onChange(of: model.searchRequest) { _, _ in searchFocused = true }
        .onChange(of: model.query) { _, _ in
            if !model.visibleAssets.contains(where: { $0.id == model.selection }) { model.selection = model.visibleAssets.first?.id }
        }
    }

    private var libraryControls: some View {
        HStack(spacing: 12) {
            Picker("Media type", selection: $model.filter) {
                Text("All Media").tag(Optional<CreativeAsset.Kind>.none)
                ForEach(CreativeAsset.Kind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(Optional(kind))
                }
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            if !model.recentProjects.isEmpty {
                Menu("Recent Folders") {
                    ForEach(model.recentProjects) { project in
                        Button(project.name) { model.openProject(project.url) }
                    }
                    Divider()
                    Button("Clear recent list", action: model.clearRecentProjects)
                }.disabled(model.busy)
            }
            Button("Open Folder…", systemImage: "folder.badge.plus", action: model.openFolder)
                .disabled(model.busy).help("Choose a project folder (⌘O)")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        eyebrow("YOUR STUDIO")
                        HStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.up.fill").foregroundStyle(accent)
                                .frame(width: 32, height: 36).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.projectName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(model.isSample ? "Sample project" : "Local project").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        eyebrow("LIBRARY").padding(.bottom, 6)
                        navigation("All media", symbol: "square.grid.2x2", kind: nil)
                        ForEach(CreativeAsset.Kind.allCases, id: \.self) { kind in
                            navigation(kind.rawValue, symbol: kind.symbol, kind: kind)
                        }
                    }
                    if !model.recentProjects.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            eyebrow("RECENT PROJECTS")
                            ForEach(model.recentProjects) { project in
                                Button { model.openProject(project.url) } label: {
                                    Label(project.name, systemImage: "folder").lineLimit(1)
                                }.buttonStyle(.plain).disabled(model.busy)
                                    .help(project.url.path).accessibilityLabel("Open recent project " + project.name)
                            }
                            Button("Clear recent list", action: model.clearRecentProjects)
                                .font(.caption).foregroundStyle(.secondary).buttonStyle(.plain)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "sparkle").foregroundStyle(accent)
                Text("A little less admin.\nMore room to create.")
                    .font(.system(size: 13, weight: .medium)).lineSpacing(4)
                Text("Gather your media. Take a listen. Get it ready to share.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }
            Divider()
            Button { model.reviewingCompanion = true } label: { Label("AI companion…", systemImage: "sparkles") }
                .disabled(model.isSample || model.busy)
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .help("Review project context and prepare Codex or Claude")
            Button(action: openTerminal) { Label("Open terminal", systemImage: "terminal") }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 11))
        }.padding(20)
    }

    private var heading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                if !embeddedInStudio { eyebrow(model.isSample ? "A SPACE FOR YOUR NEXT RELEASE" : "YOUR CREATIVE PROJECT") }
                Text(model.projectName).font(embeddedInStudio ? .largeTitle.bold() : .system(size: 30, weight: .semibold)).lineLimit(1)
                Text(model.isSample ? "The music, the visuals, and everything in between." : "Preview your media and prepare a clean handoff.")
                    .font(embeddedInStudio ? .title3 : .system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if !embeddedInStudio {
                Image(systemName: "waveform.circle").font(.system(size: 45, weight: .ultraLight)).foregroundStyle(accent)
            }
        }
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                eyebrow(title)
                Text(value).font(.system(size: 23, weight: .medium, design: .rounded))
            }
            Spacer()
            Image(systemName: symbol).font(.system(size: 19, weight: .light)).foregroundStyle(accent)
        }.padding(15).frame(maxWidth: .infinity)
            .background(surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.07)))
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.filter?.rawValue ?? "All media").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(model.visibleAssets.count)").foregroundStyle(.secondary)
            }.padding(16)
            TextField("Search media", text: $model.query)
                .focused($searchFocused)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 14).padding(.bottom, 10)
                .accessibilityLabel("Search project media")
            if model.visibleAssets.isEmpty {
                ContentUnavailableView {
                    Label(model.assets.isEmpty ? "No supported media in this folder" : "No matching media",
                          systemImage: model.assets.isEmpty ? "folder" : "magnifyingglass")
                } description: {
                    Text(model.assets.isEmpty
                        ? "You can still plan this project with your companion, or choose a folder with audio, video, or artwork."
                        : "Clear the search and filters to see all \(model.assets.count) project files.")
                } actions: {
                    if model.assets.isEmpty {
                        Button("Start project companion…") { model.reviewingCompanion = true }
                            .disabled(model.isSample || model.busy || !companionLaunchEnabled)
                        Button("Open another folder…", action: model.openFolder).disabled(model.busy)
                    } else {
                        Button("Show all media", action: model.clearFilters).disabled(model.busy)
                    }
                }.frame(maxHeight: .infinity)
            } else {
                List(selection: $model.selection) {
                    ForEach(model.visibleAssets) { asset in
                        HStack(spacing: 11) {
                            Image(systemName: asset.kind.symbol).foregroundStyle(accent)
                                .frame(width: 30, height: 34).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(asset.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(asset.relativePath).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 5).tag(asset.id)
                    }
                }.listStyle(.inset).scrollContentBackground(.hidden)
            }
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                eyebrow("PREVIEW")
                if let asset = model.selected {
                    CreativeMediaPreview(asset: asset, accent: accent).id(asset.id)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(asset.name).font(.system(size: 16, weight: .semibold)).textSelection(.enabled)
                        Text(asset.kind.rawValue + " · " + (asset.url?.pathExtension.uppercased() ?? "Sample media"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Divider()
                    detail("Source", model.isSample ? "Illustrative example" : "Original file")
                    if asset.url != nil {
                        detail("Size", ByteCountFormatter.string(fromByteCount: asset.bytes, countStyle: .file))
                        Button("Show in Finder") {
                            if let url = asset.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        Button("Open in default app") {
                            if let url = asset.url { NSWorkspace.shared.open(url) }
                        }
                    } else {
                        Text("Open your own project folder to play audio, watch video, and inspect artwork here.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    }
                } else {
                    ContentUnavailableView("Select a file", systemImage: "play.rectangle", description: Text("Your preview will appear here."))
                }
            }.padding(20)
        }
    }

    private var deliveryStrip: some View {
        HStack(spacing: 14) {
            Image(systemName: model.delivery == nil ? "shippingbox" : "checkmark.circle")
                .font(.system(size: 24, weight: .light)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.delivery == nil ? "Ready for the handoff?" : "Your delivery is ready")
                    .font(.system(size: 13, weight: .semibold))
                Text("Original media + a file manifest, in one tidy folder.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if let url = model.delivery {
                Button("Show delivery") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Button("Prepare delivery…") { model.reviewingDelivery = true }
                .buttonStyle(.borderedProminent).disabled(model.busy || model.isSample || model.assets.isEmpty)
                .help(model.isSample ? "Open a media folder to prepare a delivery" : "Review all project media before copying")
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }.padding(17).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var companionReview: some View {
        if let root = model.root {
            CreativeCompanionReview(root: root, title: model.projectName, selected: model.selected,
                companionLaunchEnabled: companionLaunchEnabled, startCompanion: startCompanion,
                companionProvider: $model.companionProvider, companionGoal: $model.companionGoal)
        }
    }

    private var deliveryReview: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Prepare delivery", systemImage: "shippingbox").font(.title2)
            Text("Copy all \(model.assets.count) media files from \(model.projectName) into a new delivery folder.")
            Text("Folder structure and original formats are preserved. A JSON manifest lists every file. Search and category filters do not affect this package.")
                .foregroundStyle(.secondary)
            detail("Total size", ByteCountFormatter.string(fromByteCount: model.assets.reduce(0) { $0 + $1.bytes }, countStyle: .file))
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.assets) { Text($0.relativePath).font(.system(size: 11, design: .monospaced)) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 150)
            HStack {
                Button("Cancel") { model.reviewingDelivery = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose destination…", action: model.exportDelivery).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 470)
    }

    private func navigation(_ title: String, symbol: String, kind: CreativeAsset.Kind?) -> some View {
        Button { model.filter = kind } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text("\(model.assets.filter { kind == nil || $0.kind == kind }.count)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }.font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 9)
                .background(model.filter == kind ? accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(model.filter == kind ? [.isSelected] : [])
    }

    @ViewBuilder private func eyebrow(_ title: String) -> some View {
        if embeddedInStudio {
            Text(title.localizedCapitalized).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        } else {
            Text(title).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.2).foregroundStyle(.secondary)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }.font(.system(size: 11))
    }
}

private struct CreativeMediaPreview: View {
    let asset: CreativeAsset
    let accent: Color
    @State private var player: AVPlayer?
    @State private var image: NSImage?
    @State private var playbackError: String?

    var body: some View {
        VStack(spacing: 10) {
            if let player {
                VideoPlayer(player: player).frame(height: 170)
                Text("Use the playback controls to preview").font(.system(size: 10)).foregroundStyle(.secondary)
            } else if let image {
                Image(nsImage: image).resizable().scaledToFit().frame(height: 170)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(spacing: 12) {
                        Image(systemName: asset.kind.symbol).font(.system(size: 48, weight: .ultraLight))
                        Text(asset.url == nil ? "SAMPLE · \(asset.kind.rawValue.uppercased())" : (playbackError == nil ? "Loading preview…" : "Preview unavailable"))
                            .font(.system(size: 9, design: .monospaced)).tracking(2)
                    }.foregroundStyle(accent)
                }.frame(height: 170)
            }
            if let playbackError { Text(playbackError).font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: asset.id) {
            guard let url = asset.url else { return }
            if asset.kind == .image {
                let thumbnail = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1000,
                    ] as CFDictionary)
                }.value
                guard !Task.isCancelled else { return }
                image = thumbnail.map { NSImage(cgImage: $0, size: .zero) }
                if image == nil { playbackError = "This image could not be previewed. Try opening it in its default app." }
            } else {
                do {
                    let media = AVURLAsset(url: url)
                    guard try await media.load(.isPlayable) else {
                        playbackError = "This format cannot be played here. Try opening it in its default app."
                        return
                    }
                    guard !Task.isCancelled else { return }
                    player = AVPlayer(playerItem: AVPlayerItem(asset: media))
                } catch { playbackError = error.localizedDescription }
            }
        }
        .onDisappear { player?.pause(); player = nil }
    }
}

final class CreativeWorkspaceWindowController: NSWindowController {
    let model = CreativeWorkspaceModel()

    init(openTerminal: @escaping () -> Void, startCompanion: @escaping (CreativeCompanionLaunch) -> Bool) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Bellith — Creative Workspace"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 920, height: 690)
        window.contentView = NSHostingView(rootView: CreativeWorkspaceView(model: model, openTerminal: openTerminal, startCompanion: startCompanion))
        window.setFrameAutosaveName("CreativeWorkspace")
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
