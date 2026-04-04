import AppKit
import GhosttyKit

/// Container that hosts multiple terminal tabs (each with optional split panes),
/// a sidebar or tab bar, and the command palette.
final class TerminalContainerView: NSView {
    private weak var terminalApp: TerminalApp?

    struct TabEntry {
        let id: UUID
        let splitRoot: SplitPaneView
        var title: String
        var cwd: String?
        /// All surfaces in this tab (including splits).
        var surfaces: [TerminalSurfaceView]
        /// The currently focused surface within this tab.
        weak var focusedSurface: TerminalSurfaceView?
    }

    private var tabs: [TabEntry] = []
    private(set) var selectedTabIndex: Int = 0
    let sidebar = SidebarView()
    let tabBar = TabBarView()
    private var commandPalette: CommandPaletteView?
    private var hud: HUDView?
    private(set) var isPaletteVisible = false
    private var isClosingTab = false
    private var edgeTrackingArea: NSTrackingArea?
    private var themeObserver: NSObjectProtocol?

    init(terminalApp: TerminalApp) {
        self.terminalApp = terminalApp
        super.init(frame: .zero)
        wantsLayer = true
        applyFrameColor()

        // Sidebar
        addSubview(sidebar)
        sidebar.onSelectTab = { [weak self] i in
            self?.selectTab(i)
            self?.sidebar.hide()
        }
        sidebar.onCloseTab = { [weak self] i in self?.closeTab(i) }
        sidebar.onNewTab = { [weak self] in self?.createTab() }
        sidebar.onExpandChanged = { [weak self] _ in self?.animateContentLayout() }

        // Tab bar
        addSubview(tabBar)
        tabBar.onSelectTab = { [weak self] i in self?.selectTab(i) }
        tabBar.onCloseTab = { [weak self] i in self?.closeTab(i) }
        tabBar.onNewTab = { [weak self] in self?.createTab() }

        applyTabMode()

        // Theme change observer
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleThemeChange() }

