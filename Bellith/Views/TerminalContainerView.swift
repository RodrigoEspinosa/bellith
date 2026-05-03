import AppKit
import Combine
import GhosttyKit
import QuartzCore
import os

/// Container that hosts multiple terminal tabs (each with optional split panes),
/// smart inspector tabs, a sidebar or tab bar, and the command palette.
final class TerminalContainerView: NSView, TerminalOverlayControllerHost, TerminalSessionCoordinatorHost {
    private enum Metrics {
        static let runtimeRefreshInterval: TimeInterval = 1.0
        static let minimumFontSize: Int = 8
        static let maximumFontSize: Int = 36
    }

    typealias TabContent = TerminalTabContent
    typealias TabKind = TerminalTabKind
    typealias TabEntry = TerminalTabEntry

    private let dependencies: BellithDependencies
    private weak var terminalApp: TerminalApp?

    private var tabs: [TabEntry] = []
    private(set) var selectedTabIndex: Int = 0
    let sidebar: SidebarView
    let tabBar: TabBarView
    let statusBar: StatusBarView
    let titleBar: TitleBarView
    private lazy var overlayController = TerminalOverlayController(
        host: self,
        commandRegistry: dependencies.commandRegistry,
        settings: dependencies.settings
    )
    private lazy var sessionCoordinator = TerminalSessionCoordinator(host: self)

    var overlayContainerView: NSView { self }
    var overlayWindow: NSWindow? { window }
    var activeSurfaceForOverlay: TerminalSurfaceView? { activeSurface }
    var terminalTabHintsForOverlay: [ShortcutTabHint] {
        let terminalIndices = Self.shortcutSelectableTerminalTabIndices(for: tabs.map(\.kind))
        let highlightedIndex = toolContextTerminalIndex()

        return terminalIndices.prefix(9).enumerated().map { visibleIndex, tabIndex in
            ShortcutTabHint(
                shortcutDigit: visibleIndex + 1,
                title: tabs[tabIndex].title,
                isSelected: tabIndex == highlightedIndex
            )
        }
    }
    var isPaletteVisible: Bool { overlayController.isPaletteVisible }
    private var overlayReferenceView: NSView? { overlayController.presentedOverlayView }
    private var isClosingTab = false
    private var isClosingPane = false
    private var edgeTrackingArea: NSTrackingArea?
    private var isAnimatingLayout = false
    private var isZoomed = false
    private var zoomedSurface: TerminalSurfaceView?
    private var lastSelectedTerminalTabID: UUID?
    private var isBroadcasting = false
    private var recentlyClosedTabs: [(
        title: String,
        cwd: String?,
        context: TerminalContext?,
        localSessionBootstrap: SSHSessionBootstrap?,
        localSessionName: String?,
        scrollbackText: String?
    )] = []
    private static let maxRecentlyClosed = 10
    private var zoomBadge: NSView?
    private var commandFailureSuggestionView: CommandFailureSuggestionView?
    private var commandFailureSuggestion: CommandFailureSuggestion?
    private weak var commandFailureSuggestionSurface: TerminalSurfaceView?
    private var lastKnownStatusBarVisible = false
    private var observationCancellables = Set<AnyCancellable>()
    private var windowObservationCancellables = Set<AnyCancellable>()
    private var eventMonitorTokens: [Any] = []

    private let noiseLayer = CALayer()
    private let contentBackdropLayer = CALayer()
    private let contentStrokeLayer = CALayer()
    private let contentInnerStrokeLayer = CALayer()
    private let contentTopGlossLayer = CAGradientLayer()

    /// When this view is embedded inside `RebrandShellView`, all of its own
    /// chrome (title bar, sidebar rail, tab bar, status bar, decorative
    /// backdrop layers) is suppressed so the parent shell owns the visible
    /// chrome. The terminal session, splits, smart panels, and overlays still
    /// run from this view — only the chrome is yielded.
    var embedInRebrandShell: Bool = false {
        didSet {
            if embedInRebrandShell != oldValue { applyEmbeddedChromeVisibility() }
        }
    }

    /// Fires whenever tabs are added/removed/renamed/reordered, the selected
    /// tab changes, or split layout shifts. The rebrand shell observes this
    /// to drive its own chrome (title bar, workspace rail, status bar).
    var onEmbeddedStateChanged: (() -> Void)?

    /// Only terminal tabs land in the workspace rail — smart-panel tabs (file
    /// activity, process tree, etc.) get their own tools cluster eventually.
    var embeddedTabSummaries: [EmbeddedTabSummary] {
        tabs.enumerated().compactMap { (idx, entry) -> EmbeddedTabSummary? in
            if case .smart = entry.kind { return nil }
            return EmbeddedTabSummary(
                id: entry.id,
                title: Self.rebrandDisplayTitle(for: entry),
                paneCount: entry.surfaces.count,
                isSmart: false,
                sourceIndex: idx
            )
        }
    }
    var embeddedSelectedTabIndex: Int { selectedTabIndex }
    var embeddedActiveTabTitle: String? {
        guard selectedTabIndex < tabs.count else { return nil }
        return Self.rebrandDisplayTitle(for: tabs[selectedTabIndex])
    }
    var embeddedStatusSummary: EmbeddedStatusSummary? {
        guard selectedTabIndex < tabs.count else { return nil }
        let entry = tabs[selectedTabIndex]
        guard entry.isTerminal else { return nil }
        let surfaces = entry.surfaces
        let focused = entry.focusedSurface ?? surfaces.first
        let focusedIndex = focused.flatMap { surface in
            surfaces.firstIndex { $0 === surface }.map { $0 + 1 }
        } ?? 1
        return EmbeddedStatusSummary(
            muxName: entry.localSessionBootstrap?.rawValue,
            paneCount: max(1, surfaces.count),
            focusedPaneIndex: focusedIndex,
            cwdDisplay: Self.compactPath(focused?.currentCwd ?? entry.cwd),
            gitBranch: activeGitInfo?.branch,
            processDisplay: focused?.lastForegroundPresentation?.text,
            isBroadcasting: isBroadcasting
        )
    }

    private func applyEmbeddedChromeVisibility() {
        let hidden = embedInRebrandShell
        titleBar.isHidden = hidden
        statusBar.isHidden = hidden
        sidebar.isHidden = hidden
        tabBar.isHidden = hidden
        contentBackdropLayer.isHidden = hidden
        contentStrokeLayer.isHidden = hidden
        contentInnerStrokeLayer.isHidden = hidden
        contentTopGlossLayer.isHidden = hidden
        needsLayout = true
    }

    /// Internal — call from anywhere tab state mutates so the rebrand shell
    /// can refresh its chrome.
    func notifyEmbeddedStateChanged() {
        onEmbeddedStateChanged?()
    }

    private let sidebarGlowLayer = CAGradientLayer()
    private let sidebarBridgeLayer = CAGradientLayer()

