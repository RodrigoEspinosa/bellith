import AppKit
import GhosttyKit
import os

/// Container that hosts multiple terminal tabs (each with optional split panes),
/// smart inspector tabs, a sidebar or tab bar, and the command palette.
final class TerminalContainerView: NSView {
    private weak var terminalApp: TerminalApp?

    enum TabContent {
        case terminal(splitRoot: SplitPaneView, surfaces: [TerminalSurfaceView], focusedSurface: TerminalSurfaceView?)
        case smart(panel: SmartPanelView)
    }

    enum TabKind: Equatable {
        case terminal
        case smart(SmartPanelKind)
    }

    struct TabEntry {
        let id: UUID
        var title: String
        var cwd: String?
        var content: TabContent

        var kind: TabKind {
            switch content {
            case .terminal: return .terminal
            case .smart(let panel): return .smart(panel.kind)
            }
        }

        var splitRoot: SplitPaneView? {
            if case .terminal(let root, _, _) = content { return root }
            return nil
        }

        var surfaces: [TerminalSurfaceView] {
            if case .terminal(_, let surfaces, _) = content { return surfaces }
            return []
        }

        var focusedSurface: TerminalSurfaceView? {
            get {
                if case .terminal(_, _, let focused) = content { return focused }
                return nil
            }
            set {
                if case .terminal(let root, let surfaces, _) = content {
                    content = .terminal(splitRoot: root, surfaces: surfaces, focusedSurface: newValue)
                }
            }
        }

        var rootView: NSView {
            switch content {
            case .terminal(let root, _, _): return root
            case .smart(let panel): return panel
            }
        }

        var isTerminal: Bool {
            if case .terminal = content { return true }
            return false
        }

        mutating func addSurface(_ surface: TerminalSurfaceView) {
            if case .terminal(let root, var surfaces, _) = content {
                surfaces.append(surface)
                content = .terminal(splitRoot: root, surfaces: surfaces, focusedSurface: surface)
            }
        }

        mutating func removeSurface(_ surface: TerminalSurfaceView) {
            if case .terminal(let root, var surfaces, let focused) = content {
                surfaces.removeAll { $0 === surface }
                let newFocus = (focused === surface) ? surfaces.last : focused
                content = .terminal(splitRoot: root, surfaces: surfaces, focusedSurface: newFocus)
            }
        }
    }

    private var tabs: [TabEntry] = []
    private(set) var selectedTabIndex: Int = 0
    let sidebar = SidebarView()
    let tabBar = TabBarView()
    let statusBar = StatusBarView()
    let titleBar = TitleBarView()
    private var commandPalette: CommandPaletteView?
    private var searchBar: SearchBarView?
    private var hud: HUDView?
    private(set) var isPaletteVisible = false
    private var isSearchVisible = false
    private var isClosingTab = false
    private var edgeTrackingArea: NSTrackingArea?
    private var themeObserver: NSObjectProtocol?
    private var isAnimatingLayout = false
    private var isZoomed = false
    private var zoomedSurface: TerminalSurfaceView?
    private var isBroadcasting = false
    private var recentlyClosedTabs: [(title: String, cwd: String?)] = []
    private static let maxRecentlyClosed = 10
    private var zoomBadge: NSView?

    init(terminalApp: TerminalApp) {
        self.terminalApp = terminalApp
        super.init(frame: .zero)
        wantsLayer = true
        applyFrameColor()

        // Sidebar
        addSubview(sidebar)
        sidebar.onSelectTab = { [weak self] i in
            self?.selectTab(i)
            if !(self?.sidebar.isPinned ?? false) { self?.sidebar.hide() }
        }
        sidebar.onCloseTab = { [weak self] i in self?.closeTab(i) }
        sidebar.onNewTab = { [weak self] in self?.createTab() }
        sidebar.onExpandChanged = { [weak self] _ in self?.animateContentLayout() }
        sidebar.onReorderTab = { [weak self] from, to in self?.reorderTab(from: from, to: to) }
        sidebar.onTabContextMenu = { [weak self] index, point in self?.showTabContextMenu(index: index, at: point) }

        // Tab bar
        addSubview(tabBar)
        tabBar.onSelectTab = { [weak self] i in self?.selectTab(i) }
        tabBar.onCloseTab = { [weak self] i in self?.closeTab(i) }
        tabBar.onNewTab = { [weak self] in self?.createTab() }
        tabBar.onReorderTab = { [weak self] from, to in self?.reorderTab(from: from, to: to) }

        // Status bar (always visible at bottom)
        addSubview(statusBar)

        // Title bar breadcrumbs (in the title area)
        addSubview(titleBar)

        applyTabMode()

        // Theme change observer
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleThemeChange() }