        createTab()
    }

    deinit {
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Active Surface

    var activeSurface: TerminalSurfaceView? {
        guard selectedTabIndex < tabs.count else { return nil }
        return tabs[selectedTabIndex].focusedSurface ?? tabs[selectedTabIndex].surfaces.first
    }

    // MARK: - Tab Mode

    private var useSidebar: Bool { BellithSettings.shared.tabMode == "sidebar" }

    func applyTabMode() {
        let isSidebar = useSidebar
        sidebar.isHidden = !isSidebar
        tabBar.isHidden = isSidebar
        needsLayout = true
    }

    func toggleTabMode() {
        let s = BellithSettings.shared
        s.tabMode = s.tabMode == "sidebar" ? "tabbar" : "sidebar"
        applyTabMode()
    }

    // MARK: - Key Interception

    private func matches(_ event: NSEvent, action actionId: String) -> Bool {
        guard let shortcut = BellithSettings.shared.shortcut(for: actionId) else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""
        return mods == shortcut.modifierFlags && key == shortcut.key
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""

        if mods == .command && key == "q" { return super.performKeyEquivalent(with: event) }

        if matches(event, action: "commandPalette") { toggleCommandPalette(); return true }
        if matches(event, action: "toggleSidebar") { sidebar.toggle(); return true }
        if matches(event, action: "newTab") { createTab(); return true }
        if matches(event, action: "closeTab") { closeCurrentTab(); return true }
        if matches(event, action: "nextTab") {
            selectTab(selectedTabIndex + 1 < tabs.count ? selectedTabIndex + 1 : 0)
            return true
        }
        if matches(event, action: "prevTab") {
            selectTab(selectedTabIndex > 0 ? selectedTabIndex - 1 : tabs.count - 1)
            return true
        }

        if mods == .command, let digit = Int(key), digit >= 1 && digit <= 9 {
            selectTab(min(digit - 1, tabs.count - 1))
            return true
        }

        if matches(event, action: "copy") {
            if let surface = activeSurface?.surface, ghostty_surface_has_selection(surface) {
                copySelection()
                return true
            }
            return false
        }
        if matches(event, action: "paste") { pasteClipboard(); return true }

        if mods == .command && key == "n" { return false }

        if matches(event, action: "showHUD") { showHUD(); return true }

        if matches(event, action: "splitRight") { splitPane(direction: .vertical); return true }
        if matches(event, action: "splitDown") { splitPane(direction: .horizontal); return true }
        if matches(event, action: "closePane") { closePane(); return true }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Tab Management

    @discardableResult
    func createTab() -> TerminalSurfaceView? {
        guard let terminalApp else { return nil }

        let surface = TerminalSurfaceView(app: terminalApp)
        let id = UUID()
        surface.onClose = { [weak self, id] _ in
            guard let self else { return }
            self.handleSurfaceClosed(id: id, surface: surface)
        }

        let splitRoot = SplitPaneView(content: surface)
        tabs.append(TabEntry(
            id: id, splitRoot: splitRoot, title: "Terminal", cwd: nil,
            surfaces: [surface], focusedSurface: surface
        ))
        addSubview(splitRoot, positioned: .below, relativeTo: sidebar)

        selectTab(tabs.count - 1)
        refreshTabUI()
        return surface
    }

    func closeTab(_ index: Int) {
        guard index < tabs.count, !isClosingTab else { return }
        isClosingTab = true
        defer { isClosingTab = false }

        let entry = tabs[index]
        for s in entry.surfaces { s.onClose = nil }
        entry.splitRoot.removeFromSuperview()
        tabs.remove(at: index)

        if tabs.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.window?.close() }
            return
        }

        if selectedTabIndex >= tabs.count { selectedTabIndex = tabs.count - 1 }
        selectTab(selectedTabIndex)
        refreshTabUI()
    }

    func closeCurrentTab() { closeTab(selectedTabIndex) }

    func selectTab(_ index: Int) {
        guard index >= 0 && index < tabs.count else { return }

        // Hide current tab's split root
        if selectedTabIndex < tabs.count {
            tabs[selectedTabIndex].splitRoot.isHidden = true
        }

        selectedTabIndex = index

        let entry = tabs[selectedTabIndex]
        let root = entry.splitRoot
        root.isHidden = false
        root.frame = contentRect
        root.wantsLayer = true
        root.layer?.cornerRadius = contentRadius
        root.layer?.masksToBounds = true
        root.layer?.borderColor = Theme.border.cgColor
        root.layer?.borderWidth = 0.5

        let focusSurface = entry.focusedSurface ?? entry.surfaces.first
        window?.makeFirstResponder(focusSurface)

        refreshTabUI()
    }

    func updateTabTitle(_ title: String, for surface: TerminalSurfaceView) {
        if let idx = tabs.firstIndex(where: { $0.surfaces.contains(where: { $0 === surface }) }) {
            tabs[idx].title = title
            refreshTabUI()
        }
    }

    func updateTabCwd(_ cwd: String, for surface: TerminalSurfaceView) {
        if let idx = tabs.firstIndex(where: { $0.surfaces.contains(where: { $0 === surface }) }) {
            tabs[idx].cwd = cwd
            let basename = (cwd as NSString).lastPathComponent
            tabs[idx].title = basename
            refreshTabUI()
        }
    }

    var activeCwd: String {
        if selectedTabIndex < tabs.count, let cwd = tabs[selectedTabIndex].cwd {
            return cwd
        }
        return FileManager.default.currentDirectoryPath
    }

    private func refreshTabUI() {
        let tabData = tabs.map { (id: $0.id, title: $0.title) }
        sidebar.update(tabs: tabData, selectedIndex: selectedTabIndex)

        let barTabs = tabs.map { TabBarView.Tab(id: $0.id, title: $0.title) }
        tabBar.update(tabs: barTabs, selectedIndex: selectedTabIndex)
    }

    // MARK: - Split Panes

    func splitPane(direction: SplitPaneView.Orientation) {
        guard selectedTabIndex < tabs.count, let terminalApp else { return }

        let surface = TerminalSurfaceView(app: terminalApp)
        let tabId = tabs[selectedTabIndex].id
        surface.onClose = { [weak self, tabId] _ in
            guard let self else { return }
            self.handleSurfaceClosed(id: tabId, surface: surface)
        }

        let root = tabs[selectedTabIndex].splitRoot

        // Find the leaf that contains the focused surface and split it
        if let focused = activeSurface, let leaf = root.leaf(containing: focused) {
            leaf.split(orientation: direction, newContent: surface)
        } else {
            root.split(orientation: direction, newContent: surface)
        }

        tabs[selectedTabIndex].surfaces.append(surface)
        tabs[selectedTabIndex].focusedSurface = surface
        window?.makeFirstResponder(surface)
        needsLayout = true
    }

    func closePane() {
        guard selectedTabIndex < tabs.count else { return }
        let entry = tabs[selectedTabIndex]

        // If only one surface, close the whole tab
        guard entry.surfaces.count > 1, let focused = activeSurface else {
            closeCurrentTab()
            return
        }

        // Find and remove the leaf
        if let leaf = entry.splitRoot.leaf(containing: focused),
           let parent = entry.splitRoot.parent(of: leaf) {
            focused.onClose = nil
            parent.removeChild(leaf)

            tabs[selectedTabIndex].surfaces.removeAll { $0 === focused }
            let newFocus = tabs[selectedTabIndex].surfaces.last
            tabs[selectedTabIndex].focusedSurface = newFocus
            window?.makeFirstResponder(newFocus)
            needsLayout = true
        } else if entry.surfaces.count == 1 {
            closeCurrentTab()
        }
    }

    private enum PaneDirection { case left, right }

    private func navigatePane(_ direction: PaneDirection) {
        guard selectedTabIndex < tabs.count else { return }
        let surfaces = tabs[selectedTabIndex].surfaces
        guard surfaces.count > 1, let current = activeSurface else { return }

        if let idx = surfaces.firstIndex(where: { $0 === current }) {
            let next: Int
            switch direction {
            case .right: next = (idx + 1) % surfaces.count
            case .left: next = (idx - 1 + surfaces.count) % surfaces.count
            }
            tabs[selectedTabIndex].focusedSurface = surfaces[next]
            window?.makeFirstResponder(surfaces[next])
        }
    }

    private func handleSurfaceClosed(id: UUID, surface: TerminalSurfaceView) {
        guard let tabIdx = tabs.firstIndex(where: { $0.id == id }) else { return }

        if tabs[tabIdx].surfaces.count <= 1 {
            closeTab(tabIdx)
        } else {
            // Close just this pane
            if let leaf = tabs[tabIdx].splitRoot.leaf(containing: surface),
               let parent = tabs[tabIdx].splitRoot.parent(of: leaf) {
                surface.onClose = nil
                parent.removeChild(leaf)
                tabs[tabIdx].surfaces.removeAll { $0 === surface }
                let newFocus = tabs[tabIdx].surfaces.last
                tabs[tabIdx].focusedSurface = newFocus
                if tabIdx == selectedTabIndex {
                    window?.makeFirstResponder(newFocus)
                }
            }
        }
    }

    // MARK: - Layout

    private let contentPadding: CGFloat = 6
    private let contentRadius: CGFloat = 12
    private let sidebarGap: CGFloat = 4
    private let tabBarHeight: CGFloat = 36

    private var contentRect: NSRect {
        let p = contentPadding
        var rect: NSRect

        if useSidebar && sidebar.isExpanded {
            let sidebarRight = p + SidebarView.expandedWidth + sidebarGap
            rect = NSRect(
                x: sidebarRight, y: p,
                width: bounds.width - sidebarRight - p,
                height: bounds.height - p * 2
            )
        } else if !useSidebar && tabs.count > 1 {
            // Tab bar mode with multiple tabs — reserve space at top
            rect = NSRect(
                x: p, y: p,
                width: bounds.width - p * 2,
                height: bounds.height - p * 2 - tabBarHeight
            )
        } else {
            rect = NSRect(x: p, y: p, width: bounds.width - p * 2, height: bounds.height - p * 2)
        }
        return rect
    }

    override func layout() {
        super.layout()
        let p = contentPadding

        // Sidebar — width is 0 when collapsed, full when expanded
        let sidebarWidth: CGFloat = sidebar.isExpanded ? SidebarView.expandedWidth : 0
        sidebar.frame = NSRect(
            x: p, y: p,
            width: sidebarWidth,
            height: bounds.height - p * 2
        )
        sidebar.wantsLayer = true
        sidebar.layer?.cornerRadius = contentRadius

        // Tab bar (top area, after traffic lights)
        if !useSidebar {
            let tabBarX: CGFloat = 80 // clear of traffic lights
            tabBar.frame = NSRect(
                x: tabBarX,
                y: bounds.height - p - tabBarHeight,
                width: bounds.width - tabBarX - p,
                height: tabBarHeight
            )
        }

        // Active tab's split root fills content area
        let rect = contentRect
        if selectedTabIndex < tabs.count {
            let root = tabs[selectedTabIndex].splitRoot
            root.frame = rect
            root.layer?.cornerRadius = contentRadius
            root.layer?.masksToBounds = true
        }

        setupEdgeTracking()
    }

    private func animateContentLayout() {
        let p = contentPadding
        let sidebarWidth: CGFloat = sidebar.isExpanded ? SidebarView.expandedWidth : 0

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animSlow
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            ctx.allowsImplicitAnimation = true

            // Animate sidebar frame width in sync with content
            sidebar.animator().frame = NSRect(
                x: p, y: p,
                width: sidebarWidth,
                height: bounds.height - p * 2
            )

            if selectedTabIndex < tabs.count {
                tabs[selectedTabIndex].splitRoot.animator().frame = contentRect
            }
        }
    }

    // MARK: - Theme

    private func applyFrameColor() {
        layer?.backgroundColor = Theme.colors.frame.cgColor
    }

    private func handleThemeChange() {
        applyFrameColor()
        if selectedTabIndex < tabs.count {
            tabs[selectedTabIndex].splitRoot.layer?.borderColor = Theme.border.cgColor
        }
        needsDisplay = true
    }

    // MARK: - Edge Hover Detection

    private func setupEdgeTracking() {
        if let existing = edgeTrackingArea { removeTrackingArea(existing) }
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
        palette.onSubmit = { [weak self] text in self?.handleCommand(text) }
        palette.onDismiss = { [weak self] in
            self?.isPaletteVisible = false
            self?.commandPalette = nil
            self?.window?.makeFirstResponder(self?.activeSurface)
        }
        commandPalette = palette
        palette.show(in: self)
        (window as? TerminalWindow)?.showTrafficLights()
    }

    func hideCommandPalette() { commandPalette?.hide() }

    private func handleCommand(_ text: String) {
        let cmd = text.lowercased().trimmingCharacters(in: .whitespaces)

        switch cmd {
        case "new tab", "tab", "new":
            createTab()
        case "close tab", "close":
            closeCurrentTab()
        case "split", "split right", "vsplit":
            splitPane(direction: .vertical)
        case "split down", "hsplit":
            splitPane(direction: .horizontal)
        case "close pane":
            closePane()
        case "sidebar":
            sidebar.toggle()
        case "tab bar", "tabbar":
            toggleTabMode()
        case "hud", "status":
            showHUD()
        case "copy":
            copySelection()
        case "paste":
            pasteClipboard()
        default:
            if cmd.hasPrefix(">") {
                let shellCmd = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !shellCmd.isEmpty, let surface = activeSurface?.surface {
                    let input = shellCmd + "\n"
                    input.withCString { ptr in
                        ghostty_surface_text(surface, ptr, UInt(input.utf8.count))
                    }
                }
            } else {
                // Check if it's a theme name
                if let theme = ThemeColors.allThemes.first(where: {
                    $0.name.lowercased() == cmd
                }) {
                    BellithSettings.shared.themeName = theme.name
                    ThemeManager.shared.apply(theme)
                } else {
                    NSLog("[Bellith] Unknown command: %@", text)
                }
            }
        }
    }

    // MARK: - Copy / Paste

    func copySelection() {
        guard let surface = activeSurface?.surface else { return }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return }
        defer { ghostty_surface_free_text(surface, &text) }
        guard text.text_len > 0 else { return }

        let str = String(cString: text.text)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(str, forType: .string)
    }

    func pasteClipboard() {
        guard let surface = activeSurface?.surface else { return }
        guard let str = NSPasteboard.general.string(forType: .string) else { return }
        str.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(str.utf8.count))
        }
    }

    // MARK: - HUD

    func showHUD() {
        if let existing = hud, existing.superview != nil {
            existing.scheduleHide(after: 0)
            return
        }
        let h = HUDView()
        h.currentCwd = activeCwd
        hud = h
        h.show(in: self)
        h.scheduleHide(after: 3.0)
    }
}