    init(
        terminalApp: TerminalApp,
        createInitialTab: Bool = true,
        dependencies: BellithDependencies = .live
    ) {
        self.dependencies = dependencies
        self.terminalApp = terminalApp
        self.sidebar = SidebarView(
            settings: dependencies.settings,
            smartPanelRegistry: dependencies.smartPanelRegistry
        )
        self.tabBar = TabBarView(smartPanelRegistry: dependencies.smartPanelRegistry)
        self.statusBar = StatusBarView(settings: dependencies.settings)
        self.titleBar = TitleBarView(settings: dependencies.settings)
        super.init(frame: .zero)
        registerForDraggedTypes([TabDragPayload.pasteboardType])
        wantsLayer = true
        applyFrameColor()
        configureChromeLayers()

        // Sidebar
        addSubview(sidebar)
        sidebar.onSelectTab = { [weak self] i in
            self?.selectTab(i)
            self?.sidebar.hideAfterSelectionIfNeeded()
        }
        sidebar.onCloseTab = { [weak self] i in self?.closeTab(i) }
        sidebar.onNewTab = { [weak self] in self?.createTab() }
        sidebar.onExpandChanged = { [weak self] _ in
            self?.animateContentLayout()
            self?.syncTrafficLightDisplayMode()
        }
        sidebar.onReorderTab = { [weak self] from, to in self?.reorderTab(from: from, to: to) }
        sidebar.onTabContextMenu = { [weak self] index, point in self?.showTabContextMenu(index: index, at: point) }
        sidebar.onReceiveDraggedTab = { [weak self] payload, insertionIndex in
            self?.receiveDraggedTab(payload, insertionIndex: insertionIndex)
        }
        sidebar.onTearOffTab = { [weak self] tabID, screenPoint in
            self?.tearOffTab(tabID, dropScreenPoint: screenPoint)
        }
        sidebar.onSelectTool = { [weak self] pluginID in self?.openOrSwitchToTool(pluginID) }

        // Tab bar
        addSubview(tabBar)
        tabBar.onSelectTab = { [weak self] i in self?.selectTab(i) }
        tabBar.onCloseTab = { [weak self] i in self?.closeTab(i) }
        tabBar.onNewTab = { [weak self] in self?.createTab() }
        tabBar.onRenameTab = { [weak self] i in self?.promptRenameTab(at: i) }
        tabBar.onReorderTab = { [weak self] from, to in self?.reorderTab(from: from, to: to) }
        tabBar.onTogglePin = { [weak self] i in self?.togglePinTab(i) }
        tabBar.onReceiveDraggedTab = { [weak self] payload, insertionIndex in
            self?.receiveDraggedTab(payload, insertionIndex: insertionIndex)
        }
        tabBar.onTearOffTab = { [weak self] tabID, screenPoint in
            self?.tearOffTab(tabID, dropScreenPoint: screenPoint)
        }

        // Status bar (optional, shown beneath the terminal content)
        statusBar.onVisibilityChanged = { [weak self] visible in
            self?.handleStatusBarVisibilityChange(visible)
        }
        statusBar.onGitHubBadgeClicked = { [weak self] in
            guard let cwd = self?.currentTerminalCwd(),
                  let gh = GitHubService.ghPath() else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gh)
                process.arguments = ["browse"]
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
            }
        }
        addSubview(statusBar)

        // Title bar breadcrumbs (in the title area)
        addSubview(titleBar)

        applyTabMode()

        // Theme change observer
        NotificationCenter.default.publisher(for: ThemeManager.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleThemeChange()
            }
            .store(in: &observationCancellables)

        NotificationCenter.default.publisher(for: BellithSettings.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyFrameColor()
                self.statusBar.refreshTheme()
                self.titleBar.refreshTheme()
                self.handleStatusBarVisibilityChange(self.shouldShowStatusBar)
                self.applyTabMode()
                for tab in self.tabs {
                    self.applyChrome(to: tab.rootView)
                }
                self.needsLayout = true
                self.reloadConfig()
                if !self.dependencies.settings.errorFixSuggestionsEnabled || !self.dependencies.settings.shellIntegrationEnabled {
                    self.clearCommandFailureSuggestion()
                } else {
                    self.updateCommandFailureSuggestionVisibility()
                }
            }
            .store(in: &observationCancellables)

        Timer.publish(every: Metrics.runtimeRefreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshActiveRuntimeStatusIfNeeded()
            }
            .store(in: &observationCancellables)

        installEventMonitorsIfNeeded()
        if createInitialTab {
            createTab()
        }
    }

    deinit {
        removeEventMonitors()
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
        contentBackdropLayer.backgroundColor = activeProfileIsTranslucent
            ? NSColor.clear.cgColor
            : Theme.surface.cgColor
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
        root.layer?.cornerRadius = embedInRebrandShell ? RebrandTokens.Layout.paneCornerRadius : contentRadius
        root.layer?.cornerCurve = .continuous
        root.layer?.maskedCorners = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner,
        ]
        // Keep the outer rounded mask (for macOS-style window card) but don't
        // clip rigidly — the focused-pane decoration's shadow/glow must extend
        // outside the leaf when panes are split.
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = embedInRebrandShell ? 1 : 0
        root.layer?.borderColor = embedInRebrandShell
            ? RebrandTokens.Color.line.cgColor
            : NSColor.clear.cgColor
        if embedInRebrandShell {
            root.layer?.backgroundColor = RebrandTokens.Color.paneBg.cgColor
        } else if activeProfileIsTranslucent {
            root.layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            root.layer?.backgroundColor = Theme.surface.cgColor
        }
    }

    private var activeProfileIsTranslucent: Bool {
        dependencies.settings.backgroundOpacity < 1.0
    }

    private func updateChromeFrames(animated: Bool, sidebarWidth: CGFloat? = nil, statusBarVisible: Bool? = nil) {
        let resolvedSidebarWidth = sidebarWidth ?? ((useSidebar && sidebar.isExpanded) ? SidebarView.expandedWidth : 0)
        let resolvedStatusBarVisible = statusBarVisible ?? shouldShowStatusBar
        let rect = contentRect(forSidebarWidth: resolvedSidebarWidth, statusBarVisible: resolvedStatusBarVisible)
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

    private func refreshActiveRuntimeStatusIfNeeded() {
        guard shouldPollRuntimeStatus else { return }
        refreshActiveRuntimeStatusAsync()
    }

    private var shouldPollRuntimeStatus: Bool {
        guard let window else { return false }
        return Self.shouldPollRuntimeStatus(windowIsVisible: window.isVisible, isKeyWindow: window.isKeyWindow)
    }

    static func shouldPollRuntimeStatus(windowIsVisible: Bool, isKeyWindow: Bool) -> Bool {
        windowIsVisible && isKeyWindow
    }

    static func gitRepositoryInfo(in directory: String) -> GitRepositoryInfo? {
        TerminalRuntimeInfoService.gitRepositoryInfo(in: directory)
    }

    static func shortcutSelectableTerminalTabIndices(for tabKinds: [TerminalTabKind]) -> [Int] {
        tabKinds.enumerated().compactMap { index, kind in
            if case .terminal = kind {
                return index
            }
            return nil
        }
    }

    static func shortcutSelectableTerminalTabIndex(for digit: Int, tabKinds: [TerminalTabKind]) -> Int? {
        let terminalIndices = shortcutSelectableTerminalTabIndices(for: tabKinds)
        guard !terminalIndices.isEmpty else { return nil }
        let clampedPosition = min(max(digit - 1, 0), terminalIndices.count - 1)
        return terminalIndices[clampedPosition]
    }

    static func nextTerminalTabIndex(after current: Int, in tabKinds: [TerminalTabKind]) -> Int? {
        let terminalIndices = shortcutSelectableTerminalTabIndices(for: tabKinds)
        guard !terminalIndices.isEmpty else { return nil }
        return terminalIndices.first(where: { $0 > current }) ?? terminalIndices.first
    }

    static func previousTerminalTabIndex(before current: Int, in tabKinds: [TerminalTabKind]) -> Int? {
        let terminalIndices = shortcutSelectableTerminalTabIndices(for: tabKinds)
        guard !terminalIndices.isEmpty else { return nil }
        return terminalIndices.last(where: { $0 < current }) ?? terminalIndices.last
    }

    private func updateRuntimeStatusObservers() {
        windowObservationCancellables.removeAll()
        guard let window else { return }

        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: window)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshActiveRuntimeStatusIfNeeded()
            }
            .store(in: &windowObservationCancellables)

        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: window)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.overlayController.hideModifierHints()
            }
            .store(in: &windowObservationCancellables)

        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: window)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshActiveRuntimeStatusIfNeeded()
            }
            .store(in: &windowObservationCancellables)
    }

    private func installEventMonitorsIfNeeded() {
        guard eventMonitorTokens.isEmpty else { return }

        let token = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, event.window == self.window else { return event }

            switch event.type {
            case .flagsChanged:
                self.overlayController.handleModifierFlagsChanged(
                    event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                )
            case .keyDown:
                self.overlayController.handleKeyEventBegan()
                if self.handlePaneKeyEquivalent(event) {
                    return nil
                }
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                self.overlayController.handleKeyEventBegan()
            default:
                break
            }

            return event
        }

        eventMonitorTokens = [token]
    }

    private func handlePaneKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              selectedTabIndex < tabs.count,
              tabs[selectedTabIndex].isTerminal,
              dependencies.settings.legacyPaneSupport || dependencies.settings.useRebrandShell else {
            return false
        }

        if matches(event, action: "splitRight") || Self.matchesShortcut(event, key: "d", command: true) {
            splitPane(direction: .vertical)
            return true
        }
        if matches(event, action: "splitDown") || Self.matchesShortcut(event, key: "d", command: true, shift: true) {
            splitPane(direction: .horizontal)
            return true
        }
        if matches(event, action: "closePane") {
            closePane()
            return true
        }
        return false
    }

    private func removeEventMonitors() {
        eventMonitorTokens.forEach { NSEvent.removeMonitor($0) }
        eventMonitorTokens.removeAll()
    }

    // MARK: - Focus Indicator

    private func updateFocusIndicator() {
        guard selectedTabIndex < tabs.count else { return }
        let entry = tabs[selectedTabIndex]
        guard entry.isTerminal else { return }
        let hasSplits = entry.surfaces.count > 1

        for surface in entry.surfaces {
            if let root = entry.splitRoot, let leaf = root.leaf(containing: surface) {
                let state: PaneDecorationState
                if !hasSplits {
                    state = .hidden
                } else if isBroadcasting {
                    state = .broadcast
                } else if surface === activeSurface {
                    state = .active
                } else {
                    state = .inactive
                }
                applyPaneDecoration(to: leaf, state: state)
            }
        }

        refreshPaneHeaders()
    }

    private enum PaneDecorationState {
        case hidden
        case inactive
        case active
        case broadcast
    }

    private enum PaneDecoration {
        static let border = "paneBorder"
        static let glow = "paneGlow"
        // Border sits flush with the pane card (the PaneContainerView paints
        // its own card hairline at the same edge). The hairline is replaced
        // by the active border's color here when the pane is focused.
        static let inset: CGFloat = 0
        static let cornerRadius: CGFloat = 8
    }

    private func applyPaneDecoration(to leaf: NSView, state: PaneDecorationState) {
        leaf.wantsLayer = true
        leaf.layer?.borderColor = nil
        leaf.layer?.borderWidth = 0
        leaf.layer?.cornerRadius = 0
        leaf.layer?.masksToBounds = false

        guard let layer = leaf.layer else { return }
        let frame = leaf.bounds.insetBy(dx: PaneDecoration.inset, dy: PaneDecoration.inset)
        let borderLayer = paneDecorationLayer(
            named: PaneDecoration.border,
            on: layer,
            frame: frame
        )
        let glowLayer = paneDecorationLayer(
            named: PaneDecoration.glow,
            on: layer,
            frame: frame
        )

        borderLayer.cornerRadius = PaneDecoration.cornerRadius
        borderLayer.cornerCurve = .continuous
        borderLayer.backgroundColor = NSColor.clear.cgColor
        borderLayer.masksToBounds = false
        glowLayer.cornerRadius = PaneDecoration.cornerRadius
        glowLayer.cornerCurve = .continuous
        glowLayer.backgroundColor = NSColor.clear.cgColor
        glowLayer.borderWidth = 0

        switch state {
        case .hidden:
            borderLayer.opacity = 0
            glowLayer.opacity = 0
            glowLayer.shadowOpacity = 0

        case .inactive:
            borderLayer.opacity = 1
            borderLayer.borderWidth = 1
            borderLayer.borderColor = Theme.chromeHairline.withAlphaComponent(Theme.colors.isLight ? 0.32 : 0.24).cgColor
            glowLayer.opacity = 0
            glowLayer.shadowOpacity = 0

        case .active:
            let tint = activeWorkspaceTint()
            borderLayer.opacity = 1
            borderLayer.borderWidth = 1.5
            borderLayer.borderColor = tint.withAlphaComponent(0.34).cgColor
            glowLayer.opacity = 1
            glowLayer.shadowColor = tint.withAlphaComponent(0.12).cgColor
            glowLayer.shadowOpacity = 0.7
            glowLayer.shadowRadius = 10
            glowLayer.shadowOffset = .zero

        case .broadcast:
            // Broadcast keeps the global accent — it's a destructive/global mode
            // that shouldn't be tinted by workspace identity.
            borderLayer.opacity = 1
            borderLayer.borderWidth = 1.5
            borderLayer.borderColor = Theme.accent.withAlphaComponent(0.52).cgColor
            glowLayer.opacity = 1
            glowLayer.shadowColor = Theme.accent.withAlphaComponent(0.12).cgColor
            glowLayer.shadowOpacity = 1
            glowLayer.shadowRadius = 8
            glowLayer.shadowOffset = .zero
        }
    }

    private func activeWorkspaceTint() -> NSColor {
        guard selectedTabIndex < tabs.count else { return Theme.accent }
        return WorkspaceTint.accent(for: tabs[selectedTabIndex].title)
    }

    private func paneDecorationLayer(named name: String, on parent: CALayer, frame: CGRect) -> CALayer {
        if let existing = parent.sublayers?.first(where: { $0.name == name }) {
            existing.frame = frame
            return existing
        }

        let layer = CALayer()
        layer.name = name
        layer.frame = frame
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        parent.addSublayer(layer)
        return layer
    }

    // MARK: - Tab Mode

    private var useSidebar: Bool { dependencies.settings.tabMode == "sidebar" }

    func applyTabMode() {
        let isSidebar = useSidebar
        sidebar.isHidden = embedInRebrandShell ? true : !isSidebar
        tabBar.isHidden = embedInRebrandShell ? true : isSidebar
        syncTrafficLightDisplayMode()
        updateChromeFrames(animated: false)
        needsLayout = true
    }

    func toggleTabMode() {
        let s = dependencies.settings
        s.tabMode = s.tabMode == "sidebar" ? "tabbar" : "sidebar"
        applyTabMode()
    }

    // MARK: - Key Interception

    private func matches(_ event: NSEvent, action actionId: String) -> Bool {
        dependencies.settings.binding(for: actionId)?.matches(event: event) ?? false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = KeyShortcut.canonicalKey(from: event) ?? ""

        if mods == .command && (key == "q" || key == ",") { return super.performKeyEquivalent(with: event) }

        if overlayController.isSearchVisible {
            if matches(event, action: "dismissOverlay") { hideSearch(); return true }
            if matches(event, action: "searchNext") { overlayController.searchNextShortcut(); return true }
            if matches(event, action: "searchPrev") { overlayController.searchPrevShortcut(); return true }
        }

        if overlayController.isShortcutCheatSheetVisible,
           matches(event, action: "dismissOverlay") {
            hideShortcutCheatSheet()
            return true
        }

        if matches(event, action: "commandPalette") { toggleCommandPalette(); return true }
        if matches(event, action: "showKeyboardShortcuts") { toggleShortcutCheatSheet(); return true }
        if matches(event, action: "toggleSidebar") { sidebar.toggle(); return true }
        if matches(event, action: "newTab") { createTab(); return true }
        if matches(event, action: "closeTab") { closeFocusedPaneOrTab(); return true }
        if matches(event, action: "nextTab") { advanceToNextTerminalTab(); return true }
        if matches(event, action: "prevTab") { advanceToPreviousTerminalTab(); return true }

        if mods == .command, let digit = Int(key), digit >= 1 && digit <= 9 {
            if let tabIndex = Self.shortcutSelectableTerminalTabIndex(for: digit, tabKinds: tabs.map(\.kind)) {
                selectTab(tabIndex)
            }
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
        if matches(event, action: "renameTab") { promptRenameTab(); return true }
        if matches(event, action: "clearBuffer") { clearBuffer(); return true }
        if matches(event, action: "preferences") {
            SettingsNavigation.open(
                in: self,
                settings: dependencies.settings,
                preferencesWindowController: dependencies.preferencesWindowController
            )
            return true
        }

        if matches(event, action: "newWindow") {
            NotificationCenter.default.post(name: .bellithCreateNewWindow, object: nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Tab Management

    @discardableResult
    func createTab(
        initialWorkingDirectory: String? = nil,
        titleOverride: String? = nil,
        context: TerminalContext = .local,
        localSessionBootstrap overrideBootstrap: SSHSessionBootstrap? = nil,
        localSessionName overrideSessionName: String? = nil
    ) -> TerminalSurfaceView? {
        guard let terminalApp else { return nil }

        let id = UUID()
        let surface = makeSurface(tabId: id, app: terminalApp, context: context)
        let localSessionBootstrap = context.source == .local
            ? (overrideBootstrap ?? dependencies.settings.localSessionBootstrap)
            : .none
        let localSessionName = localSessionBootstrap == .none
            ? nil
            : (overrideSessionName ?? LocalSessionLaunchBuilder.makeSessionName())

        let splitRoot = SplitPaneView(content: makePaneContent(for: surface))
        let initialCwd = (initialWorkingDirectory?.isEmpty == false)
            ? initialWorkingDirectory ?? FileManager.default.currentDirectoryPath
            : FileManager.default.currentDirectoryPath
        tabs.append(TabEntry(
            id: id, title: titleOverride ?? (initialCwd as NSString).lastPathComponent, cwd: initialCwd,
            localSessionBootstrap: localSessionBootstrap == .none ? nil : localSessionBootstrap,
            localSessionName: localSessionName,
            content: .terminal(splitRoot: splitRoot, surfaces: [surface], focusedSurface: surface)
        ))
        addSubview(splitRoot, positioned: .below, relativeTo: sidebar)

        selectTab(tabs.count - 1)
        refreshTabUI()

        if let bootstrapCommand = LocalSessionLaunchBuilder.command(
            bootstrap: localSessionBootstrap,
            sessionName: localSessionName,
            workingDirectory: initialWorkingDirectory
        ) {
            sessionCoordinator.send(command: bootstrapCommand, to: surface)
            titleBar.updateContext(surface.displayContext)
            statusBar.updateContext(surface.displayContext)
            statusBar.updateCwd(initialCwd)
            titleBar.updatePath(initialCwd)
            titleBar.updateGitBranch(nil)
            titleBar.updateGitWorktree(nil)
            titleBar.updateProcess(nil)
            statusBar.updateGitBranch(nil)
            statusBar.updateGitWorktree(nil)
            statusBar.updateProcess(nil)
            refreshStatusBarAsync(cwd: initialCwd)
        } else if initialWorkingDirectory?.isEmpty == false {
            openWorkingDirectory(initialCwd, in: surface)
        } else {
            titleBar.updateContext(surface.displayContext)
            statusBar.updateContext(surface.displayContext)
            statusBar.updateCwd(initialCwd)
            titleBar.updatePath(initialCwd)
            titleBar.updateGitBranch(nil)
            titleBar.updateGitWorktree(nil)
            titleBar.updateProcess(nil)
            statusBar.updateGitBranch(nil)
            statusBar.updateGitWorktree(nil)
            statusBar.updateProcess(nil)
            refreshStatusBarAsync(cwd: initialCwd)
        }

        openReferencePaneLayoutIfNeeded()
        return surface
    }

    // MARK: - Smart Tab Management

    func createSmartTab(pluginID: String) {
        guard let plugin = dependencies.smartPanelRegistry.plugin(for: pluginID),
              let panel = makeSmartPanel(pluginID: pluginID) else { return }

        // Provide the shell PID and CWD so panels can scope their data.
        prepareSmartPanel(panel)

        let id = UUID()
        tabs.append(TabEntry(
            id: id, title: plugin.title, cwd: nil,
            content: .smart(panel: panel)
        ))
        addSubview(panel, positioned: .below, relativeTo: sidebar)

        selectTab(tabs.count - 1)
        refreshTabUI()
    }

    func makeSmartPanel(pluginID: String) -> SmartPanelView? {
        SmartPanelView.create(pluginID: pluginID, registry: dependencies.smartPanelRegistry)
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

    static func clampedDropInsertionIndex(
        requestedIndex: Int,
        movingPinned: Bool,
        pinnedCount: Int,
        tabCount: Int
    ) -> Int {
        let clampedIndex = max(0, min(requestedIndex, tabCount))
        if movingPinned {
            return min(clampedIndex, pinnedCount)
        }
        return max(clampedIndex, pinnedCount)
    }

    func detachTab(withID id: UUID) -> TabEntry? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }

        let entry = tabs.remove(at: index)
        if case .smart(let panel) = entry.content {
            panel.stopRefreshing()
        }
        entry.rootView.removeFromSuperview()
        entry.rootView.isHidden = true

        if lastSelectedTerminalTabID == id {
            lastSelectedTerminalTabID = tabs.first(where: \.isTerminal)?.id
        }

        if tabs.isEmpty {
            refreshTabUI()
            DispatchQueue.main.async { [weak self] in
                self?.window?.close()
            }
            return entry
        }

        if selectedTabIndex > index {
            selectedTabIndex -= 1
        } else if selectedTabIndex >= tabs.count {
            selectedTabIndex = tabs.count - 1
        }

        selectTab(selectedTabIndex)
        refreshTabUI()
        return entry
    }

    func insertTransferredTab(_ entry: TabEntry, at requestedIndex: Int?) {
        var transferredEntry = entry
        let insertIndex = Self.clampedDropInsertionIndex(
            requestedIndex: requestedIndex ?? tabs.count,
            movingPinned: transferredEntry.isPinned,
            pinnedCount: tabs.filter { $0.isPinned }.count,
            tabCount: tabs.count
        )

        if case .smart(let panel) = transferredEntry.content {
            prepareSmartPanel(panel)
        }
        for surface in transferredEntry.surfaces {
            bindSurfaceCallbacks(for: surface, tabId: transferredEntry.id)
        }

        transferredEntry.rootView.removeFromSuperview()
        transferredEntry.rootView.isHidden = true
        tabs.insert(transferredEntry, at: insertIndex)
        addSubview(transferredEntry.rootView, positioned: .below, relativeTo: sidebar)
        selectTab(insertIndex)
        refreshTabUI()
    }

    private func receiveDraggedTab(_ payload: TabDragPayload, insertionIndex: Int) {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let destinationWindowID = tabDragWindowID else { return }
        _ = appDelegate.moveTab(
            payload.tabID,
            fromWindowWithID: payload.sourceWindowID,
            toWindowWithID: destinationWindowID,
            insertionIndex: insertionIndex
        )
    }

    private func tearOffTab(_ tabID: UUID, dropScreenPoint: NSPoint) {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let sourceWindowID = tabDragWindowID else { return }
        _ = appDelegate.tearOffTab(tabID, fromWindowWithID: sourceWindowID, dropScreenPoint: dropScreenPoint)
    }

    private var tabDragWindowID: UUID? {
        (window as? TerminalWindow)?.tabDragIdentifier
    }

    private func prepareSmartPanel(_ panel: SmartPanelView) {
        panel.shellPID = findShellPID()
        panel.workingDirectory = currentTerminalCwd()
        panel.onRequestNewTab = { [weak self] directory in
            self?.createTab(initialWorkingDirectory: directory)
        }
    }

    /// Toggle the pinned state of a tab. Pinning moves the tab to the left of
    /// the first non-pinned tab; unpinning leaves it in place within the pin
    /// region, which becomes the first non-pinned slot.
    func togglePinTab(_ index: Int) {
        guard index >= 0, index < tabs.count else { return }
        tabs[index].isPinned.toggle()
        rebalancePinnedOrder()
        refreshTabUI()
    }

    /// Ensure pinned tabs are contiguous and leftmost without otherwise
    /// disturbing the relative order of tabs within the pinned and unpinned
    /// segments.
    private func rebalancePinnedOrder() {
        guard !tabs.isEmpty else { return }
        let selectedId = tabs.indices.contains(selectedTabIndex) ? tabs[selectedTabIndex].id : nil
        let pinned = tabs.filter { $0.isPinned }
        let unpinned = tabs.filter { !$0.isPinned }
        tabs = pinned + unpinned
        if let selectedId, let newIndex = tabs.firstIndex(where: { $0.id == selectedId }) {
            selectedTabIndex = newIndex
        }
    }

    func closeTab(_ index: Int) {
        guard index < tabs.count, !isClosingTab else { return }
        // Pinned tabs are protected from accidental close. Unpin first.
        if tabs[index].isPinned {
            NSSound.beep()
            return
        }
        isClosingTab = true

        let entry = tabs[index]
        let tabId = entry.id

        // Track for reopen
        if entry.isTerminal {
            recentlyClosedTabs.append((
                title: entry.title,
                cwd: entry.cwd,
                context: entry.persistedContext,
                localSessionBootstrap: entry.localSessionBootstrap,
                localSessionName: entry.localSessionName,
                scrollbackText: entry.focusedSurface?.readScreenText() ?? entry.surfaces.first?.readScreenText()
            ))
            if recentlyClosedTabs.count > Self.maxRecentlyClosed {
                recentlyClosedTabs.removeFirst()
            }
        }

        if case .smart(let panel) = entry.content {
            panel.stopRefreshing()
        }
        if entry.surfaces.contains(where: { $0 === commandFailureSuggestionSurface }) {
            clearCommandFailureSuggestion()
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
            if self.lastSelectedTerminalTabID == tabId {
                self.lastSelectedTerminalTabID = nil
            }

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

    func closeFocusedPaneOrTab() {
        guard selectedTabIndex < tabs.count else { return }
        let entry = tabs[selectedTabIndex]
        if entry.isTerminal, entry.surfaces.count > 1 {
            closePane()
        } else {
            closeCurrentTab()
        }
    }

    func reorderTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < tabs.count,
              destinationIndex >= 0, destinationIndex < tabs.count else { return }

        // Clamp destination so pinned tabs stay leftmost and unpinned tabs
        // stay to the right of the pinned block.
        let pinnedCount = tabs.filter { $0.isPinned }.count
        let movingPinned = tabs[sourceIndex].isPinned
        var clampedDestination = destinationIndex
        if movingPinned {
            clampedDestination = min(clampedDestination, max(0, pinnedCount - 1))
        } else {
            clampedDestination = max(clampedDestination, pinnedCount)
        }
        guard clampedDestination != sourceIndex else { return }

        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: clampedDestination)

        let destinationIndex = clampedDestination

        if selectedTabIndex == sourceIndex {
            selectedTabIndex = destinationIndex
        } else if sourceIndex < selectedTabIndex && destinationIndex >= selectedTabIndex {
            selectedTabIndex -= 1
        } else if sourceIndex > selectedTabIndex && destinationIndex <= selectedTabIndex {
            selectedTabIndex += 1
        }

        refreshTabUI()
    }

    func advanceToNextTerminalTab() {
        if let next = Self.nextTerminalTabIndex(after: selectedTabIndex, in: tabs.map(\.kind)) {
            selectTab(next)
        }
    }

    func advanceToPreviousTerminalTab() {
        if let prev = Self.previousTerminalTabIndex(before: selectedTabIndex, in: tabs.map(\.kind)) {
            selectTab(prev)
        }
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
        if entry.isTerminal {
            lastSelectedTerminalTabID = entry.id
        }
        updateSmartPanelContexts()

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
            let context = focusSurface?.displayContext ?? entry.visibleContext
            titleBar.updateContext(context)
            statusBar.updateContext(context)
            titleBar.updatePath(entry.cwd)
            if let cwd = entry.cwd {
                titleBar.updateGitBranch(nil)
                titleBar.updateGitWorktree(nil)
                titleBar.updateProcess(nil)
                statusBar.updateCwd(cwd)
                statusBar.updateGitBranch(nil)
                statusBar.updateGitWorktree(nil)
                statusBar.updateProcess(nil)
                refreshStatusBarAsync(cwd: cwd)
            } else {
                titleBar.updateGitBranch(nil)
                titleBar.updateGitWorktree(nil)
                titleBar.updateProcess(nil)
                statusBar.updateContext(context)
                statusBar.updateCwd(nil)
                statusBar.updateGitBranch(nil)
                statusBar.updateGitWorktree(nil)
                statusBar.updateProcess(nil)
            }
            sidebar.setActiveToolID(nil)
        case .smart(let panel):
            panel.startRefreshing()
            window?.makeFirstResponder(self)
            titleBar.updateContext(nil)
            titleBar.updatePath(nil)
            titleBar.updateGitBranch(nil)
            titleBar.updateGitWorktree(nil)
            titleBar.updateProcess(nil)
            titleBar.clearSize()
            statusBar.clear()
            sidebar.setActiveToolID(panel.pluginID)
        }

        updateChromeFrames(animated: previousIndex != index)
        updateCommandFailureSuggestionVisibility()
        refreshTabUI()
    }

    func updateTabTitle(_ title: String, for surface: TerminalSurfaceView) {
        if let idx = tabs.firstIndex(where: { $0.surfaces.contains(where: { $0 === surface }) }) {
            if tabs[idx].isUserRenamed { return }
            tabs[idx].title = title
            refreshTabUI()
        }
    }

    func updateTabCwd(_ cwd: String, for surface: TerminalSurfaceView) {
        surface.currentCwd = cwd
        if let idx = tabs.firstIndex(where: { $0.surfaces.contains(where: { $0 === surface }) }) {
            tabs[idx].cwd = cwd
            if !tabs[idx].isUserRenamed {
                tabs[idx].title = (cwd as NSString).lastPathComponent
            }
            refreshTabUI()

            // Update status bar and title bar if this is the active tab
            if idx == selectedTabIndex {
                titleBar.updateContext(surface.displayContext)
                statusBar.updateContext(surface.displayContext)
                titleBar.updatePath(cwd)
                titleBar.updateGitBranch(nil)
                titleBar.updateGitWorktree(nil)
                titleBar.updateProcess(nil)
                statusBar.updateCwd(cwd)
                statusBar.updateGitBranch(nil)
                statusBar.updateGitWorktree(nil)
                statusBar.updateProcess(nil)
                refreshStatusBarAsync(cwd: cwd)
            }
            updateSmartPanelContexts()
        }
    }

    /// Fetch shell context off the main thread.
    private func refreshStatusBarAsync(cwd: String) {
        activeGitInfo = nil
        notifyEmbeddedStateChanged()
        let pid = findShellPID()
        let activeSurface = activeSurface
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let gitInfo = TerminalRuntimeInfoService.gitRepositoryInfo(in: cwd)
            let runtimeStatus = TerminalRuntimeInfoService.runtimeStatus(for: pid)

            DispatchQueue.main.async {
                guard let self,
                      self.selectedTabIndex < self.tabs.count,
                      self.tabs[self.selectedTabIndex].cwd == cwd else { return }
                if let activeSurface, self.activeSurface === activeSurface {
                    activeSurface.detectedContext = runtimeStatus.detectedContext
                    activeSurface.lastForegroundPresentation = runtimeStatus.foregroundProcess
                    let context = activeSurface.displayContext
                    self.titleBar.updateContext(context)
                    self.statusBar.updateContext(context)
                }
                self.titleBar.updateGitBranch(gitInfo?.branch)
                self.titleBar.updateGitWorktree(gitInfo?.worktreeName)
                self.titleBar.updateProcess(runtimeStatus.foregroundProcess)
                self.statusBar.updateCwd(cwd)
                self.statusBar.updateGitBranch(gitInfo?.branch)
                self.statusBar.updateGitWorktree(gitInfo?.worktreeName)
                self.statusBar.updateProcess(runtimeStatus.foregroundProcess)
                self.activeGitInfo = gitInfo
                self.refreshPaneHeaders()
                self.notifyEmbeddedStateChanged()
            }
        }

        // Fetch GitHub summary separately (slower, runs in parallel)
        refreshGitHubStatusAsync(cwd: cwd)
    }

    private var lastGitHubCwd: String?
    private var activeGitInfo: GitRepositoryInfo?

    private var shouldShowStatusBar: Bool {
        dependencies.settings.showStatusBar && statusBar.hasVisibleContent
    }

    private func refreshGitHubStatusAsync(cwd: String) {
        // Only re-fetch when the directory actually changes
        guard cwd != lastGitHubCwd else { return }
        lastGitHubCwd = cwd

        statusBar.updateGitHub(nil)
        statusBar.updateGitHubDetails(nil)
        statusBar.setGitHubLoading(dependencies.settings.showStatusBarGitHub)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let details = GitHubService.statusDetails(in: cwd)

            DispatchQueue.main.async {
                guard let self,
                      self.selectedTabIndex < self.tabs.count,
                      self.tabs[self.selectedTabIndex].cwd == cwd else { return }
                self.statusBar.updateGitHub(details?.summary)
                self.statusBar.updateGitHubDetails(details)
                self.statusBar.setGitHubLoading(false)
            }
        }
    }

    private func refreshActiveRuntimeStatusAsync() {
        guard selectedTabIndex < tabs.count,
              let surface = activeSurface else { return }

        let tabID = tabs[selectedTabIndex].id
        let pid = findShellPID()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak surface] in
            let runtimeStatus = TerminalRuntimeInfoService.runtimeStatus(for: pid)

            DispatchQueue.main.async {
                guard let self, let surface else { return }
                guard self.selectedTabIndex < self.tabs.count,
                      self.tabs[self.selectedTabIndex].id == tabID,
                      self.activeSurface === surface else { return }

                surface.detectedContext = runtimeStatus.detectedContext
                surface.lastForegroundPresentation = runtimeStatus.foregroundProcess
                let context = surface.displayContext
                self.titleBar.updateContext(context)
                self.statusBar.updateContext(context)
                self.titleBar.updateProcess(runtimeStatus.foregroundProcess)
                self.statusBar.updateProcess(runtimeStatus.foregroundProcess)
                self.refreshPaneHeaders()
                self.notifyEmbeddedStateChanged()
            }
        }
    }

    func connectSSHProfile(id: UUID) {
        guard let profile = SSHProfileStore.shared.profile(id: id) else {
            SettingsNavigation.open(
                selecting: "ssh",
                in: self,
                settings: dependencies.settings,
                preferencesWindowController: dependencies.preferencesWindowController
            )
            return
        }

        let context = profile.launchContext
        guard let surface = createTab(titleOverride: profile.displayName, context: context) else { return }
        sessionCoordinator.send(command: SSHLaunchBuilder.command(for: profile), to: surface)
    }

    var activeCwd: String {
        if selectedTabIndex < tabs.count, let cwd = tabs[selectedTabIndex].cwd {
            return cwd
        }
        return FileManager.default.currentDirectoryPath
    }

    func owns(surface: TerminalSurfaceView) -> Bool {
        tabs.contains { tab in
            tab.surfaces.contains { $0 === surface }
        }
    }

    func isSurfaceVisible(_ surface: TerminalSurfaceView) -> Bool {
        guard selectedTabIndex < tabs.count else { return false }
        let activeTab = tabs[selectedTabIndex]
        return activeTab.surfaces.contains { $0 === surface } && activeSurface === surface
    }

    func tabTitle(for surface: TerminalSurfaceView) -> String? {
        tabs.first(where: { entry in
            entry.surfaces.contains { $0 === surface }
        })?.title
    }

    private func refreshTabUI() {
        // Build a map from tab index to ⌘N digit for the first 9 terminal tabs.
        let terminalIndices = Self.shortcutSelectableTerminalTabIndices(for: tabs.map(\.kind))
        var hotkeyByTabIndex: [Int: Int] = [:]
        for (visibleIndex, tabIndex) in terminalIndices.prefix(9).enumerated() {
            hotkeyByTabIndex[tabIndex] = visibleIndex + 1
        }
        let tabData = tabs.enumerated().map { offset, entry in
            (
                id: entry.id,
                title: entry.title,
                kind: entry.kind,
                paneCount: entry.surfaces.count,
                hotkeyDigit: hotkeyByTabIndex[offset]
            )
        }
        sidebar.update(tabs: tabData, selectedIndex: selectedTabIndex)

        let barTabs = tabs.map { TabBarView.Tab(id: $0.id, title: $0.title, kind: $0.kind, isPinned: $0.isPinned) }
        tabBar.update(tabs: barTabs, selectedIndex: selectedTabIndex)

        refreshWorkspaceTitle()
        refreshPaneHeaders()
        notifyEmbeddedStateChanged()
    }

    /// Push the active tab's name + pane count into the title bar's centered title.
    private func refreshWorkspaceTitle() {
        guard selectedTabIndex < tabs.count else {
            titleBar.updateWorkspaceContext(shell: nil, name: nil, paneCount: 0)
            return
        }
        let entry = tabs[selectedTabIndex]
        guard entry.isTerminal else {
            titleBar.updateWorkspaceContext(shell: nil, name: nil, paneCount: 0)
            return
        }
        titleBar.updateWorkspaceContext(
            shell: "zsh",
            name: entry.title,
            paneCount: entry.surfaces.count
        )
    }

    // MARK: - Split Panes

    func splitPane(direction: SplitPaneView.Orientation) {
        splitPane(direction: direction, animated: true)
    }

    func openReferencePaneLayoutIfNeeded() {
        guard dependencies.settings.useRebrandShell,
              dependencies.settings.openRebrandPanesByDefault,
              selectedTabIndex < tabs.count,
              tabs[selectedTabIndex].isTerminal,
              tabs[selectedTabIndex].surfaces.count == 1,
              let root = tabs[selectedTabIndex].splitRoot else {
            return
        }

        let originalCwd = activeSurface?.currentCwd ?? tabs[selectedTabIndex].cwd
        splitPane(direction: .vertical, animated: false)
        root.adjustRatio(by: 0.12, animated: false)

        splitPane(direction: .horizontal, animated: false)
        root.second?.adjustRatio(by: -0.08, animated: false)

        if let originalCwd {
            for surface in tabs[selectedTabIndex].surfaces where surface.currentCwd == nil {
                openWorkingDirectory(originalCwd, in: surface)
            }
        }

        if let firstSurface = tabs[selectedTabIndex].surfaces.first {
            tabs[selectedTabIndex].focusedSurface = firstSurface
            window?.makeFirstResponder(firstSurface)
        }
        updateFocusIndicator()
        refreshWorkspaceTitle()
        refreshTabUI()
    }

    private func splitPane(direction: SplitPaneView.Orientation, animated: Bool) {
        guard selectedTabIndex < tabs.count, tabs[selectedTabIndex].isTerminal, let terminalApp else { return }

        let tabId = tabs[selectedTabIndex].id
        let inheritedContext = activeSurface?.terminalContext ?? .local
        let inheritedCwd = activeSurface?.currentCwd ?? tabs[selectedTabIndex].cwd
        let surface = makeSurface(tabId: tabId, app: terminalApp, context: inheritedContext)

        guard let root = tabs[selectedTabIndex].splitRoot else { return }

        let newLeaf: SplitPaneView
        if let focused = activeSurface, let leaf = root.leaf(containing: focused) {
            newLeaf = leaf.split(orientation: direction, newContent: makePaneContent(for: surface))
        } else {
            newLeaf = root.split(orientation: direction, newContent: makePaneContent(for: surface))
        }

        tabs[selectedTabIndex].addSurface(surface)
        tabs[selectedTabIndex].focusedSurface = surface
        if let inheritedCwd {
            openWorkingDirectory(inheritedCwd, in: surface)
        }
        window?.makeFirstResponder(surface)

        if animated {
            // Fade in the new pane while animating the split layout.
            newLeaf.alphaValue = 0
            needsLayout = true
            layoutSubtreeIfNeeded()
            root.animateLayout(duration: Theme.animMedium)

            Theme.animate(duration: Theme.animMedium) { _ in
                newLeaf.animator().alphaValue = 1
            }
        } else {
            newLeaf.alphaValue = 1
            root.needsLayout = true
        }

        updateFocusIndicator()
        refreshWorkspaceTitle()
        refreshPaneHeaders()
        notifyEmbeddedStateChanged()
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
                self.refreshWorkspaceTitle()
            })
        } else if entry.surfaces.count == 1 {
            closeCurrentTab()
        }
    }

    private func navigatePane(_ direction: SplitPaneView.Direction) {
        guard selectedTabIndex < tabs.count, let current = activeSurface else { return }
        guard let root = tabs[selectedTabIndex].splitRoot else { return }
        if let nextView = root.adjacentLeaf(from: current, direction: direction),
           let nextSurface = terminalSurface(in: nextView) {
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
            addSubview(focused, positioned: .below, relativeTo: overlayReferenceView)
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
        notifyEmbeddedStateChanged()
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

        let pinItem = NSMenuItem(
            title: tabs[index].isPinned ? "Unpin Tab" : "Pin Tab",
            action: #selector(contextMenuTogglePin(_:)),
            keyEquivalent: ""
        )
        pinItem.representedObject = index
        pinItem.target = self
        menu.addItem(pinItem)
        menu.addItem(.separator())

        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(contextMenuCloseTab(_:)), keyEquivalent: "")
        closeItem.representedObject = index
        closeItem.target = self
        closeItem.isEnabled = !tabs[index].isPinned
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
            // Skip pinned tabs — they're protected from bulk-close.
            if tabs[i].id != keepId && !tabs[i].isPinned { closeTab(i) }
            i -= 1
        }
    }

    @objc private func contextMenuCloseTabsToRight(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        var i = tabs.count - 1
        while i > index {
            if !tabs[i].isPinned { closeTab(i) }
            i -= 1
        }
    }

    @objc private func contextMenuTogglePin(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        togglePinTab(index)
    }

    @objc private func contextMenuDuplicateTab(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, index < tabs.count else { return }
        let cwd = tabs[index].cwd
        let context = tabs[index].persistedContext
        if let sshProfileID = context?.sshProfileID, SSHProfileStore.shared.profile(id: sshProfileID) != nil {
            connectSSHProfile(id: sshProfileID)
        } else {
            _ = createTab(
                initialWorkingDirectory: cwd,
                titleOverride: tabs[index].title,
                context: context ?? .local
            )
        }
    }

    @objc private func contextMenuMoveToNewWindow(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int,
              index >= 0, index < tabs.count,
              let currentWindow = window else { return }

        let frame = currentWindow.frame
        let dropPoint = NSPoint(x: frame.midX, y: frame.maxY - 32)
        tearOffTab(tabs[index].id, dropScreenPoint: dropPoint)
    }

    // MARK: - Reopen Closed Tab

    func reopenClosedTab() {
        guard let last = recentlyClosedTabs.popLast() else { return }
        if let sshProfileID = last.context?.sshProfileID, SSHProfileStore.shared.profile(id: sshProfileID) != nil {
            connectSSHProfile(id: sshProfileID)
        } else {
            let surface = createTab(
                initialWorkingDirectory: last.cwd,
                titleOverride: last.title,
                context: last.context ?? .local,
                localSessionBootstrap: last.localSessionBootstrap,
                localSessionName: last.localSessionName
            )
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

    private func toolContextTerminalIndex() -> Int? {
        if selectedTabIndex < tabs.count, tabs[selectedTabIndex].isTerminal {
            return selectedTabIndex
        }

        if let lastSelectedTerminalTabID,
           let index = tabs.firstIndex(where: { $0.id == lastSelectedTerminalTabID && $0.isTerminal }) {
            return index
        }

        return tabs.firstIndex(where: \.isTerminal)
    }

    private func updateSmartPanelContexts() {
        let shellPID = findShellPID()
        let cwd = currentTerminalCwd()
        for tab in tabs {
            guard case .smart(let panel) = tab.content else { continue }
            panel.shellPID = shellPID
            panel.workingDirectory = cwd
        }
    }

    /// Returns the CWD of the most relevant terminal tab.
    private func currentTerminalCwd() -> String? {
        guard let terminalIndex = toolContextTerminalIndex() else { return nil }
        let entry = tabs[terminalIndex]
        let surface = entry.focusedSurface ?? entry.surfaces.first
        return surface?.currentCwd ?? entry.cwd
    }

    func refreshSmartPanelContexts() {
        updateSmartPanelContexts()
    }

    /// Find the shell PID for the most relevant terminal context by looking up the
    /// Bellith app's child processes and matching against the current or last active
    /// terminal tab's working directory. When only one shell is present, use it as a
    /// fallback even if the shell has not reported its cwd yet.
    private func findShellPID() -> pid_t? {
        guard let terminalIndex = toolContextTerminalIndex() else { return nil }
        let terminalEntry = tabs[terminalIndex]
        let surface = terminalEntry.focusedSurface ?? terminalEntry.surfaces.first
        let cwd = surface?.currentCwd ?? terminalEntry.cwd
        let appPID = ProcessInfo.processInfo.processIdentifier
        guard let tree = ProcessMonitor.processTree(rootPID: appPID) else { return nil }

        let shellNames: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "nu", "elvish", "nushell"]
        var shellPIDs: [pid_t] = []

        // Walk children looking for shells in the process tree and prefer a cwd match.
        func findMatchingChild(_ node: TerminalProcessInfo) -> pid_t? {
            if shellNames.contains(node.name.lowercased()) {
                shellPIDs.append(node.pid)
                if let cwd,
                   let childCwd = ProcessMonitor.workingDirectory(for: node.pid),
                   childCwd == cwd {
                    return node.pid
                }
            }
            for child in node.children {
                if let found = findMatchingChild(child) { return found }
            }
            return nil
        }

        if let matchedPID = findMatchingChild(tree) {
            return matchedPID
        }

        return shellPIDs.count == 1 ? shellPIDs[0] : nil
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
                    if self.commandFailureSuggestionSurface === surface {
                        self.clearCommandFailureSuggestion()
                    }
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
    private let titleBarHeight: CGFloat = 34

    private func statusBarHeight(for isVisible: Bool) -> CGFloat {
        isVisible ? StatusBarView.height : 0
    }

    private func statusBarGap(for isVisible: Bool) -> CGFloat {
        isVisible ? 6 : 0
    }

    private func contentRect(forSidebarWidth sidebarWidth: CGFloat, statusBarVisible: Bool = false) -> NSRect {
        // When the rebrand shell hosts this view, it provides its own title
        // bar / rail / status bar / outer padding, so this view is just the
        // body and should fill its bounds completely.
        if embedInRebrandShell {
            return bounds
        }
        let p = contentPadding
        let bottomOffset = p + statusBarHeight(for: statusBarVisible) + statusBarGap(for: statusBarVisible)
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
        return contentRect(forSidebarWidth: sidebarWidth, statusBarVisible: shouldShowStatusBar)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tabBar.windowIdentifier = tabDragWindowID
        sidebar.windowIdentifier = tabDragWindowID
        lastKnownStatusBarVisible = shouldShowStatusBar
        statusBar.alphaValue = lastKnownStatusBarVisible ? 1 : 0
        updateRuntimeStatusObservers()
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
        titleBar.isHidden = embedInRebrandShell
        titleBar.frame = NSRect(
            x: contentLeft + 6,
            y: bounds.height - p - titleBarHeight + 1,
            width: bounds.width - contentLeft - p - 10,
            height: titleBarHeight
        )

        let statusBarVisible = shouldShowStatusBar && !embedInRebrandShell
        lastKnownStatusBarVisible = statusBarVisible
        statusBar.isHidden = !statusBarVisible
        statusBar.alphaValue = statusBarVisible ? 1 : 0
        statusBar.frame = NSRect(
            x: contentLeft,
            y: p,
            width: bounds.width - contentLeft - p,
            height: statusBarHeight(for: statusBarVisible)
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

        if let suggestionView = commandFailureSuggestionView, suggestionView.superview != nil {
            let suggestedWidth = min(420, max(300, rect.width * 0.4))
            let panelHeight = suggestionView.preferredHeight(for: suggestedWidth)
            suggestionView.frame = NSRect(
                x: rect.maxX - suggestedWidth - 14,
                y: rect.minY + 14,
                width: suggestedWidth,
                height: panelHeight
            )
        }
    }

    private func animateContentLayout(statusBarVisible explicitStatusBarVisible: Bool? = nil) {
        let p = contentPadding
        let targetSidebarWidth: CGFloat = sidebar.isExpanded ? SidebarView.expandedWidth : 0
        let targetStatusBarVisible = explicitStatusBarVisible ?? shouldShowStatusBar
        let targetStatusBarHeight = statusBarHeight(for: targetStatusBarVisible)
        let targetContentRect = contentRect(forSidebarWidth: targetSidebarWidth, statusBarVisible: targetStatusBarVisible)

        // Calculate target positions for all elements that shift with the sidebar
        let targetContentLeft: CGFloat
        if useSidebar && targetSidebarWidth > 0 {
            targetContentLeft = p + targetSidebarWidth + sidebarGap
        } else {
            targetContentLeft = p
        }

        let targetStatusBarX = targetContentLeft
        let targetStatusBarW = bounds.width - targetStatusBarX - p

        if targetStatusBarVisible && !embedInRebrandShell {
            statusBar.isHidden = false
            if !lastKnownStatusBarVisible {
                statusBar.alphaValue = 0
            }
        }

        let targetTitleBarX = targetContentLeft + 6
        let targetTitleBarY = bounds.height - p - titleBarHeight + 1
        let targetTitleBarW = bounds.width - targetContentLeft - p - 10

        isAnimatingLayout = true
        let springTiming = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        Theme.animate(duration: Theme.animSlow, timing: springTiming, { ctx in
            ctx.allowsImplicitAnimation = true

            self.updateChromeFrames(animated: true, sidebarWidth: targetSidebarWidth, statusBarVisible: targetStatusBarVisible)

            sidebar.animator().frame = NSRect(
                x: p, y: p,
                width: targetSidebarWidth,
                height: bounds.height - p * 2
            )

            statusBar.animator().alphaValue = targetStatusBarVisible ? 1 : 0
            statusBar.animator().frame = NSRect(
                x: targetStatusBarX, y: p,
                width: targetStatusBarW,
                height: targetStatusBarHeight
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
            guard let self else { return }
            self.lastKnownStatusBarVisible = targetStatusBarVisible
            let hideForEmbed = self.embedInRebrandShell
            self.statusBar.isHidden = hideForEmbed || !targetStatusBarVisible
            self.statusBar.alphaValue = (hideForEmbed || !targetStatusBarVisible) ? 0 : 1
            self.isAnimatingLayout = false
            self.needsLayout = true
        })
    }

    private func handleStatusBarVisibilityChange(_ visible: Bool) {
        guard lastKnownStatusBarVisible != visible else { return }
        guard window != nil else {
            lastKnownStatusBarVisible = visible
            needsLayout = true
            return
        }
        animateContentLayout(statusBarVisible: visible)
    }

    // MARK: - Theme

    private func applyFrameColor() {
        layer?.backgroundColor = activeProfileIsTranslucent
            ? NSColor.clear.cgColor
            : Theme.colors.frame.cgColor
        // Slider 0–1 maps to 0–0.08 (dark) or 0–0.12 (light) actual opacity
        let maxOpacity: Double = Theme.colors.isLight ? 0.12 : 0.08
        noiseLayer.opacity = Float(dependencies.settings.noiseIntensity * maxOpacity)
    }

    private func handleThemeChange() {
        applyFrameColor()
        applyChromeTheme()
        sidebar.refreshTheme()
        tabBar.refreshTheme()
        statusBar.refreshTheme()
        titleBar.refreshTheme()
        overlayController.refreshTheme()
        for tab in tabs {
            tab.splitRoot?.refreshTheme()
            applyChrome(to: tab.rootView)
        }
        (zoomBadge as? ZoomBadge)?.refreshTheme()
        (broadcastBadge as? BroadcastBadge)?.refreshTheme()
        commandFailureSuggestionView?.refreshTheme()
        updateChromeFrames(animated: false)
        updateFocusIndicator()
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

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard useSidebar, TabDragPayload.read(from: sender.draggingPasteboard) != nil else {
            return []
        }

        let location = convert(sender.draggingLocation, from: nil)
        if !sidebar.isExpanded && location.x <= 24 {
            sidebar.show()
            needsLayout = true
            layoutSubtreeIfNeeded()
        }

        guard sidebar.isExpanded, sidebar.frame.contains(location) else { return [] }
        return sidebar.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        guard useSidebar, sidebar.isExpanded else { return }
        sidebar.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard useSidebar else { return false }
        return sidebar.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard useSidebar else { return false }
        return sidebar.performDragOperation(sender)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        guard useSidebar else { return }
        sidebar.concludeDragOperation(sender)
    }

    // MARK: - Command Palette

    func toggleCommandPalette() {
        overlayController.toggleCommandPalette()
    }

    func showCommandPalette() {
        overlayController.showCommandPalette()
    }

    func hideCommandPalette() {
        overlayController.hideCommandPalette()
    }

    func toggleShortcutCheatSheet() {
        overlayController.toggleShortcutCheatSheet()
    }

    func hideShortcutCheatSheet() {
        overlayController.hideShortcutCheatSheet()
    }

    func performCommandPaletteCommand(_ text: String) {
        let cmd = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let command = dependencies.commandRegistry.command(matching: cmd) {
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
                dependencies.settings.lightThemeName = theme.name
            } else {
                dependencies.settings.darkThemeName = theme.name
            }
            let resolved = dependencies.settings.resolvedTheme
            dependencies.themeManager.apply(resolved)
        } else {
            Logger.ui.warning("Unknown command: \(text)")
        }
    }

    // MARK: - Search

    func showSearch(initialNeedle: String? = nil) {
        overlayController.showSearch(initialNeedle: initialNeedle)
    }

    func hideSearch() {
        overlayController.hideSearch()
    }

    func updateSearchTotal(_ total: Int) {
        overlayController.updateSearchTotal(total)
    }

    func updateSearchSelected(_ selected: Int) {
        overlayController.updateSearchSelected(selected)
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

    func handleCompletedCommand(on surface: TerminalSurfaceView, exitCode: Int16) {
        guard dependencies.settings.shellIntegrationEnabled,
              dependencies.settings.errorFixSuggestionsEnabled else {
            if commandFailureSuggestionSurface === surface {
                clearCommandFailureSuggestion()
            }
            return
        }

        guard exitCode > 0 else {
            if commandFailureSuggestionSurface === surface {
                clearCommandFailureSuggestion()
            }
            return
        }

        guard isSurfaceVisible(surface),
              window?.isVisible == true,
              window?.isKeyWindow == true,
              let transcript = surface.readScreenText(),
              let suggestion = CommandFailureSuggestionService.suggestion(
                  for: transcript,
                  exitCode: exitCode,
                  foregroundProcessName: surface.lastForegroundPresentation?.text
              ) else {
            if commandFailureSuggestionSurface === surface {
                clearCommandFailureSuggestion()
            }
            return
        }

        commandFailureSuggestionSurface = surface
        commandFailureSuggestion = suggestion
        updateCommandFailureSuggestionVisibility()
    }

    private func updateCommandFailureSuggestionVisibility() {
        guard dependencies.settings.shellIntegrationEnabled,
              dependencies.settings.errorFixSuggestionsEnabled,
              let suggestion = commandFailureSuggestion,
              let surface = commandFailureSuggestionSurface,
              isSurfaceVisible(surface) else {
            commandFailureSuggestionView?.removeFromSuperview()
            if commandFailureSuggestionSurface == nil {
                commandFailureSuggestion = nil
            }
            needsLayout = true
            return
        }

        let view: CommandFailureSuggestionView
        if let existingView = commandFailureSuggestionView {
            view = existingView
        } else {
            let newView = CommandFailureSuggestionView()
            newView.onInsertFix = { [weak self] in
                self?.insertSuggestedFixCommand()
            }
            newView.onDismiss = { [weak self] in
                self?.clearCommandFailureSuggestion()
            }
            commandFailureSuggestionView = newView
            view = newView
        }

        view.update(with: suggestion)
        view.refreshTheme()
        if view.superview == nil {
            addSubview(view, positioned: .below, relativeTo: overlayReferenceView)
        }
        needsLayout = true
    }

    private func clearCommandFailureSuggestion() {
        commandFailureSuggestion = nil
        commandFailureSuggestionSurface = nil
        commandFailureSuggestionView?.removeFromSuperview()
        needsLayout = true
    }

    private func insertSuggestedFixCommand() {
        guard let surface = commandFailureSuggestionSurface,
              isSurfaceVisible(surface),
              let fixCommand = commandFailureSuggestion?.fixCommand else { return }
        window?.makeFirstResponder(surface)
        surface.insertCommandText(fixCommand)
        clearCommandFailureSuggestion()
    }

    // MARK: - Font Size

    func adjustFontSizePublic(delta: Int) { adjustFontSize(delta: delta) }
    func resetFontSizePublic() { resetFontSize() }

    private func adjustFontSize(delta: Int) {
        let settings = dependencies.settings
        let newSize = max(Metrics.minimumFontSize, min(Metrics.maximumFontSize, settings.fontSize + delta))
        guard newSize != settings.fontSize else { return }
        settings.fontSize = newSize
        reloadConfig()
    }

    private func resetFontSize() {
        dependencies.settings.fontSize = 15
        reloadConfig()
    }

    // MARK: - Config Reload

    func reloadConfig() {
        guard let terminalApp = terminalApp, let app = terminalApp.app else { return }
        let config = TerminalConfig()
        guard let newConfig = config.config else { return }
        // Update the app-level config so new surfaces inherit the new settings.
        ghostty_app_update_config(app, newConfig)
        // ghostty_app_update_config does not touch existing surfaces — push the
        // same config onto every live surface so theme, font, cursor, scrollback,
        // and other settings reflect immediately without closing the tab.
        for tab in tabs {
            for surfaceView in tab.surfaces {
                guard let surface = surfaceView.surface else { continue }
                ghostty_surface_update_config(surface, newConfig)
                ghostty_surface_refresh(surface)
            }
        }
    }

    // MARK: - Session Save / Restore

    func saveSession() -> SessionState {
        sessionCoordinator.saveSession(from: tabs, selectedTabIndex: selectedTabIndex, sidebarExpanded: sidebar.isExpanded)
    }

    func sessionState(forTabAt index: Int) -> SessionState? {
        sessionCoordinator.sessionState(forTabAt: index, in: tabs)
    }

    func restoreSession(_ state: SessionState) {
        guard terminalApp != nil else { return }

        for tab in tabs {
            tab.rootView.removeFromSuperview()
        }
        tabs.removeAll()
        tabs = sessionCoordinator.restoreSession(state)

        if tabs.isEmpty {
            createTab()
        }

        let idx = min(state.selectedTabIndex, tabs.count - 1)
        selectTab(max(idx, 0))
        refreshTabUI()

        // Restore sidebar expanded/collapsed state
        if let sidebarExpanded = state.sidebarExpanded {
            if sidebarExpanded && !sidebar.isExpanded {
                sidebar.show()
            } else if !sidebarExpanded && sidebar.isExpanded {
                sidebar.hide()
            }
        }
    }

    // MARK: - Rename Tab

    func promptRenameTab(at index: Int? = nil) {
        let targetIndex = index ?? selectedTabIndex
        guard tabs.indices.contains(targetIndex) else { return }
        guard tabs[targetIndex].isTerminal else { return }

        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.informativeText = "Enter a new name for this tab. Leave blank to restore the automatic name."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = tabs[targetIndex].title
        input.selectText(nil)
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if name.isEmpty {
            tabs[targetIndex].isUserRenamed = false
            if let cwd = tabs[targetIndex].cwd {
                tabs[targetIndex].title = (cwd as NSString).lastPathComponent
            }
        } else {
            tabs[targetIndex].title = name
            tabs[targetIndex].isUserRenamed = true
        }
        refreshTabUI()
    }

    // MARK: - Workspaces

    func promptSaveWorkspace() {
        let alert = NSAlert()
        alert.messageText = "Save Workspace"
        alert.informativeText = "Enter a name for this workspace layout:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "Workspace name"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let session = saveSession()
        let store = WorkspaceStore.shared

        if let existing = store.workspace(named: name) {
            let confirm = NSAlert()
            confirm.messageText = "Workspace Exists"
            confirm.informativeText = "A workspace named \"\(name)\" already exists. Replace it?"
            confirm.addButton(withTitle: "Replace")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
            store.updateSession(id: existing.id, session: session)
        } else {
            store.save(WorkspaceDefinition(name: name, session: session))
        }
    }

    func promptDeleteWorkspace() {
        let store = WorkspaceStore.shared
        let workspaces = store.workspaces
        guard !workspaces.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Workspaces"
            alert.informativeText = "There are no saved workspaces to delete."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete Workspace"
        alert.informativeText = "Select a workspace to delete:"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 24), pullsDown: false)
        for ws in workspaces {
            popup.addItem(withTitle: ws.name)
        }
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let selectedIndex = popup.indexOfSelectedItem
        guard selectedIndex >= 0, selectedIndex < workspaces.count else { return }
        store.delete(id: workspaces[selectedIndex].id)
    }

    // MARK: - Surface Factory

    /// Centralized surface creation — wires up all callbacks (onClose, onTextInserted).
    func makeSurface(tabId: UUID, context: TerminalContext) -> TerminalSurfaceView {
        guard let terminalApp else {
            preconditionFailure("Terminal app must exist before creating a surface")
        }
        return makeSurface(tabId: tabId, app: terminalApp, context: context)
    }

    func addRestoredTabRootView(_ view: NSView) {
        addSubview(view, positioned: .below, relativeTo: sidebar)
    }

    func makePaneContent(for surface: TerminalSurfaceView) -> NSView {
        let container = PaneContainerView(surface: surface)
        return container
    }

    /// Walk up from a surface's view tree to find the wrapping `PaneContainerView`, if any.
    private func paneContainer(for surface: NSView) -> PaneContainerView? {
        var node: NSView? = surface
        while let n = node {
            if let container = n as? PaneContainerView { return container }
            node = n.superview
        }
        return nil
    }

    /// Refresh every pane's header content (pid pill, title, cwd, status dot) for the active tab.
    private func refreshPaneHeaders() {
        guard selectedTabIndex < tabs.count else { return }
        let entry = tabs[selectedTabIndex]
        guard entry.isTerminal else { return }
        let tint = WorkspaceTint.accent(for: entry.title)
        let showsCard = entry.surfaces.count > 1
        for (idx, surface) in entry.surfaces.enumerated() {
            guard let container = paneContainer(for: surface) else { continue }
            let cwd = surface.currentCwd ?? entry.cwd
            let presentation = surface.lastForegroundPresentation
            let title = Self.paneHeaderTitle(from: presentation)
            let isRunning = Self.paneHeaderIsRunning(from: presentation)
            container.configure(
                paneIndex: "0:\(idx + 1)",
                title: title,
                cwd: cwd,
                isFocused: surface === entry.focusedSurface,
                isRunning: isRunning,
                workspaceTint: tint,
                showsCardChrome: showsCard
            )
        }
    }

    private func makeSurface(tabId: UUID, app: TerminalApp, context: TerminalContext) -> TerminalSurfaceView {
        let surface = TerminalSurfaceView(app: app)
        surface.terminalContext = context
        bindSurfaceCallbacks(for: surface, tabId: tabId)
        return surface
    }

    private func bindSurfaceCallbacks(for surface: TerminalSurfaceView, tabId: UUID) {
        surface.shouldReportMousePosition = { [weak self, weak surface] in
            guard let self, let surface else { return false }
            return self.isSurfaceVisible(surface)
        }
        surface.onFocus = { [weak self, weak surface] focusedSurface in
            guard let self, let surface, focusedSurface === surface else { return }
            guard let tabIndex = self.tabs.firstIndex(where: { tab in
                tab.surfaces.contains { $0 === surface }
            }) else { return }

            self.tabs[tabIndex].focusedSurface = surface
            if tabIndex == self.selectedTabIndex {
                self.updateCommandFailureSuggestionVisibility()
                self.titleBar.updateContext(surface.displayContext)
                self.statusBar.updateContext(surface.displayContext)
                self.updateFocusIndicator()
                surface.refreshReportedSize()
                if let cwd = self.tabs[tabIndex].cwd {
                    self.refreshStatusBarAsync(cwd: cwd)
                } else {
                    self.refreshActiveRuntimeStatusAsync()
                }
            }
        }
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
                self.titleBar.updateContext(surface.displayContext)
                self.statusBar.updateContext(surface.displayContext)
                self.titleBar.updateSize(cols: cols, rows: rows)
                self.statusBar.updateSize(cols: cols, rows: rows)
            }
        }
    }

    private func terminalSurface(in view: NSView) -> TerminalSurfaceView? {
        if let surface = view as? TerminalSurfaceView {
            return surface
        }
        for subview in view.subviews {
            if let surface = terminalSurface(in: subview) {
                return surface
            }
        }
        return nil
    }

    func openWorkingDirectory(_ cwd: String) {
        guard let surface = activeSurface else { return }
        openWorkingDirectory(cwd, in: surface)
    }

    func runInActiveSurface(_ command: String) {
        guard let surface = activeSurface else { return }
        sessionCoordinator.send(command: command, to: surface)
    }

    func openFileInEditor(_ fileURL: URL, titleOverride: String? = nil) {
        let command = Self.editorCommand(for: fileURL)
        let workingDirectory = fileURL.deletingLastPathComponent().path

        guard let surface = createTab(
            initialWorkingDirectory: workingDirectory,
            titleOverride: titleOverride ?? fileURL.lastPathComponent
        ) else {
            return
        }

        sessionCoordinator.send(command: command, to: surface)
    }

    private func openWorkingDirectory(_ cwd: String, in surface: TerminalSurfaceView) {
        surface.currentCwd = cwd
        if let idx = tabs.firstIndex(where: { $0.surfaces.contains(where: { $0 === surface }) }) {
            tabs[idx].cwd = cwd
            if !tabs[idx].isUserRenamed {
                tabs[idx].title = (cwd as NSString).lastPathComponent
            }
            if idx == selectedTabIndex {
                titleBar.updateContext(surface.displayContext)
                statusBar.updateContext(surface.displayContext)
                titleBar.updatePath(cwd)
                titleBar.updateGitBranch(nil)
                titleBar.updateGitWorktree(nil)
                titleBar.updateProcess(nil)
                statusBar.updateCwd(cwd)
                statusBar.updateGitBranch(nil)
                statusBar.updateGitWorktree(nil)
                statusBar.updateProcess(nil)
                refreshStatusBarAsync(cwd: cwd)
            }
            updateSmartPanelContexts()
            refreshTabUI()
        }
        sessionCoordinator.restoreWorkingDirectory(cwd, on: surface)
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