        createTab()
    }

    deinit {
        teardown()
    }

    /// Explicitly release resources — call before dropping the last reference
    /// to break retain cycles and stop background work.
    func teardown() {
        // Remove theme observer
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
            self.themeObserver = nil
        }

        // Disconnect all surface callbacks to break retain cycles
        for tab in tabs {
            for surface in tab.surfaces {
                surface.onClose = nil
                surface.onTextInserted = nil
            }
            // Stop smart panel refresh timers
            if case .smart(let panel) = tab.content {
                panel.stopRefreshing()
            }
        }

        terminalApp = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Active Surface

    var activeSurface: TerminalSurfaceView? {
        guard selectedTabIndex < tabs.count else { return nil }
        return tabs[selectedTabIndex].focusedSurface ?? tabs[selectedTabIndex].surfaces.first
    }

    // MARK: - Focus Indicator

    private func updateFocusIndicator() {
        guard selectedTabIndex < tabs.count else { return }
        let entry = tabs[selectedTabIndex]
        guard entry.isTerminal else { return }
        let hasSplits = entry.surfaces.count > 1

        for surface in entry.surfaces {
            if let root = entry.splitRoot, let leaf = root.leaf(containing: surface) {
                leaf.wantsLayer = true

                // Remove any existing focus indicator sublayer
                leaf.layer?.sublayers?.removeAll { $0.name == "focusIndicator" }

                // Reset border properties (used only for broadcast mode)
                leaf.layer?.borderColor = nil
                leaf.layer?.borderWidth = 0
                leaf.layer?.cornerRadius = 0

                if isBroadcasting && hasSplits {
                    // Broadcast mode: full border on all panes
                    leaf.layer?.borderColor = Theme.accent.withAlphaComponent(0.6).cgColor
                    leaf.layer?.borderWidth = 1.5
                    leaf.layer?.cornerRadius = 4
                } else if hasSplits && surface === activeSurface {
                    // Focused pane: thin accent line at the top edge
                    let indicator = CALayer()
                    indicator.name = "focusIndicator"
                    indicator.backgroundColor = Theme.accent.withAlphaComponent(0.6).cgColor
                    indicator.cornerRadius = 1
                    let margin: CGFloat = 8
                    indicator.frame = CGRect(
                        x: margin,
                        y: leaf.bounds.height - 2,
                        width: leaf.bounds.width - margin * 2,
                        height: 2
                    )
                    indicator.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
                    leaf.layer?.addSublayer(indicator)
                }
            }
        }
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

        if mods == .command && (key == "q" || key == ",") { return super.performKeyEquivalent(with: event) }

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

        if matches(event, action: "search") { showSearch(); return true }

        if matches(event, action: "navLeft")  { navigatePane(.left);  return true }
        if matches(event, action: "navRight") { navigatePane(.right); return true }
        if matches(event, action: "navUp")    { navigatePane(.up);    return true }
        if matches(event, action: "navDown")  { navigatePane(.down);  return true }

        if matches(event, action: "resizeLeft")  { resizePane(.left);  return true }
        if matches(event, action: "resizeRight") { resizePane(.right); return true }
        if matches(event, action: "resizeUp")    { resizePane(.up);    return true }
        if matches(event, action: "resizeDown")  { resizePane(.down);  return true }

        if matches(event, action: "zoomPane") { toggleZoom(); return true }
        if matches(event, action: "equalizePanes") { equalizePanes(); return true }
        if matches(event, action: "broadcastInput") { toggleBroadcast(); return true }

        if matches(event, action: "fontSizeUp") { adjustFontSize(delta: 1); return true }
        if matches(event, action: "fontSizeDown") { adjustFontSize(delta: -1); return true }
        if matches(event, action: "fontSizeReset") { resetFontSize(); return true }

        if matches(event, action: "toggleFullscreen") {
            window?.toggleFullScreen(nil)
            return true
        }

        if matches(event, action: "reloadConfig") { reloadConfig(); return true }
        if matches(event, action: "reopenTab") { reopenClosedTab(); return true }
        if matches(event, action: "clearBuffer") { clearBuffer(); return true }

        if matches(event, action: "newWindow") {
            NotificationCenter.default.post(name: .init("BellithCreateNewWindow"), object: nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Tab Management

    @discardableResult
    func createTab() -> TerminalSurfaceView? {
        guard let terminalApp else { return nil }

        let id = UUID()
        let surface = makeSurface(tabId: id, app: terminalApp)

        let splitRoot = SplitPaneView(content: surface)
        let initialCwd = FileManager.default.currentDirectoryPath
        tabs.append(TabEntry(
            id: id, title: (initialCwd as NSString).lastPathComponent, cwd: initialCwd,
            content: .terminal(splitRoot: splitRoot, surfaces: [surface], focusedSurface: surface)
        ))
        addSubview(splitRoot, positioned: .below, relativeTo: sidebar)
        statusBar.updateCwd(initialCwd)
        titleBar.updatePath(initialCwd)
        refreshStatusBarAsync(cwd: initialCwd)

        selectTab(tabs.count - 1)
        refreshTabUI()
        return surface
    }

    // MARK: - Smart Tab Management

    func createSmartTab(kind: SmartPanelKind) {
        let panel = SmartPanelView.create(kind: kind)

        // Find the shell PID from the current terminal's CWD
        panel.shellPID = findShellPID()

        let id = UUID()
        tabs.append(TabEntry(
            id: id, title: kind.displayName, cwd: nil,
            content: .smart(panel: panel)
        ))
        addSubview(panel, positioned: .below, relativeTo: sidebar)

        selectTab(tabs.count - 1)
        refreshTabUI()
    }

    func closeTab(_ index: Int) {
        guard index < tabs.count, !isClosingTab else { return }
        isClosingTab = true
        defer { isClosingTab = false }

        let entry = tabs[index]

        // Track for reopen
        if entry.isTerminal {
            recentlyClosedTabs.append((title: entry.title, cwd: entry.cwd))
            if recentlyClosedTabs.count > Self.maxRecentlyClosed {
                recentlyClosedTabs.removeFirst()
            }
        }

        if case .smart(let panel) = entry.content {
            panel.stopRefreshing()
        }
        for s in entry.surfaces { s.onClose = nil }
        entry.rootView.removeFromSuperview()
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

    func reorderTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < tabs.count,
              destinationIndex >= 0, destinationIndex < tabs.count else { return }

        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: destinationIndex)

        if selectedTabIndex == sourceIndex {
            selectedTabIndex = destinationIndex
        } else if sourceIndex < selectedTabIndex && destinationIndex >= selectedTabIndex {
            selectedTabIndex -= 1
        } else if sourceIndex > selectedTabIndex && destinationIndex <= selectedTabIndex {
            selectedTabIndex += 1
        }

        refreshTabUI()
    }

    func selectTab(_ index: Int) {
        guard index >= 0 && index < tabs.count else { return }

        if selectedTabIndex < tabs.count {
            if case .smart(let panel) = tabs[selectedTabIndex].content {
                panel.stopRefreshing()
            }
            tabs[selectedTabIndex].rootView.isHidden = true
        }

        selectedTabIndex = index

        let entry = tabs[selectedTabIndex]
        let root = entry.rootView
        root.isHidden = false
        root.frame = contentRect
        root.wantsLayer = true
        root.layer?.cornerRadius = contentRadius
        root.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 0

        switch entry.content {
        case .terminal:
            let focusSurface = entry.focusedSurface ?? entry.surfaces.first
            window?.makeFirstResponder(focusSurface)
            updateFocusIndicator()
            // Update status bar with current tab info
            statusBar.updateCwd(entry.cwd)
            titleBar.updatePath(entry.cwd)
            if let cwd = entry.cwd {
                refreshStatusBarAsync(cwd: cwd)
            }
            statusBar.isHidden = false
        case .smart(let panel):
            panel.startRefreshing()
            window?.makeFirstResponder(self)
            statusBar.isHidden = true
        }

        refreshTabUI()
    }

    func updateTabTitle(_ title: String, for surface: TerminalSurfaceView) {
        if let idx = tabs.firstIndex(where: { $0.surfaces.contains(where: { $0 === surface }) }) {
            tabs[idx].title = title
            refreshTabUI()
        }
    }

    func updateTabCwd(_ cwd: String, for surface: TerminalSurfaceView) {
        surface.currentCwd = cwd
        if let idx = tabs.firstIndex(where: { $0.surfaces.contains(where: { $0 === surface }) }) {
            tabs[idx].cwd = cwd
            let basename = (cwd as NSString).lastPathComponent
            tabs[idx].title = basename
            refreshTabUI()

            // Update status bar and title bar if this is the active tab
            if idx == selectedTabIndex {
                statusBar.updateCwd(cwd)
                titleBar.updatePath(cwd)
                refreshStatusBarAsync(cwd: cwd)
            }
        }
    }

    /// Fetch git branch and process info off the main thread, then update the status bar.
    private func refreshStatusBarAsync(cwd: String) {
        let pid = findShellPID()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Git branch
            let branch = Self.gitBranch(in: cwd)

            // Foreground process
            var foregroundProcess: String?
            if let pid {
                let shellName = ProcessMonitor.processName(for: pid)
                if let tree = ProcessMonitor.processTree(rootPID: pid) {
                    var deepest: TerminalProcessInfo?
                    func findDeepest(_ node: TerminalProcessInfo) {
                        if node.children.isEmpty && node.pid != pid { deepest = node }
                        for child in node.children { findDeepest(child) }
                    }
                    findDeepest(tree)
                    if let d = deepest, d.name.lowercased() != shellName.lowercased() {
                        foregroundProcess = d.name
                    }
                }
            }

            DispatchQueue.main.async {
                self?.statusBar.updateGitBranch(branch)
                self?.statusBar.updateProcess(foregroundProcess)
            }
        }
    }

    private static func gitBranch(in directory: String) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "branch", "--show-current"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        } catch { return nil }
    }

    var activeCwd: String {
        if selectedTabIndex < tabs.count, let cwd = tabs[selectedTabIndex].cwd {
            return cwd
        }
        return FileManager.default.currentDirectoryPath
    }

    private func refreshTabUI() {
        let tabData = tabs.map { (id: $0.id, title: $0.title, kind: $0.kind) }
        sidebar.update(tabs: tabData, selectedIndex: selectedTabIndex)

        let barTabs = tabs.map { TabBarView.Tab(id: $0.id, title: $0.title, kind: $0.kind) }
        tabBar.update(tabs: barTabs, selectedIndex: selectedTabIndex)
    }

    // MARK: - Split Panes

    func splitPane(direction: SplitPaneView.Orientation) {
        guard selectedTabIndex < tabs.count, tabs[selectedTabIndex].isTerminal, let terminalApp else { return }

        let tabId = tabs[selectedTabIndex].id
        let surface = makeSurface(tabId: tabId, app: terminalApp)

        guard let root = tabs[selectedTabIndex].splitRoot else { return }

        if let focused = activeSurface, let leaf = root.leaf(containing: focused) {
            leaf.split(orientation: direction, newContent: surface)
        } else {
            root.split(orientation: direction, newContent: surface)
        }

        tabs[selectedTabIndex].addSurface(surface)
        window?.makeFirstResponder(surface)
        needsLayout = true
        updateFocusIndicator()
    }

    func closePane() {
        guard selectedTabIndex < tabs.count, tabs[selectedTabIndex].isTerminal else { return }
        let entry = tabs[selectedTabIndex]

        guard entry.surfaces.count > 1, let focused = activeSurface else {
            closeCurrentTab()
            return
        }

        guard let root = entry.splitRoot else { return }

        if let leaf = root.leaf(containing: focused),
           let parent = root.parent(of: leaf) {
            focused.onClose = nil
            parent.removeChild(leaf)

            tabs[selectedTabIndex].removeSurface(focused)
            let newFocus = tabs[selectedTabIndex].focusedSurface
            window?.makeFirstResponder(newFocus)
            needsLayout = true
            updateFocusIndicator()
        } else if entry.surfaces.count == 1 {
            closeCurrentTab()
        }
    }

    private func navigatePane(_ direction: SplitPaneView.Direction) {
        guard selectedTabIndex < tabs.count, let current = activeSurface else { return }
        guard let root = tabs[selectedTabIndex].splitRoot else { return }
        if let nextView = root.adjacentLeaf(from: current, direction: direction),
           let nextSurface = nextView as? TerminalSurfaceView {
            tabs[selectedTabIndex].focusedSurface = nextSurface
            window?.makeFirstResponder(nextSurface)
            updateFocusIndicator()
        }
    }

    private func resizePane(_ direction: SplitPaneView.Direction) {
        guard selectedTabIndex < tabs.count, let current = activeSurface else { return }
        guard let root = tabs[selectedTabIndex].splitRoot else { return }
        root.resizeFromLeaf(containing: current, direction: direction, delta: 0.05)
    }

    // MARK: - Zoom

    private func toggleZoom() {
        guard selectedTabIndex < tabs.count, tabs[selectedTabIndex].isTerminal else { return }
        let entry = tabs[selectedTabIndex]
        guard entry.surfaces.count > 1 else { return }

        if isZoomed {
            if let surface = zoomedSurface {
                surface.removeFromSuperview()
            }
            entry.splitRoot?.isHidden = false
            isZoomed = false
            zoomedSurface = nil
            needsLayout = true
            updateFocusIndicator()
            updateZoomBadge()
        } else {
            guard let focused = activeSurface else { return }
            isZoomed = true
            zoomedSurface = focused
            entry.splitRoot?.isHidden = true
            addSubview(focused, positioned: .below, relativeTo: commandPalette ?? searchBar)
            focused.frame = contentRect
            window?.makeFirstResponder(focused)
            updateZoomBadge()
        }
    }

    // MARK: - Equalize

    private func equalizePanes() {
        guard selectedTabIndex < tabs.count else { return }
        tabs[selectedTabIndex].splitRoot?.equalizeAll()
    }

    // MARK: - Broadcast

    private var broadcastBadge: NSView?

    private func toggleBroadcast() {
        isBroadcasting.toggle()
        updateFocusIndicator()
        updateBroadcastBadge()
    }

    private func updateBroadcastBadge() {
        if isBroadcasting {
            if broadcastBadge == nil {
                let badge = BroadcastBadge()
                addSubview(badge)
                broadcastBadge = badge
                badge.alphaValue = 0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = Theme.animMedium
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    badge.animator().alphaValue = 1
                }
            }
            needsLayout = true
        } else {
            if let badge = broadcastBadge {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = Theme.animFast
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    badge.animator().alphaValue = 0
                }, completionHandler: {
                    badge.removeFromSuperview()
                })
                broadcastBadge = nil
            }
        }
    }

    // MARK: - Tab Context Menu

    private func showTabContextMenu(index: Int, at windowPoint: NSPoint) {
        guard index < tabs.count else { return }
        let menu = NSMenu()

        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(contextMenuCloseTab(_:)), keyEquivalent: "")
        closeItem.representedObject = index
        closeItem.target = self
        menu.addItem(closeItem)

        if tabs.count > 1 {
            let closeOthersItem = NSMenuItem(title: "Close Other Tabs", action: #selector(contextMenuCloseOtherTabs(_:)), keyEquivalent: "")
            closeOthersItem.representedObject = index
            closeOthersItem.target = self
            menu.addItem(closeOthersItem)

            let closeRightItem = NSMenuItem(title: "Close Tabs to the Right", action: #selector(contextMenuCloseTabsToRight(_:)), keyEquivalent: "")
            closeRightItem.representedObject = index
            closeRightItem.target = self
            menu.addItem(closeRightItem)
        }

        menu.addItem(.separator())

        let duplicateItem = NSMenuItem(title: "Duplicate Tab", action: #selector(contextMenuDuplicateTab(_:)), keyEquivalent: "")
        duplicateItem.representedObject = index
        duplicateItem.target = self
        menu.addItem(duplicateItem)

        let newWindowItem = NSMenuItem(title: "Move to New Window", action: #selector(contextMenuMoveToNewWindow(_:)), keyEquivalent: "")
        newWindowItem.representedObject = index
        newWindowItem.target = self
        menu.addItem(newWindowItem)

        let point = convert(windowPoint, from: nil)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    @objc private func contextMenuCloseTab(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        closeTab(index)
    }

    @objc private func contextMenuCloseOtherTabs(_ sender: NSMenuItem) {
        guard let keepIndex = sender.representedObject as? Int, keepIndex < tabs.count else { return }
        let keepId = tabs[keepIndex].id
        var i = tabs.count - 1
        while i >= 0 {
            if tabs[i].id != keepId { closeTab(i) }
            i -= 1
        }
    }

    @objc private func contextMenuCloseTabsToRight(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        var i = tabs.count - 1
        while i > index {
            closeTab(i)
            i -= 1
        }
    }

    @objc private func contextMenuDuplicateTab(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, index < tabs.count else { return }
        let cwd = tabs[index].cwd
        if let surface = createTab(), let cwd, !cwd.isEmpty {
            sendCdWhenReady(surface: surface, cwd: cwd)
        }
    }

    @objc private func contextMenuMoveToNewWindow(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, index < tabs.count else { return }
        let cwd = tabs[index].cwd
        closeTab(index)
        NotificationCenter.default.post(name: .init("BellithCreateNewWindow"), object: cwd)
    }

    // MARK: - Reopen Closed Tab

    func reopenClosedTab() {
        guard let last = recentlyClosedTabs.popLast() else { return }
        if let surface = createTab(), let cwd = last.cwd, !cwd.isEmpty {
            sendCdWhenReady(surface: surface, cwd: cwd)
        }
    }

    // MARK: - Clear Buffer

    func clearBuffer() {
        guard let surface = activeSurface?.surface else { return }
        let action = "clear_screen"
        action.withCString { ptr in
            _ = ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }

    // MARK: - Zoom Badge

    private func updateZoomBadge() {
        if isZoomed {
            if zoomBadge == nil {
                let badge = ZoomBadge()
                addSubview(badge)
                zoomBadge = badge
                badge.alphaValue = 0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = Theme.animMedium
                    badge.animator().alphaValue = 1
                }
            }
            needsLayout = true
        } else {
            if let badge = zoomBadge {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = Theme.animFast
                    badge.animator().alphaValue = 0
                }, completionHandler: {
                    badge.removeFromSuperview()
                })
                zoomBadge = nil
            }
        }
    }

    func broadcastText(_ text: String, from source: TerminalSurfaceView) {
        guard isBroadcasting, selectedTabIndex < tabs.count else { return }
        for surface in tabs[selectedTabIndex].surfaces where surface !== source {
            if let surf = surface.surface {
                text.withCString { ptr in
                    ghostty_surface_text(surf, ptr, UInt(text.utf8.count))
                }
            }
        }
    }

    func broadcastKeyEvent(_ event: ghostty_input_key_s, from source: TerminalSurfaceView) {
        guard isBroadcasting, selectedTabIndex < tabs.count else { return }
        for surface in tabs[selectedTabIndex].surfaces where surface !== source {
            if let surf = surface.surface {
                ghostty_surface_key(surf, event)
            }
        }
    }

    /// Find the shell PID for the current terminal by looking up the Bellith app's
    /// child processes and matching against the active tab's CWD.
    private func findShellPID() -> pid_t? {
        guard let surface = activeSurface, let cwd = surface.currentCwd else { return nil }
        let appPID = ProcessInfo.processInfo.processIdentifier
        guard let tree = ProcessMonitor.processTree(rootPID: appPID) else { return nil }

        let shellNames: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "nu", "elvish", "nushell"]

        // Walk children looking for a shell whose CWD matches the active surface
        func findMatchingChild(_ node: TerminalProcessInfo) -> pid_t? {
            if shellNames.contains(node.name.lowercased()),
               let childCwd = ProcessMonitor.workingDirectory(for: node.pid),
               childCwd == cwd {
                return node.pid
            }
            for child in node.children {
                if let found = findMatchingChild(child) { return found }
            }
            return nil
        }
        return findMatchingChild(tree)
    }

    private func handleSurfaceClosed(id: UUID, surface: TerminalSurfaceView) {
        guard let tabIdx = tabs.firstIndex(where: { $0.id == id }) else { return }

        if tabs[tabIdx].surfaces.count <= 1 {
            closeTab(tabIdx)
        } else {
            guard let root = tabs[tabIdx].splitRoot else { return }
            if let leaf = root.leaf(containing: surface),
               let parent = root.parent(of: leaf) {
                surface.onClose = nil
                parent.removeChild(leaf)
                tabs[tabIdx].removeSurface(surface)
                if tabIdx == selectedTabIndex {
                    window?.makeFirstResponder(tabs[tabIdx].focusedSurface)
                    updateFocusIndicator()
                }
            }
        }
    }

    // MARK: - Layout

    private let contentPadding: CGFloat = 8
    private let contentRadius: CGFloat = 12
    private let sidebarGap: CGFloat = 6
    private let tabBarHeight: CGFloat = 36
    private let statusBarHeight: CGFloat = StatusBarView.height
    private let titleBarHeight: CGFloat = 28

    private func contentRect(forSidebarWidth sidebarWidth: CGFloat) -> NSRect {
        let p = contentPadding
        let bottomOffset = p + statusBarHeight
        let topOffset = p + titleBarHeight

        if useSidebar && sidebarWidth > 0 {
            let sidebarRight = p + sidebarWidth + sidebarGap
            return NSRect(
                x: sidebarRight, y: bottomOffset,
                width: bounds.width - sidebarRight - p,
                height: bounds.height - bottomOffset - topOffset
            )
        } else if !useSidebar && tabs.count > 1 {
            return NSRect(
                x: p, y: bottomOffset,
                width: bounds.width - p * 2,
                height: bounds.height - bottomOffset - topOffset - tabBarHeight
            )
        } else {
            return NSRect(x: p, y: bottomOffset, width: bounds.width - p * 2, height: bounds.height - bottomOffset - topOffset)
        }
    }

    private var contentRect: NSRect {
        let sidebarWidth: CGFloat = (useSidebar && sidebar.isExpanded) ? SidebarView.expandedWidth : 0
        return contentRect(forSidebarWidth: sidebarWidth)
    }

    override func layout() {
        super.layout()
        guard !isAnimatingLayout else { return }

        let p = contentPadding

        let sidebarWidth: CGFloat = sidebar.isExpanded ? SidebarView.expandedWidth : 0
        sidebar.frame = NSRect(
            x: p, y: p,
            width: sidebarWidth,
            height: bounds.height - p * 2
        )
        sidebar.wantsLayer = true
        sidebar.layer?.cornerRadius = contentRadius

        if !useSidebar {
            let tabBarX: CGFloat = 80
            tabBar.frame = NSRect(
                x: tabBarX,
                y: bounds.height - p - titleBarHeight - tabBarHeight,
                width: bounds.width - tabBarX - p,
                height: tabBarHeight
            )
        }

        // Title bar breadcrumbs — at the top, aligned with content area
        let contentLeft: CGFloat
        if useSidebar && sidebarWidth > 0 {
            contentLeft = p + sidebarWidth + sidebarGap
        } else {
            contentLeft = p
        }
        titleBar.frame = NSRect(
            x: contentLeft + 12,
            y: bounds.height - p - titleBarHeight,
            width: bounds.width - contentLeft - p - 12,
            height: titleBarHeight
        )

        // Status bar — at the bottom, spanning the content width
        let statusBarX: CGFloat
        let statusBarW: CGFloat
        if useSidebar && sidebarWidth > 0 {
            statusBarX = p + sidebarWidth + sidebarGap
            statusBarW = bounds.width - statusBarX - p
        } else {
            statusBarX = p
            statusBarW = bounds.width - p * 2
        }
        statusBar.frame = NSRect(
            x: statusBarX, y: p,
            width: statusBarW,
            height: statusBarHeight
        )
        statusBar.wantsLayer = true
        statusBar.layer?.cornerRadius = contentRadius
        statusBar.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        statusBar.layer?.masksToBounds = true

        let rect = contentRect
        if selectedTabIndex < tabs.count {
            let root = tabs[selectedTabIndex].rootView
            root.frame = rect
            root.layer?.cornerRadius = contentRadius
            root.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            root.layer?.masksToBounds = true
        }

        setupEdgeTracking()

        // Position broadcast badge
        if let badge = broadcastBadge {
            let badgeW: CGFloat = 110
            let badgeH: CGFloat = 26
            badge.frame = NSRect(
                x: rect.midX - badgeW / 2,
                y: rect.maxY - badgeH - 8,
                width: badgeW,
                height: badgeH
            )
        }

        // Position zoom badge
        if let badge = zoomBadge {
            let badgeW: CGFloat = 80
            let badgeH: CGFloat = 24
            let offsetX: CGFloat = broadcastBadge != nil ? 70 : 0
            badge.frame = NSRect(
                x: rect.midX - badgeW / 2 + offsetX,
                y: rect.maxY - badgeH - 8,
                width: badgeW,
                height: badgeH
            )
        }
    }

    private func animateContentLayout() {
        let p = contentPadding
        let targetSidebarWidth: CGFloat = sidebar.isExpanded ? SidebarView.expandedWidth : 0
        let targetContentRect = contentRect(forSidebarWidth: targetSidebarWidth)

        let targetStatusBarX: CGFloat
        let targetStatusBarW: CGFloat
        if useSidebar && targetSidebarWidth > 0 {
            targetStatusBarX = p + targetSidebarWidth + sidebarGap
            targetStatusBarW = bounds.width - targetStatusBarX - p
        } else {
            targetStatusBarX = p
            targetStatusBarW = bounds.width - p * 2
        }

        isAnimatingLayout = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Theme.animSlow
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            ctx.allowsImplicitAnimation = true

            sidebar.animator().frame = NSRect(
                x: p, y: p,
                width: targetSidebarWidth,
                height: bounds.height - p * 2
            )

            statusBar.animator().frame = NSRect(
                x: targetStatusBarX, y: p,
                width: targetStatusBarW,
                height: statusBarHeight
            )

            if selectedTabIndex < tabs.count {
                tabs[selectedTabIndex].rootView.animator().frame = targetContentRect
            }
        }, completionHandler: { [weak self] in
            self?.isAnimatingLayout = false
        })
    }

    // MARK: - Theme

    private func applyFrameColor() {
        layer?.backgroundColor = Theme.colors.frame.cgColor
    }

    private func handleThemeChange() {
        applyFrameColor()
        sidebar.layer?.backgroundColor = Theme.surface.cgColor
        statusBar.refreshTheme()
        titleBar.refreshTheme()
        needsDisplay = true
    }

    // MARK: - Edge Hover Detection

    private func setupEdgeTracking() {
        if let existing = edgeTrackingArea { removeTrackingArea(existing) }
        let edgeRect = NSRect(x: 0, y: 0, width: 4, height: bounds.height)
        let area = NSTrackingArea(
            rect: edgeRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: ["zone": "edge"]
        )
        edgeTrackingArea = area
        addTrackingArea(area)
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
        case "focus left":
            navigatePane(.left)
        case "focus right":
            navigatePane(.right)
        case "focus up":
            navigatePane(.up)
        case "focus down":
            navigatePane(.down)
        case "sidebar":
            sidebar.toggle()
        case "tab bar", "tabbar":
            toggleTabMode()
        case "hud", "status":
            showHUD()
        case "zoom", "maximize":
            toggleZoom()
        case "equalize", "equal":
            equalizePanes()
        case "broadcast":
            toggleBroadcast()
        case "fullscreen":
            window?.toggleFullScreen(nil)
        case "reload", "reload config":
            reloadConfig()
        case "font+", "bigger":
            adjustFontSize(delta: 1)
        case "font-", "smaller":
            adjustFontSize(delta: -1)
        case "find", "search":
            showSearch()
        case "copy", "copyselection":
            copySelection()
        case "paste", "pasteclipboard":
            pasteClipboard()
        case "reopentab", "reopen":
            reopenClosedTab()
        case "clearbuffer", "clear":
            clearBuffer()
        case "close pane", "closepane":
            closePane()
        case "new window", "newwindow":
            NotificationCenter.default.post(name: .init("BellithCreateNewWindow"), object: nil)
        case "selectall", "select all":
            if let surface = activeSurface?.surface {
                let action = "select_all"
                action.withCString { ptr in
                    _ = ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
                }
            }
        // Smart panel commands
        case "processes", "process tree", "procs", "ps":
            createSmartTab(kind: .processTree)
        case "network", "connections", "netstat":
            createSmartTab(kind: .network)
        case "env", "environment":
            createSmartTab(kind: .environment)
        case "files", "file activity":
            createSmartTab(kind: .fileActivity)
        case "perf", "performance":
            createSmartTab(kind: .performance)
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
                if let theme = ThemeColors.allThemes.first(where: {
                    $0.name.lowercased() == cmd
                }) {
                    BellithSettings.shared.themeName = theme.name
                    ThemeManager.shared.apply(theme)
                } else {
                    Logger.ui.warning("Unknown command: \(text)")
                }
            }
        }
    }

    // MARK: - Search

    func showSearch(initialNeedle: String? = nil) {
        guard !isSearchVisible else { return }
        isSearchVisible = true

        let bar = SearchBarView()
        bar.onSearch = { [weak self] query in self?.performSearch(query) }
        bar.onNext = { [weak self] in self?.searchNext() }
        bar.onPrev = { [weak self] in self?.searchPrev() }
        bar.onDismiss = { [weak self] in
            self?.isSearchVisible = false
            self?.searchBar = nil
            if let surface = self?.activeSurface?.surface {
                let action = "close_surface_search"
                action.withCString { ptr in
                    _ = ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
                }
            }
            self?.window?.makeFirstResponder(self?.activeSurface)
        }

        searchBar = bar
        if let needle = initialNeedle { bar.setQuery(needle) }
        bar.show(in: self)
    }

    func hideSearch() {
        guard isSearchVisible else { return }
        searchBar?.hide()
    }

    private var searchTotal: Int = 0

    func updateSearchTotal(_ total: Int) {
        searchTotal = total
        searchBar?.updateCount(selected: 0, total: total)
    }

    func updateSearchSelected(_ selected: Int) {
        searchBar?.updateCount(selected: selected, total: searchTotal)
    }

    private func performSearch(_ query: String) {
        guard let surface = activeSurface?.surface else { return }
        let action = "search_forward:\(query)"
        _ = action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }

    private func searchNext() {
        guard let surface = activeSurface?.surface else { return }
        let action = "search_forward"
        _ = action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }

    private func searchPrev() {
        guard let surface = activeSurface?.surface else { return }
        let action = "search_backward"
        _ = action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
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

    // MARK: - Link Preview

    func showLinkPreview(_ url: String) {
        // TODO: implement link preview tooltip
    }

    func hideLinkPreview() {
        // TODO: hide link preview tooltip
    }

    // MARK: - Font Size

    func adjustFontSizePublic(delta: Int) { adjustFontSize(delta: delta) }
    func resetFontSizePublic() { resetFontSize() }

    private func adjustFontSize(delta: Int) {
        let settings = BellithSettings.shared
        let newSize = max(8, min(36, settings.fontSize + delta))
        guard newSize != settings.fontSize else { return }
        settings.fontSize = newSize
        reloadConfig()
    }

    private func resetFontSize() {
        BellithSettings.shared.fontSize = 15
        reloadConfig()
    }

    // MARK: - Config Reload

    func reloadConfig() {
        guard let terminalApp = terminalApp, let app = terminalApp.app else { return }
        let config = TerminalConfig()
        guard let newConfig = config.config else { return }
        ghostty_app_update_config(app, newConfig)
    }

    // MARK: - Scrollbar

    func updateScrollbar(total: UInt64, offset: UInt64, visible: UInt64) {
        // TODO: implement scrollbar overlay
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

    // MARK: - Session Save / Restore

    func saveSession() -> SessionState {
        let tabStates = tabs.compactMap { tab -> SessionState.TabState? in
            guard let root = tab.splitRoot else { return nil }
            let tree = root.serialize { view in
                (view as? TerminalSurfaceView)?.currentCwd
            }
            return SessionState.TabState(title: tab.title, splitTree: tree)
        }
        return SessionState(tabs: tabStates, selectedTabIndex: min(selectedTabIndex, max(tabStates.count - 1, 0)))
    }

    func restoreSession(_ state: SessionState) {
        guard let terminalApp else { return }

        for tab in tabs {
            tab.rootView.removeFromSuperview()
        }
        tabs.removeAll()

        for tabState in state.tabs {
            var surfaces: [TerminalSurfaceView] = []
            let id = UUID()
            let splitRoot = buildSplitTree(tabState.splitTree, tabId: id, app: terminalApp, surfaces: &surfaces, depth: 0)

            // Validate: at least one surface must have initialized successfully
            let validSurfaces = surfaces.filter { $0.isReady }
            guard !validSurfaces.isEmpty else {
                Logger.app.warning("Session restore: skipping tab '\(tabState.title)' — no valid surfaces")
                splitRoot.removeFromSuperview()
                continue
            }

            var entry = TabEntry(
                id: id, title: tabState.title, cwd: nil,
                content: .terminal(splitRoot: splitRoot, surfaces: validSurfaces, focusedSurface: validSurfaces.first)
            )
            if let firstCwd = validSurfaces.first?.currentCwd {
                entry.cwd = firstCwd
            }
            tabs.append(entry)
            addSubview(splitRoot, positioned: .below, relativeTo: sidebar)
            splitRoot.isHidden = true
        }

        if tabs.isEmpty {
            createTab()
        }

        let idx = min(state.selectedTabIndex, tabs.count - 1)
        selectTab(max(idx, 0))
        refreshTabUI()
    }

    private static let maxSplitDepth = 8

    private func buildSplitTree(
        _ node: SplitNodeState,
        tabId: UUID,
        app: TerminalApp,
        surfaces: inout [TerminalSurfaceView],
        depth: Int
    ) -> SplitPaneView {
        switch node {
        case .leaf(let cwd):
            let surface = makeSurface(tabId: tabId, app: app)
            surface.currentCwd = cwd
            surfaces.append(surface)

            if let cwd, !cwd.isEmpty {
                sendCdWhenReady(surface: surface, cwd: cwd)
            }

            return SplitPaneView(content: surface)

        case .branch(let orientation, let ratio, let firstNode, let secondNode):
            // Depth limit to prevent pathological session data from stack overflow
            guard depth < Self.maxSplitDepth else {
                Logger.app.warning("Session restore: split depth limit reached, collapsing to leaf")
                let surface = makeSurface(tabId: tabId, app: app)
                surfaces.append(surface)
                return SplitPaneView(content: surface)
            }

            let ori: SplitPaneView.Orientation = orientation == "horizontal" ? .horizontal : .vertical
            let firstChild = buildSplitTree(firstNode, tabId: tabId, app: app, surfaces: &surfaces, depth: depth + 1)
            let secondChild = buildSplitTree(secondNode, tabId: tabId, app: app, surfaces: &surfaces, depth: depth + 1)
            return SplitPaneView.makeBranch(
                orientation: ori,
                ratio: CGFloat(ratio),
                first: firstChild,
                second: secondChild
            )
        }
    }

    // MARK: - Surface Factory

    /// Centralized surface creation — wires up all callbacks (onClose, onTextInserted).
    private func makeSurface(tabId: UUID, app: TerminalApp) -> TerminalSurfaceView {
        let surface = TerminalSurfaceView(app: app)
        surface.onClose = { [weak self, weak surface] _ in
            guard let self, let surface else { return }
            self.handleSurfaceClosed(id: tabId, surface: surface)
        }
        surface.onTextInserted = { [weak self] text, source in
            self?.broadcastText(text, from: source)
        }
        return surface
    }

    // MARK: - Session Restore Helpers

    /// Send a `cd` command to a surface once the shell is ready, with exponential backoff.
    private func sendCdWhenReady(surface: TerminalSurfaceView, cwd: String, attempt: Int = 0) {
        let maxAttempts = 5
        let delay = 0.05 * pow(2.0, Double(attempt))

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak surface] in
            guard let surface, let surf = surface.surface else { return }

            // If surface reports a CWD (shell has initialized) or we've exhausted retries, send the command
            if surface.currentCwd != nil || attempt >= maxAttempts {
                let escaped = cwd.replacingOccurrences(of: "'", with: "'\\''")
                let cmd = " cd '\(escaped)'\n"
                cmd.withCString { ptr in
                    ghostty_surface_text(surf, ptr, UInt(cmd.utf8.count))
                }
            } else {
                self?.sendCdWhenReady(surface: surface, cwd: cwd, attempt: attempt + 1)
            }
        }
    }
}

