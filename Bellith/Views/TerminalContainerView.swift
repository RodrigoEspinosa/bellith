import AppKit
import GhosttyKit
import QuartzCore
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
        case smart(String)
    }

    struct TabEntry {
        let id: UUID
        var title: String
        var cwd: String?
        var content: TabContent

        var kind: TabKind {
            switch content {
            case .terminal: return .terminal
            case .smart(let panel): return .smart(panel.pluginID)
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

    private(set) var isPaletteVisible = false
    private var isSearchVisible = false
    private var isClosingTab = false
    private var isClosingPane = false
    private var edgeTrackingArea: NSTrackingArea?
    private var themeObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var isAnimatingLayout = false
    private var isZoomed = false
    private var zoomedSurface: TerminalSurfaceView?
    private var isBroadcasting = false
    private var recentlyClosedTabs: [(title: String, cwd: String?)] = []
    private static let maxRecentlyClosed = 10
    private var zoomBadge: NSView?

    private let noiseLayer = CALayer()
    private let contentBackdropLayer = CALayer()
    private let contentStrokeLayer = CALayer()
    private let contentInnerStrokeLayer = CALayer()
    private let contentTopGlossLayer = CAGradientLayer()
    private let sidebarGlowLayer = CAGradientLayer()
    private let sidebarBridgeLayer = CAGradientLayer()

    init(terminalApp: TerminalApp) {
        self.terminalApp = terminalApp
        super.init(frame: .zero)
        wantsLayer = true
        applyFrameColor()
        configureChromeLayers()

        // Sidebar
        addSubview(sidebar)
        sidebar.onSelectTab = { [weak self] i in
            self?.selectTab(i)
            if !(self?.sidebar.isPinned ?? false) { self?.sidebar.hide() }
        }
        sidebar.onCloseTab = { [weak self] i in self?.closeTab(i) }
        sidebar.onNewTab = { [weak self] in self?.createTab() }
        sidebar.onExpandChanged = { [weak self] _ in
            self?.animateContentLayout()
            self?.syncTrafficLightDisplayMode()
        }
        sidebar.onReorderTab = { [weak self] from, to in self?.reorderTab(from: from, to: to) }
        sidebar.onTabContextMenu = { [weak self] index, point in self?.showTabContextMenu(index: index, at: point) }
        sidebar.onSelectTool = { [weak self] pluginID in self?.openOrSwitchToTool(pluginID) }

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

        settingsObserver = NotificationCenter.default.addObserver(
            forName: BellithSettings.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.applyFrameColor() }

        createTab()
    }

    deinit {
        teardown()
    }

    /// Explicitly release resources — call before dropping the last reference
    /// to break retain cycles and stop background work.
    func teardown() {
        // Remove observers
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
            self.themeObserver = nil
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
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

    /// 256×256 monochrome noise tile, generated once and shared across all instances.
    private static let noiseImage: CGImage? = {
        let size = 256
        let totalBytes = size * size
        var pixels = [UInt8](repeating: 0, count: totalBytes)
        for i in 0..<totalBytes {
            pixels[i] = UInt8.random(in: 0...255)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: size, height: size,
                  bitsPerComponent: 8, bitsPerPixel: 8,
                  bytesPerRow: size,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: 0),
                  provider: provider,
                  decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { return nil }
        return image
    }()

    private func configureChromeLayers() {
        guard let layer else { return }

        // Noise texture overlay (Zen-style grain)
        if let noiseImage = Self.noiseImage {
            let nsImage = NSImage(cgImage: noiseImage, size: NSSize(width: noiseImage.width, height: noiseImage.height))
            noiseLayer.backgroundColor = NSColor(patternImage: nsImage).cgColor
        }
        layer.addSublayer(noiseLayer)
        applyFrameColor()

        contentBackdropLayer.cornerCurve = .continuous
        contentBackdropLayer.shadowOpacity = 1
        contentBackdropLayer.shadowOffset = CGSize(width: 0, height: -2)

        contentStrokeLayer.backgroundColor = NSColor.clear.cgColor
        contentStrokeLayer.cornerCurve = .continuous
        contentInnerStrokeLayer.backgroundColor = NSColor.clear.cgColor
        contentInnerStrokeLayer.cornerCurve = .continuous
        contentInnerStrokeLayer.borderWidth = 1

        contentTopGlossLayer.startPoint = CGPoint(x: 0.5, y: 1)
        contentTopGlossLayer.endPoint = CGPoint(x: 0.5, y: 0)
        contentTopGlossLayer.cornerCurve = .continuous

        sidebarGlowLayer.startPoint = CGPoint(x: 0, y: 0.5)
        sidebarGlowLayer.endPoint = CGPoint(x: 1, y: 0.5)

        sidebarBridgeLayer.startPoint = CGPoint(x: 0, y: 0.5)
        sidebarBridgeLayer.endPoint = CGPoint(x: 1, y: 0.5)
        sidebarBridgeLayer.cornerRadius = 12
        sidebarBridgeLayer.cornerCurve = .continuous

        layer.addSublayer(contentBackdropLayer)
        layer.addSublayer(contentTopGlossLayer)
        layer.addSublayer(sidebarGlowLayer)
        layer.addSublayer(sidebarBridgeLayer)
        layer.addSublayer(contentStrokeLayer)
        layer.addSublayer(contentInnerStrokeLayer)

        applyChromeTheme()
        updateChromeFrames(animated: false)
    }

    private func applyChromeTheme() {
        contentBackdropLayer.backgroundColor = Theme.surface.cgColor
        contentBackdropLayer.shadowColor = NSColor.clear.cgColor
        contentBackdropLayer.shadowOpacity = 0
        contentBackdropLayer.shadowRadius = 0

        contentStrokeLayer.borderWidth = 0
        contentStrokeLayer.borderColor = NSColor.clear.cgColor

        contentInnerStrokeLayer.borderColor = NSColor.clear.cgColor
        contentInnerStrokeLayer.borderWidth = 0

        contentTopGlossLayer.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        contentTopGlossLayer.locations = [0, 1]

        sidebarGlowLayer.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        sidebarGlowLayer.locations = [0, 1]

        sidebarBridgeLayer.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        sidebarBridgeLayer.locations = [0, 1]
    }

    private func applyChrome(to root: NSView) {
        root.wantsLayer = true
        root.layer?.cornerRadius = contentRadius
        root.layer?.cornerCurve = .continuous
        root.layer?.maskedCorners = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner,
        ]
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 0
        root.layer?.borderColor = NSColor.clear.cgColor
        root.layer?.backgroundColor = Theme.surface.cgColor
    }

    private func updateChromeFrames(animated: Bool, sidebarWidth: CGFloat? = nil) {
        let resolvedSidebarWidth = sidebarWidth ?? ((useSidebar && sidebar.isExpanded) ? SidebarView.expandedWidth : 0)
        let rect = contentRect(forSidebarWidth: resolvedSidebarWidth)
        let hasVisibleContent = selectedTabIndex < tabs.count || (isZoomed && zoomedSurface != nil)
        let cornerMask: CACornerMask = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner,
        ]

        let updates = {
            let chromeRect = rect.insetBy(dx: -1, dy: -1)

            self.contentBackdropLayer.isHidden = !hasVisibleContent
            self.contentStrokeLayer.isHidden = !hasVisibleContent
            self.contentInnerStrokeLayer.isHidden = !hasVisibleContent
            self.contentTopGlossLayer.isHidden = !hasVisibleContent

            self.contentBackdropLayer.frame = chromeRect
            self.contentBackdropLayer.cornerRadius = self.contentRadius + 2
            self.contentBackdropLayer.maskedCorners = cornerMask

            self.contentStrokeLayer.frame = chromeRect
            self.contentStrokeLayer.cornerRadius = self.contentRadius + 2
            self.contentStrokeLayer.maskedCorners = cornerMask

            self.contentInnerStrokeLayer.frame = chromeRect.insetBy(dx: 1, dy: 1)
            self.contentInnerStrokeLayer.cornerRadius = self.contentRadius + 1
            self.contentInnerStrokeLayer.maskedCorners = cornerMask

            let glossHeight = min(72, max(40, chromeRect.height * 0.16))
            self.contentTopGlossLayer.frame = NSRect(
                x: chromeRect.minX,
                y: chromeRect.maxY - glossHeight,
                width: chromeRect.width,
                height: glossHeight
            )
            self.contentTopGlossLayer.cornerRadius = self.contentRadius + 2
            self.contentTopGlossLayer.maskedCorners = cornerMask

            let showsSidebarTransition = self.useSidebar && resolvedSidebarWidth > 0 && hasVisibleContent
            self.sidebarGlowLayer.isHidden = !showsSidebarTransition
            self.sidebarBridgeLayer.isHidden = !showsSidebarTransition

            if showsSidebarTransition {
                let glowRect = NSRect(
                    x: self.contentPadding + resolvedSidebarWidth - 6,
                    y: chromeRect.minY + 16,
                    width: self.sidebarGap + 24,
                    height: max(0, chromeRect.height - 32)
                )
                self.sidebarGlowLayer.frame = glowRect

                let bridgeHeight = min(168, max(112, chromeRect.height * 0.38))
                self.sidebarBridgeLayer.frame = NSRect(
                    x: glowRect.minX,
                    y: chromeRect.maxY - bridgeHeight - 6,
                    width: glowRect.width - 2,
                    height: bridgeHeight
                )
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(!(animated && !Theme.prefersReducedMotion))
        if animated && !Theme.prefersReducedMotion {
            CATransaction.setAnimationDuration(Theme.animSlow)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1))
        }
        updates()
        CATransaction.commit()
    }

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

                // Reset border properties (used only for broadcast mode)
                leaf.layer?.borderColor = nil
                leaf.layer?.borderWidth = 0
                leaf.layer?.cornerRadius = 0

                if isBroadcasting && hasSplits {
                    // Broadcast mode: full border on all panes
                    leaf.layer?.borderColor = Theme.accent.withAlphaComponent(0.6).cgColor
                    leaf.layer?.borderWidth = 1.5
                    leaf.layer?.cornerRadius = 4
                }

                let existingIndicator = leaf.layer?.sublayers?.first { $0.name == "focusIndicator" }
                let shouldShow = hasSplits && surface === activeSurface && !isBroadcasting

                if shouldShow {
                    let margin: CGFloat = 6
                    let targetFrame = CGRect(
                        x: margin,
                        y: leaf.bounds.height - 2.5,
                        width: leaf.bounds.width - margin * 2,
                        height: 2.5
                    )
                    if let existing = existingIndicator {
                        // Update position of existing indicator
                        existing.frame = targetFrame
                    } else {
                        // Add new indicator with fade-in
                        let indicator = CALayer()
                        indicator.name = "focusIndicator"
                        indicator.backgroundColor = Theme.accent.withAlphaComponent(0.7).cgColor
                        indicator.cornerRadius = 1.25
                        indicator.frame = targetFrame
                        indicator.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
                        indicator.opacity = 0
                        leaf.layer?.addSublayer(indicator)

                        let fadeIn = CABasicAnimation(keyPath: "opacity")
                        fadeIn.fromValue = 0
                        fadeIn.toValue = 1
                        fadeIn.duration = Theme.animFast
                        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        indicator.add(fadeIn, forKey: "fadeIn")
                        indicator.opacity = 1
                    }
                } else if let existing = existingIndicator {
                    // Fade out and remove
                    let fadeOut = CABasicAnimation(keyPath: "opacity")
                    fadeOut.fromValue = existing.presentation()?.opacity ?? 1
                    fadeOut.toValue = 0
                    fadeOut.duration = Theme.animFast
                    fadeOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    fadeOut.isRemovedOnCompletion = false
                    fadeOut.fillMode = .forwards
                    existing.add(fadeOut, forKey: "fadeOut")

                    DispatchQueue.main.asyncAfter(deadline: .now() + Theme.animFast) {
                        existing.removeFromSuperlayer()
                    }
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
        syncTrafficLightDisplayMode()
        updateChromeFrames(animated: false)
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
            NotificationCenter.default.post(name: .bellithCreateNewWindow, object: nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Tab Management

    @discardableResult
    func createTab(initialWorkingDirectory: String? = nil) -> TerminalSurfaceView? {
        guard let terminalApp else { return nil }

        let id = UUID()
        let surface = makeSurface(tabId: id, app: terminalApp)

        let splitRoot = SplitPaneView(content: surface)
        let initialCwd = (initialWorkingDirectory?.isEmpty == false)
            ? initialWorkingDirectory ?? FileManager.default.currentDirectoryPath
            : FileManager.default.currentDirectoryPath
        tabs.append(TabEntry(
            id: id, title: (initialCwd as NSString).lastPathComponent, cwd: initialCwd,
            content: .terminal(splitRoot: splitRoot, surfaces: [surface], focusedSurface: surface)
        ))
        addSubview(splitRoot, positioned: .below, relativeTo: sidebar)

        selectTab(tabs.count - 1)
        refreshTabUI()

        if initialWorkingDirectory?.isEmpty == false {
            openWorkingDirectory(initialCwd, in: surface)
        } else {
            statusBar.updateCwd(initialCwd)
            titleBar.updatePath(initialCwd)
            titleBar.updateGitBranch(nil)
            titleBar.updateProcess(nil)
            refreshStatusBarAsync(cwd: initialCwd)
        }

        return surface
    }

    // MARK: - Smart Tab Management

    func createSmartTab(pluginID: String) {
        guard let plugin = SmartPanelRegistry.shared.plugin(for: pluginID),
              let panel = SmartPanelView.create(pluginID: pluginID) else { return }

        // Find the shell PID from the current terminal's CWD
        panel.shellPID = findShellPID()

        let id = UUID()
        tabs.append(TabEntry(
            id: id, title: plugin.title, cwd: nil,
            content: .smart(panel: panel)
        ))
        addSubview(panel, positioned: .below, relativeTo: sidebar)

        selectTab(tabs.count - 1)
        refreshTabUI()
    }

    /// Open a tool panel, or switch to an existing one with the same plugin identifier.
    func openOrSwitchToTool(_ pluginID: String) {
        if let existingIndex = tabs.firstIndex(where: {
            if case .smart(let panel) = $0.content, panel.pluginID == pluginID { return true }
            return false
        }) {
            selectTab(existingIndex)
            return
        }
        createSmartTab(pluginID: pluginID)
    }

    func closeTab(_ index: Int) {
        guard index < tabs.count, !isClosingTab else { return }
        isClosingTab = true

        let entry = tabs[index]
        let tabId = entry.id

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

        // Fade out + subtle scale-down when closing a tab
        let rootView = entry.rootView
        rootView.wantsLayer = true
        Theme.animate(duration: Theme.animFast, timing: CAMediaTimingFunction(name: .easeIn), { _ in
            rootView.animator().alphaValue = 0
            if !Theme.prefersReducedMotion {
                rootView.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.98, y: 0.98))
            }
        }, completion: { [weak self] in
            guard let self else { return }
            rootView.removeFromSuperview()
            rootView.alphaValue = 1
            rootView.layer?.setAffineTransform(.identity)
            self.isClosingTab = false

            // Re-resolve index by tab ID in case array changed during animation
            guard let resolvedIndex = self.tabs.firstIndex(where: { $0.id == tabId }) else { return }
            self.tabs.remove(at: resolvedIndex)

            if self.tabs.isEmpty {
                DispatchQueue.main.async { [weak self] in self?.window?.close() }
                return
            }

            if self.selectedTabIndex >= self.tabs.count {
                self.selectedTabIndex = self.tabs.count - 1
            }
            self.selectTab(self.selectedTabIndex)
            self.refreshTabUI()
        })
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

        let previousIndex = selectedTabIndex

        if previousIndex < tabs.count {
            if case .smart(let panel) = tabs[previousIndex].content {
                panel.stopRefreshing()
            }
            tabs[previousIndex].rootView.isHidden = true
        }

        selectedTabIndex = index

        let entry = tabs[selectedTabIndex]
        let root = entry.rootView
        root.isHidden = false
        root.frame = contentRect
        applyChrome(to: root)

        // Subtle fade-in when switching between tabs
        if previousIndex != index && previousIndex < tabs.count {
            root.alphaValue = 0
            if !Theme.prefersReducedMotion {
                root.layer?.setAffineTransform(CGAffineTransform(translationX: useSidebar ? 10 : 6, y: 0).scaledBy(x: 0.992, y: 0.992))
            }
            Theme.animate(duration: Theme.animMedium, timing: CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)) { _ in
                root.animator().alphaValue = 1
                root.layer?.setAffineTransform(.identity)
            }
        } else {
            root.alphaValue = 1
            root.layer?.setAffineTransform(.identity)
        }

        switch entry.content {
        case .terminal:
            let focusSurface = entry.focusedSurface ?? entry.surfaces.first
            window?.makeFirstResponder(focusSurface)
            updateFocusIndicator()
            focusSurface?.refreshReportedSize()
            titleBar.updatePath(entry.cwd)
            if let cwd = entry.cwd {
                titleBar.updateGitBranch(nil)
                titleBar.updateProcess(nil)
                statusBar.updateCwd(cwd)
                statusBar.updateGitBranch(nil)
                statusBar.updateProcess(nil)
                refreshStatusBarAsync(cwd: cwd)
            } else {
                titleBar.updateGitBranch(nil)
                titleBar.updateProcess(nil)
                statusBar.clear()
            }
            sidebar.setActiveToolID(nil)
        case .smart(let panel):
            panel.startRefreshing()
            window?.makeFirstResponder(self)
            titleBar.updatePath(nil)
            titleBar.updateGitBranch(nil)
            titleBar.updateProcess(nil)
            titleBar.clearSize()
            statusBar.clear()
            sidebar.setActiveToolID(panel.pluginID)
        }

        updateChromeFrames(animated: previousIndex != index)
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
                titleBar.updatePath(cwd)
                titleBar.updateGitBranch(nil)
                titleBar.updateProcess(nil)
                statusBar.updateCwd(cwd)
                statusBar.updateGitBranch(nil)
                statusBar.updateProcess(nil)
                refreshStatusBarAsync(cwd: cwd)
            }
        }
    }

    /// Fetch shell context off the main thread.
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
                guard let self,
                      self.selectedTabIndex < self.tabs.count,
                      self.tabs[self.selectedTabIndex].cwd == cwd else { return }
                self.titleBar.updateGitBranch(branch)
                self.titleBar.updateProcess(foregroundProcess)
                self.statusBar.updateCwd(cwd)
                self.statusBar.updateGitBranch(branch)
                self.statusBar.updateProcess(foregroundProcess)
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

        let newLeaf: SplitPaneView
        if let focused = activeSurface, let leaf = root.leaf(containing: focused) {
            newLeaf = leaf.split(orientation: direction, newContent: surface)
        } else {
            newLeaf = root.split(orientation: direction, newContent: surface)
        }

        tabs[selectedTabIndex].addSurface(surface)
        window?.makeFirstResponder(surface)

        // Fade in the new pane while animating the split layout
        newLeaf.alphaValue = 0
        needsLayout = true
        layoutSubtreeIfNeeded()
        root.animateLayout(duration: Theme.animMedium)

        Theme.animate(duration: Theme.animMedium) { _ in
            newLeaf.animator().alphaValue = 1
        }

        updateFocusIndicator()
    }

    func closePane() {
        guard !isClosingPane, selectedTabIndex < tabs.count, tabs[selectedTabIndex].isTerminal else { return }
        let entry = tabs[selectedTabIndex]
        let tabId = entry.id

        guard entry.surfaces.count > 1, let focused = activeSurface else {
            closeCurrentTab()
            return
        }

        guard let root = entry.splitRoot else { return }

        if let leaf = root.leaf(containing: focused),
           let parent = root.parent(of: leaf) {
            focused.onClose = nil
            isClosingPane = true

            // Fade out the closing pane, then collapse the tree
            Theme.animate(duration: Theme.animFast, timing: CAMediaTimingFunction(name: .easeIn), { _ in
                leaf.animator().alphaValue = 0
            }, completion: { [weak self] in
                guard let self else { return }
                self.isClosingPane = false
                leaf.alphaValue = 1

                // Re-resolve the tab index in case tabs changed during animation
                guard let idx = self.tabs.firstIndex(where: { $0.id == tabId }),
                      idx == self.selectedTabIndex else { return }

                parent.removeChild(leaf)
                self.tabs[idx].removeSurface(focused)
                let newFocus = self.tabs[idx].focusedSurface
                self.window?.makeFirstResponder(newFocus)

                // Animate the remaining pane expanding into the freed space
                root.animateLayout(duration: Theme.animMedium)
                self.updateFocusIndicator()
            })
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
        root.resizeFromLeaf(containing: current, direction: direction, delta: 0.05, animated: true)
    }

    // MARK: - Zoom

    private func toggleZoom() {
        guard selectedTabIndex < tabs.count, tabs[selectedTabIndex].isTerminal else { return }
        let entry = tabs[selectedTabIndex]
        guard entry.surfaces.count > 1 else { return }

        if isZoomed {
            // Unzoom: fade out the zoomed surface, show split tree
            let tabId = entry.id
            if let surface = zoomedSurface {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = Theme.animFast
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    surface.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    guard let self else { return }
                    surface.removeFromSuperview()
                    surface.alphaValue = 1

                    // Verify the tab still exists before manipulating its split root
                    guard let idx = self.tabs.firstIndex(where: { $0.id == tabId }),
                          let splitRoot = self.tabs[idx].splitRoot else { return }
                    splitRoot.isHidden = false
                    splitRoot.alphaValue = 0
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = Theme.animFast
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        splitRoot.animator().alphaValue = 1
                    }
                    self.needsLayout = true
                    self.updateFocusIndicator()
                })
            }
            isZoomed = false
            zoomedSurface = nil
            updateZoomBadge()
        } else {
            guard let focused = activeSurface else { return }
            isZoomed = true
            zoomedSurface = focused

            // Zoom in: cross-fade from split tree to zoomed surface
            entry.splitRoot?.isHidden = true
            addSubview(focused, positioned: .below, relativeTo: commandPalette ?? searchBar)
            focused.frame = contentRect
            focused.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Theme.animFast
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                focused.animator().alphaValue = 1
            }
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
        guard let index = sender.representedObject as? Int,
              let session = sessionState(forTabAt: index) else { return }
        NotificationCenter.default.post(name: .bellithCreateNewWindow, object: WindowLaunchRequest(session: session))
        closeTab(index)
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

                // Fade out the closing pane, then collapse
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = Theme.animFast
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    leaf.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    guard let self else { return }
                    leaf.alphaValue = 1

                    // Re-resolve tab index by ID in case tabs changed during animation
                    guard let currentIdx = self.tabs.firstIndex(where: { $0.id == id }) else { return }
                    parent.removeChild(leaf)
                    self.tabs[currentIdx].removeSurface(surface)
                    if currentIdx == self.selectedTabIndex {
                        self.window?.makeFirstResponder(self.tabs[currentIdx].focusedSurface)
                        root.animateLayout(duration: Theme.animMedium)
                        self.updateFocusIndicator()
                    }
                })
            }
        }
    }

    // MARK: - Layout

    private let contentPadding: CGFloat = 8
    private let contentRadius: CGFloat = 13
    private let sidebarGap: CGFloat = 8
    private let tabBarHeight: CGFloat = 36
    private let statusBarHeight: CGFloat = 0
    private let titleBarHeight: CGFloat = 34

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncTrafficLightDisplayMode()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        noiseLayer.frame = bounds
        CATransaction.commit()
        guard !isAnimatingLayout else { return }

        let p = contentPadding

        let sidebarWidth: CGFloat = sidebar.isExpanded ? SidebarView.expandedWidth : 0
        sidebar.frame = NSRect(
            x: p, y: p,
            width: sidebarWidth,
            height: bounds.height - p * 2
        )
        sidebar.wantsLayer = true
        sidebar.layer?.cornerCurve = .continuous
        sidebar.layer?.cornerRadius = 0

        if !useSidebar {
            let tabBarX: CGFloat = 84
            tabBar.frame = NSRect(
                x: tabBarX,
                y: bounds.height - p - titleBarHeight - tabBarHeight + 3,
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
        let hasVisibleTrafficLights = !useSidebar
        titleBar.leadingInset = hasVisibleTrafficLights ? 92 : 0
        titleBar.isHidden = false
        titleBar.frame = NSRect(
            x: contentLeft + 6,
            y: bounds.height - p - titleBarHeight + 1,
            width: bounds.width - contentLeft - p - 10,
            height: titleBarHeight
        )

        statusBar.isHidden = true
        statusBar.frame = NSRect(
            x: contentLeft,
            y: p,
            width: bounds.width - contentLeft - p,
            height: statusBarHeight
        )

        let rect = contentRect
        if selectedTabIndex < tabs.count {
            let root = tabs[selectedTabIndex].rootView
            root.frame = rect
            applyChrome(to: root)
        }

        updateChromeFrames(animated: false)

        // Keep zoomed surface in sync with content rect
        if isZoomed, let surface = zoomedSurface {
            surface.frame = rect
        }

        setupEdgeTracking()
        syncTrafficLightDisplayMode()

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

        // Calculate target positions for all elements that shift with the sidebar
        let targetContentLeft: CGFloat
        if useSidebar && targetSidebarWidth > 0 {
            targetContentLeft = p + targetSidebarWidth + sidebarGap
        } else {
            targetContentLeft = p
        }

        let targetStatusBarX = targetContentLeft
        let targetStatusBarW = bounds.width - targetStatusBarX - p

        let targetTitleBarX = targetContentLeft + 6
        let targetTitleBarY = bounds.height - p - titleBarHeight + 1
        let targetTitleBarW = bounds.width - targetContentLeft - p - 10

        isAnimatingLayout = true
        let springTiming = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        Theme.animate(duration: Theme.animSlow, timing: springTiming, { ctx in
            ctx.allowsImplicitAnimation = true

            self.updateChromeFrames(animated: true, sidebarWidth: targetSidebarWidth)

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

            titleBar.animator().frame = NSRect(
                x: targetTitleBarX,
                y: targetTitleBarY,
                width: targetTitleBarW,
                height: titleBarHeight
            )

            if selectedTabIndex < tabs.count {
                let root = tabs[selectedTabIndex].rootView
                root.animator().frame = targetContentRect
            }

            // Also animate zoomed surface if active
            if isZoomed, let surface = zoomedSurface {
                surface.animator().frame = targetContentRect
            }
        }, completion: { [weak self] in
            self?.isAnimatingLayout = false
            self?.needsLayout = true
        })
    }

    // MARK: - Theme

    private func applyFrameColor() {
        layer?.backgroundColor = Theme.colors.frame.cgColor
        // Slider 0–1 maps to 0–0.08 (dark) or 0–0.12 (light) actual opacity
        let maxOpacity: Double = Theme.colors.isLight ? 0.12 : 0.08
        noiseLayer.opacity = Float(BellithSettings.shared.noiseIntensity * maxOpacity)
    }

    private func handleThemeChange() {
        applyFrameColor()
        applyChromeTheme()
        sidebar.refreshTheme()
        tabBar.refreshTheme()
        statusBar.refreshTheme()
        titleBar.refreshTheme()
        commandPalette?.refreshTheme()
        searchBar?.refreshTheme()
        for tab in tabs {
            tab.splitRoot?.refreshTheme()
            applyChrome(to: tab.rootView)
        }
        (zoomBadge as? ZoomBadge)?.refreshTheme()
        (broadcastBadge as? BroadcastBadge)?.refreshTheme()
        updateChromeFrames(animated: false)
        reloadConfig()
        terminalApp?.setColorScheme(Theme.colors.isLight ? GHOSTTY_COLOR_SCHEME_LIGHT : GHOSTTY_COLOR_SCHEME_DARK)
        needsDisplay = true
    }

    private func syncTrafficLightDisplayMode() {
        guard let window = window as? TerminalWindow else { return }

        if useSidebar {
            let mode: TerminalWindow.TrafficLightDisplayMode = sidebar.isExpanded ? .forcedVisible : .forcedHidden
            window.setTrafficLightDisplayMode(mode)
        } else {
            window.setTrafficLightDisplayMode(.automatic)
        }
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
        let cmd = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let command = CommandRegistry.shared.command(matching: cmd) {
            _ = command.perform(self, cmd)
            return
        }

        if cmd.hasPrefix(">") {
            let shellCmd = String(cmd.dropFirst()).trimmingCharacters(in: .whitespaces)
            if !shellCmd.isEmpty, let surface = activeSurface?.surface {
                let input = shellCmd + "\n"
                input.withCString { ptr in
                    ghostty_surface_text(surface, ptr, UInt(input.utf8.count))
                }
            }
            return
        }

        let normalizedThemeName = cmd.lowercased()
        if let theme = ThemeColors.allThemes.first(where: { $0.name.lowercased() == normalizedThemeName }) {
            if theme.isLight {
                BellithSettings.shared.lightThemeName = theme.name
            } else {
                BellithSettings.shared.darkThemeName = theme.name
            }
            let resolved = BellithSettings.shared.resolvedTheme
            ThemeManager.shared.apply(resolved)
        } else {
            Logger.ui.warning("Unknown command: \(text)")
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

    func toggleSidebarVisibility() { sidebar.toggle() }

    func focusPane(_ direction: SplitPaneView.Direction) { navigatePane(direction) }

    func togglePaneZoom() { toggleZoom() }

    func equalizeAllPanes() { equalizePanes() }

    func toggleBroadcastMode() { toggleBroadcast() }

    func toggleFullscreenMode() { window?.toggleFullScreen(nil) }

    func openNewWindow() {
        NotificationCenter.default.post(name: .bellithCreateNewWindow, object: nil)
    }

    func selectAllText() {
        if let surface = activeSurface?.surface {
            let action = "select_all"
            action.withCString { ptr in
                _ = ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
            }
        }
    }

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

    // MARK: - Session Save / Restore

    func saveSession() -> SessionState {
        let tabStates = tabs.compactMap { tab -> SessionState.TabState? in
            switch tab.content {
            case .terminal(let root, _, _):
                let tree = root.serialize { view in
                    (view as? TerminalSurfaceView)?.currentCwd
                }
                return SessionState.TabState(title: tab.title, splitTree: tree)
            case .smart(let panel):
                return SessionState.TabState(title: tab.title, smartPanelID: panel.pluginID)
            }
        }
        return SessionState(tabs: tabStates, selectedTabIndex: min(selectedTabIndex, max(tabStates.count - 1, 0)))
    }

    func sessionState(forTabAt index: Int) -> SessionState? {
        guard index >= 0, index < tabs.count else { return nil }
        let tab = tabs[index]

        let tabState: SessionState.TabState
        switch tab.content {
        case .terminal(let root, _, _):
            let tree = root.serialize { view in
                (view as? TerminalSurfaceView)?.currentCwd
            }
            tabState = SessionState.TabState(title: tab.title, splitTree: tree)
        case .smart(let panel):
            tabState = SessionState.TabState(title: tab.title, smartPanelID: panel.pluginID)
        }

        return SessionState(tabs: [tabState], selectedTabIndex: 0)
    }

    func restoreSession(_ state: SessionState) {
        guard let terminalApp else { return }

        for tab in tabs {
            tab.rootView.removeFromSuperview()
        }
        tabs.removeAll()

        for tabState in state.tabs {
            let id = UUID()

            switch tabState.kind {
            case .terminal:
                guard let splitTree = tabState.splitTree else { continue }

                var surfaces: [TerminalSurfaceView] = []
                let splitRoot = buildSplitTree(splitTree, tabId: id, app: terminalApp, surfaces: &surfaces, depth: 0)

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

            case .smart:
                guard let pluginID = tabState.smartPanelID,
                      let panel = SmartPanelView.create(pluginID: pluginID) else { continue }
                let entry = TabEntry(
                    id: id, title: tabState.title, cwd: nil,
                    content: .smart(panel: panel)
                )
                tabs.append(entry)
                addSubview(panel, positioned: .below, relativeTo: sidebar)
                panel.isHidden = true
            }
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
        surface.onSizeChanged = { [weak self, weak surface] cols, rows in
            guard let self, let surface else { return }
            if self.activeSurface === surface {
                self.titleBar.updateSize(cols: cols, rows: rows)
                self.statusBar.updateSize(cols: cols, rows: rows)
            }
        }
        return surface
    }

    func openWorkingDirectory(_ cwd: String) {
        guard let surface = activeSurface else { return }
        openWorkingDirectory(cwd, in: surface)
    }

    private func openWorkingDirectory(_ cwd: String, in surface: TerminalSurfaceView) {
        surface.currentCwd = cwd
        if let idx = tabs.firstIndex(where: { $0.surfaces.contains(where: { $0 === surface }) }) {
            tabs[idx].cwd = cwd
            tabs[idx].title = (cwd as NSString).lastPathComponent
            if idx == selectedTabIndex {
                titleBar.updatePath(cwd)
                titleBar.updateGitBranch(nil)
                titleBar.updateProcess(nil)
                statusBar.updateCwd(cwd)
                statusBar.updateGitBranch(nil)
                statusBar.updateProcess(nil)
                refreshStatusBarAsync(cwd: cwd)
            }
            refreshTabUI()
        }
        sendCdWhenReady(surface: surface, cwd: cwd)
    }

    // MARK: - Session Restore Helpers

    /// Send a `cd` command to a surface once the shell is ready, with exponential backoff.
    private func sendCdWhenReady(surface: TerminalSurfaceView, cwd: String, attempt: Int = 0) {
        let maxAttempts = 5
        let delay = 0.05 * pow(2.0, Double(attempt))

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak surface] in
            guard let surface, let surf = surface.surface else { return }

            // If the shell has reported its cwd already, only send `cd` when needed.
            if let currentCwd = surface.currentCwd {
                guard currentCwd != cwd else { return }
                let escaped = cwd.replacingOccurrences(of: "'", with: "'\\''")
                let cmd = " cd '\(escaped)'\n"
                cmd.withCString { ptr in
                    ghostty_surface_text(surf, ptr, UInt(cmd.utf8.count))
                }
                return
            }

            if attempt >= maxAttempts {
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
        layer?.borderWidth = 0.5

        iconView.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Zoomed")
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        addSubview(label)

        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 8, y: (h - 10) / 2, width: 10, height: 10)
        label.frame = NSRect(x: 22, y: (h - 12) / 2, width: bounds.width - 28, height: 12)
    }

    func refreshTheme() {
        layer?.backgroundColor = Theme.accent.withAlphaComponent(0.15).cgColor
        layer?.borderColor = Theme.accent.withAlphaComponent(0.3).cgColor
        iconView.contentTintColor = Theme.accent
        label.textColor = Theme.accent
    }
}

private final class BroadcastBadge: NSView {
    private let label = NSTextField(labelWithString: "BROADCAST")
    private let dotView = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.borderWidth = 0.5

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3
        addSubview(dotView)

        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        addSubview(label)

        // Pulse the dot
        startPulse()
        refreshTheme()
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

    func refreshTheme() {
        layer?.backgroundColor = Theme.warning.withAlphaComponent(0.15).cgColor
        layer?.borderColor = Theme.warning.withAlphaComponent(0.3).cgColor
        dotView.layer?.backgroundColor = Theme.warning.cgColor
        label.textColor = Theme.warning
    }
}
