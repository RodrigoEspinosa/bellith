import AppKit
import GhosttyKit

/// Container that hosts multiple terminal surfaces, a sidebar, and the command palette.
final class TerminalContainerView: NSView {
    private weak var terminalApp: TerminalApp?
    private var surfaces: [(id: UUID, view: TerminalSurfaceView, title: String)] = []
    private(set) var selectedTabIndex: Int = 0
    let sidebar = SidebarView()
    private var commandPalette: CommandPaletteView?
    private(set) var isPaletteVisible = false
    private var isClosingTab = false
    private var edgeTrackingArea: NSTrackingArea?
    init(terminalApp: TerminalApp) {
        self.terminalApp = terminalApp
        super.init(frame: .zero)
        wantsLayer = true
        // Darker than terminal background — the gap between content and window edge
        // creates the "border" effect naturally through contrast
        layer?.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1.0).cgColor

        addSubview(sidebar)
        sidebar.onSelectTab = { [weak self] i in
            self?.selectTab(i)
            self?.sidebar.hide()
        }
        sidebar.onCloseTab = { [weak self] i in self?.closeTab(i) }
        sidebar.onNewTab = { [weak self] in self?.createTab() }

        // Create the initial tab
        createTab()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var activeSurface: TerminalSurfaceView? {
        guard selectedTabIndex < surfaces.count else { return nil }
        return surfaces[selectedTabIndex].view
    }

    // MARK: - Key Interception

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""

        // Cmd+K — command palette
        if mods == .command && key == "k" {
            toggleCommandPalette()
            return true
        }

        // Cmd+B — toggle sidebar
        if mods == .command && key == "b" {
            sidebar.toggle()
            return true
        }

        // Cmd+T — new tab
        if mods == .command && key == "t" {
            createTab()
            return true
        }

        // Cmd+W — close tab
        if mods == .command && key == "w" {
            closeCurrentTab()
            return true
        }

        // Cmd+Shift+] — next tab
        if mods == [.command, .shift] && key == "]" {
            selectTab(selectedTabIndex + 1 < surfaces.count ? selectedTabIndex + 1 : 0)
            return true
        }

        // Cmd+Shift+[ — previous tab
        if mods == [.command, .shift] && key == "[" {
            selectTab(selectedTabIndex > 0 ? selectedTabIndex - 1 : surfaces.count - 1)
            return true
        }

        // Cmd+1-9 — jump to tab
        if mods == .command, let digit = Int(key), digit >= 1 && digit <= 9 {
            let index = min(digit - 1, surfaces.count - 1)
            selectTab(index)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Tab Management

    @discardableResult
    func createTab() -> TerminalSurfaceView? {
        guard let terminalApp else { return nil }

        let surface = TerminalSurfaceView(app: terminalApp)
        let id = UUID()
        surface.onClose = { [weak self, id] processAlive in
            guard let self else { return }
            if let idx = self.surfaces.firstIndex(where: { $0.id == id }) {
                self.closeTab(idx)
            }
        }

        surfaces.append((id: id, view: surface, title: "Terminal"))
        addSubview(surface, positioned: .below, relativeTo: sidebar)

        selectTab(surfaces.count - 1)
        refreshSidebar()
        return surface
    }

    func closeTab(_ index: Int) {
        guard index < surfaces.count, !isClosingTab else { return }
        isClosingTab = true
        defer { isClosingTab = false }

        let entry = surfaces[index]
        entry.view.onClose = nil
        entry.view.removeFromSuperview()
        surfaces.remove(at: index)

        if surfaces.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.window?.close()
            }
            return
        }

        if selectedTabIndex >= surfaces.count {
            selectedTabIndex = surfaces.count - 1
        }

        selectTab(selectedTabIndex)
        refreshSidebar()
    }

    func closeCurrentTab() {
        closeTab(selectedTabIndex)
    }

    func selectTab(_ index: Int) {
        guard index >= 0 && index < surfaces.count else { return }

        if selectedTabIndex < surfaces.count {
            surfaces[selectedTabIndex].view.isHidden = true
        }

        selectedTabIndex = index

        let surface = surfaces[selectedTabIndex].view
        surface.isHidden = false
        surface.frame = contentRect
        surface.wantsLayer = true
        surface.layer?.cornerRadius = contentRadius
        surface.layer?.masksToBounds = true
        window?.makeFirstResponder(surface)

        refreshSidebar()
    }

    func updateTabTitle(_ title: String, for surface: TerminalSurfaceView) {
        if let idx = surfaces.firstIndex(where: { $0.view === surface }) {
            surfaces[idx].title = title
            refreshSidebar()
        }
    }

    private func refreshSidebar() {
        let tabs = surfaces.map { (id: $0.id, title: $0.title) }
        sidebar.update(tabs: tabs, selectedIndex: selectedTabIndex)
    }

    // MARK: - Layout

    private let contentPadding: CGFloat = 4
    private let contentRadius: CGFloat = 8

    private var contentRect: NSRect {
        let p = contentPadding
        return NSRect(
            x: p,
            y: p,
            width: bounds.width - p * 2,
            height: bounds.height - p * 2
        )
    }

    override func layout() {
        super.layout()

        let rect = contentRect

        // Sidebar overlays the left edge of the content area
        sidebar.frame = NSRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: SidebarView.expandedWidth,
            height: rect.height
        )
        sidebar.wantsLayer = true
        sidebar.layer?.cornerRadius = contentRadius
        sidebar.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        sidebar.layer?.masksToBounds = true

        // Active surface fills the content area
        if selectedTabIndex < surfaces.count {
            surfaces[selectedTabIndex].view.frame = rect
        }

        setupEdgeTracking()
    }

    // MARK: - Edge Hover Detection (show sidebar on left edge hover)

    private func setupEdgeTracking() {
        if let existing = edgeTrackingArea {
            removeTrackingArea(existing)
        }
        let edgeRect = NSRect(x: 0, y: 0, width: 4, height: bounds.height)
        edgeTrackingArea = NSTrackingArea(
            rect: edgeRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: ["zone": "edge"]
        )
        addTrackingArea(edgeTrackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        if let info = event.trackingArea?.userInfo as? [String: String],
           info["zone"] == "edge" {
            sidebar.show()
            (window as? TerminalWindow)?.showTrafficLights()
        }
    }

    // MARK: - Command Palette

    func toggleCommandPalette() {
        if isPaletteVisible { hideCommandPalette() } else { showCommandPalette() }
    }

    func showCommandPalette() {
        guard !isPaletteVisible else { return }
        isPaletteVisible = true

        let palette = CommandPaletteView()
        palette.onSubmit = { [weak self] text in
            self?.handleCommand(text)
        }
        palette.onDismiss = { [weak self] in
            self?.isPaletteVisible = false
            self?.commandPalette = nil
            self?.window?.makeFirstResponder(self?.activeSurface)
        }
        commandPalette = palette
        palette.show(in: self)

        (window as? TerminalWindow)?.showTrafficLights()
    }

    func hideCommandPalette() {
        commandPalette?.hide()
    }

    private func handleCommand(_ text: String) {
        NSLog("[Recminal] Command: %@", text)
    }
}