// MARK: - Broadcast Badge

// MARK: - Zoom Badge

private final class ZoomBadge: NSView {
    private let label = NSTextField(labelWithString: "ZOOMED")
    private let iconView = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = Theme.accent.withAlphaComponent(0.15).cgColor
        layer?.borderColor = Theme.accent.withAlphaComponent(0.3).cgColor
        layer?.borderWidth = 0.5

        iconView.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Zoomed")
        iconView.contentTintColor = Theme.accent
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = Theme.accent
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 8, y: (h - 10) / 2, width: 10, height: 10)
        label.frame = NSRect(x: 22, y: (h - 12) / 2, width: bounds.width - 28, height: 12)
    }
}

private final class BroadcastBadge: NSView {
    private let label = NSTextField(labelWithString: "BROADCAST")
    private let dotView = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = Theme.warning.withAlphaComponent(0.15).cgColor
        layer?.borderColor = Theme.warning.withAlphaComponent(0.3).cgColor
        layer?.borderWidth = 0.5

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3
        dotView.layer?.backgroundColor = Theme.warning.cgColor
        addSubview(dotView)

        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = Theme.warning
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        addSubview(label)

        // Pulse the dot
        startPulse()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        dotView.frame = NSRect(x: 10, y: (h - 6) / 2, width: 6, height: 6)
        label.frame = NSRect(x: 22, y: (h - 12) / 2, width: bounds.width - 30, height: 12)
    }

    private func startPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotView.layer?.add(pulse, forKey: "pulse")
    }
}
