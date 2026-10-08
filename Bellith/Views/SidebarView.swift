import AppKit
import QuartzCore

/// Monochrome utility sidebar with restrained chrome and strong type hierarchy.
final class SidebarView: NSView, NSDraggingSource {
    override var mouseDownCanMoveWindow: Bool { false }
    typealias TabModel = (id: UUID, title: String, kind: TerminalContainerView.TabKind, paneCount: Int, hotkeyDigit: Int?)

    struct SettingsSnapshot: Equatable {
        let isPinned: Bool
        let autoHideWhenFloating: Bool
        let showTools: Bool
        let enabledToolIDs: [String]

        static func current(using settings: BellithSettings = .shared) -> SettingsSnapshot {
            SettingsSnapshot(
                isPinned: settings.sidebarPinned,
                autoHideWhenFloating: settings.sidebarAutoHide,
                showTools: settings.sidebarShowTools,
                enabledToolIDs: settings.sidebarTools
            )
        }
    }

    static let expandedWidth: CGFloat = 56

    private var tabRows: [SidebarTabRow] = []
    private var tabRowSourceIndices: [Int] = []
    private let newTabButton = NSButton()
    private let headerLabel = NSTextField(labelWithString: "")
    private let noiseView = SidebarNoiseView()
    private let topBand = CAGradientLayer()
    private let trafficLightDock = CALayer()
    private let trafficLightHalo = CAGradientLayer()
    private let topBandSeparator = CALayer()
    private let innerStroke = CALayer()
    private let topHighlight = CALayer()
    private let edgeBlend = CAGradientLayer()

    // Tools section
    private let toolsSeparator = CALayer()
    private let toolsHeaderLabel = NSTextField(labelWithString: "Tools")
    private var toolRows: [SidebarToolRow] = []
    private var enabledTools: [SmartPanelPlugin] = []
    private let settings: BellithSettings
    private let smartPanelRegistry: SmartPanelRegistry

    /// Which tool plugin is currently open in the main content area (for highlight state).
    private var activeToolID: String?

    private(set) var isExpanded = false
    private var hideTimer: Timer?
    private(set) var isPinned: Bool
    private var settingsSnapshot: SettingsSnapshot

    var tabs: [TabModel] = []
    var selectedIndex: Int = 0

    var onSelectTab: ((Int) -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onExpandChanged: ((Bool) -> Void)?
    var onReorderTab: ((Int, Int) -> Void)?
    var onTabContextMenu: ((Int, NSPoint) -> Void)?
    var onReceiveDraggedTab: ((TabDragPayload, Int) -> Void)?
    var onTearOffTab: ((UUID, NSPoint) -> Void)?

    var windowIdentifier: UUID?

    private var effectiveWindowIdentifier: UUID? {
        windowIdentifier ?? (window as? TerminalWindow)?.tabDragIdentifier
    }

    /// Called when a tool is clicked in the sidebar. The container opens it in the main content area.
    var onSelectTool: ((String) -> Void)?

    private var newTabTrackingArea: NSTrackingArea?
    private var dragSourceIndex: Int?
    private var localDragSourceVisibleIndex: Int?
    private var dragIndicatorLayer: CALayer?
    private var dragInsertionIndex: Int?
    private var isDropAccepted = false
    private let pinButton = NSButton()
    private let newTabDashedBorder = CAShapeLayer()
    private var newTabTrackingAreaForHover: NSTrackingArea?
    private var isNewTabHovered: Bool = false {
        didSet {
            if isNewTabHovered != oldValue { applyNewTabHoverAppearance() }
        }
    }
    private var settingsObserver: NSObjectProtocol?

    init(
        frame frameRect: NSRect = .zero,
        settings: BellithSettings = .shared,
        smartPanelRegistry: SmartPanelRegistry = .shared
    ) {
        self.settings = settings
        self.smartPanelRegistry = smartPanelRegistry
        self.isPinned = settings.sidebarPinned
        self.settingsSnapshot = SettingsSnapshot.current(using: settings)
        super.init(frame: frameRect)
        registerForDraggedTypes([TabDragPayload.pasteboardType])
        wantsLayer = true
        alphaValue = 1
        appearance = Theme.overlayAppearance

        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        topBand.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer?.addSublayer(topBand)
        layer?.addSublayer(trafficLightDock)
        layer?.addSublayer(trafficLightHalo)
        layer?.addSublayer(topBandSeparator)
        layer?.addSublayer(toolsSeparator)
        layer?.addSublayer(innerStroke)
        layer?.addSublayer(topHighlight)
        layer?.addSublayer(edgeBlend)

        noiseView.alphaValue = 0
        addSubview(noiseView)

        // PR Popover v2 rail: workspace/tools headers and the inline pin button are
        // dropped in favor of a compact 56px rail. New-tab is a single + at the
        // bottom; the pin toggle moves into settings.
        headerLabel.isHidden = true
        toolsHeaderLabel.isHidden = true

        newTabButton.title = ""
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.contentTintColor = Theme.textSecondary
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTab)
        configureHeaderButton(newTabButton)
        newTabButton.layer?.borderWidth = 0
        newTabButton.toolTip = "New tab"
        addSubview(newTabButton)

        // Dashed hairline around the + tile, mirroring the design's "add" affordance.
        newTabDashedBorder.fillColor = NSColor.clear.cgColor
        newTabDashedBorder.lineWidth = 1
        newTabDashedBorder.lineDashPattern = [3, 3]
        layer?.addSublayer(newTabDashedBorder)

        pinButton.title = ""
        pinButton.isHidden = true
        addSubview(pinButton)

        // Start expanded if pinned
        if isPinned {
            isExpanded = true
        }

        applySidebarChrome()

        // Rebuild tools from settings
        rebuildTools(using: settingsSnapshot)

        // Watch for sidebar settings changes to update pins and tools.
        settingsObserver = NotificationCenter.default.addObserver(
            forName: BellithSettings.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleSettingsChange() }
    }

    deinit {
        hideTimer?.invalidate()
        if let obs = settingsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var headerButtonBaseColor: NSColor {
        Theme.chromeElevated
    }

    private func configureHeaderButton(_ button: NSButton) {
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.cornerCurve = .continuous
        button.layer?.borderWidth = 1
    }

    private func applySidebarChrome() {
        appearance = Theme.overlayAppearance
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        layer?.cornerRadius = 0

        topBand.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        topBand.locations = [0, 1]
        topBand.startPoint = CGPoint(x: 0.5, y: 1)
        topBand.endPoint = CGPoint(x: 0.5, y: 0)
        topBand.cornerRadius = 0

        trafficLightDock.backgroundColor = NSColor.clear.cgColor
        trafficLightDock.borderWidth = 0
        trafficLightDock.borderColor = NSColor.clear.cgColor
        trafficLightDock.cornerRadius = 0

        trafficLightHalo.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        trafficLightHalo.locations = [0, 1]
        trafficLightHalo.startPoint = CGPoint(x: 0, y: 0.5)
        trafficLightHalo.endPoint = CGPoint(x: 1, y: 0.5)

        topBandSeparator.backgroundColor = NSColor.clear.cgColor
        toolsSeparator.backgroundColor = Theme.borderSubtle.cgColor

        innerStroke.backgroundColor = NSColor.clear.cgColor
        innerStroke.borderWidth = 0
        innerStroke.borderColor = NSColor.clear.cgColor
        innerStroke.cornerRadius = 0

        topHighlight.backgroundColor = NSColor.clear.cgColor

        edgeBlend.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        edgeBlend.locations = [0, 1]
        edgeBlend.startPoint = CGPoint(x: 0, y: 0.5)
        edgeBlend.endPoint = CGPoint(x: 1, y: 0.5)
        edgeBlend.cornerRadius = 0

        headerLabel.textColor = Theme.textSecondary
        toolsHeaderLabel.textColor = Theme.textSecondary
        noiseView.alphaValue = 0
        noiseView.refreshTheme()
        newTabButton.contentTintColor = Theme.textSecondary
        newTabButton.layer?.backgroundColor = NSColor.clear.cgColor
        newTabButton.layer?.borderColor = NSColor.clear.cgColor
        newTabDashedBorder.strokeColor = Theme.chromeHairline.withAlphaComponent(Theme.colors.isLight ? 0.55 : 0.45).cgColor
        pinButton.contentTintColor = isPinned ? Theme.textPrimary : Theme.textMuted
        pinButton.layer?.backgroundColor = (isPinned ? Theme.selectionFill.withAlphaComponent(0.65) : NSColor.clear).cgColor
        pinButton.layer?.borderColor = Theme.borderSubtle.cgColor
    }

    func update(tabs: [TabModel], selectedIndex: Int) {
        self.tabs = tabs
        self.selectedIndex = selectedIndex
        rebuildTabs()
    }

    private func rebuildTabs() {
        tabRows.forEach { $0.removeFromSuperview() }
        tabRows.removeAll()
        tabRowSourceIndices.removeAll()

        let visibleTabs = tabs.enumerated().filter { _, tab in
            // When tools section is visible, hide smart tabs from the main tabs list
            // to avoid showing the same tools twice.
            if shouldHideSmartTabsInTabList, case .smart = tab.kind {
                return false
            }
            return true
        }

        for (visibleIndex, entry) in visibleTabs.enumerated() {
            let sourceIndex = entry.offset
            let tab = entry.element
            let row = SidebarTabRow(
                title: tab.title,
                isSelected: sourceIndex == selectedIndex,
                kind: tab.kind,
                smartPanelRegistry: smartPanelRegistry
            )
            row.setPaneCount(tab.paneCount)
            row.setHotkeyDigit(tab.hotkeyDigit)
            row.onSelect = { [weak self] in self?.onSelectTab?(sourceIndex) }
            row.onClose = { [weak self] in self?.onCloseTab?(sourceIndex) }
            row.onDragMoved = { [weak self, weak row] event in
                guard let self, let row else { return }
                self.handleLocalDragMoved(fromVisibleIndex: visibleIndex, event: event, dragView: row)
            }
            row.onDragEnded = { [weak self] event in
                self?.handleLocalDragEnded(fromVisibleIndex: visibleIndex, event: event)
            }
            row.onRightClick = { [weak self] point in self?.onTabContextMenu?(sourceIndex, point) }
            addSubview(row)
            tabRows.append(row)
            tabRowSourceIndices.append(sourceIndex)
        }

        needsLayout = true
    }

    // MARK: - Tools Section

    private func handleSettingsChange() {
        let nextSnapshot = SettingsSnapshot.current(using: settings)
        guard nextSnapshot != settingsSnapshot else { return }

        let previousSnapshot = settingsSnapshot
        settingsSnapshot = nextSnapshot

        if nextSnapshot.isPinned != previousSnapshot.isPinned {
            applyPinnedState(nextSnapshot.isPinned)
        }

        if nextSnapshot.autoHideWhenFloating != previousSnapshot.autoHideWhenFloating {
            applyAutoHidePreference()
        }

        if nextSnapshot.showTools != previousSnapshot.showTools ||
            nextSnapshot.enabledToolIDs != previousSnapshot.enabledToolIDs {
            rebuildTools(using: nextSnapshot)
        }
    }

    private func rebuildTools(using snapshot: SettingsSnapshot) {
        let newTools = snapshot.showTools
            ? smartPanelRegistry.allPlugins.filter { snapshot.enabledToolIDs.contains($0.id) }
            : []

        // Skip rebuild if nothing changed
        if newTools.map(\.id) == enabledTools.map(\.id) && snapshot.showTools == !toolsHeaderLabel.isHidden {
            return
        }

        toolRows.forEach { $0.removeFromSuperview() }
        toolRows.removeAll()

        toolsHeaderLabel.isHidden = !snapshot.showTools
        toolsSeparator.isHidden = !snapshot.showTools

        // Clear active highlight if its plugin was removed
        if let active = activeToolID, !newTools.contains(where: { $0.id == active }) {
            activeToolID = nil
        }

        enabledTools = newTools

        for plugin in enabledTools {
            let isActive = plugin.id == activeToolID
            let row = SidebarToolRow(plugin: plugin, isActive: isActive)
            row.onSelect = { [weak self] in self?.handleToolSelected(plugin.id) }
            addSubview(row)
            toolRows.append(row)
        }

        // Tool visibility affects whether smart tabs should appear in the tabs list.
        rebuildTabs()
        needsLayout = true
    }

    private var shouldHideSmartTabsInTabList: Bool {
        settingsSnapshot.showTools && !enabledTools.isEmpty
    }

    private var shouldAutoHideWhenFloating: Bool {
        !isPinned && settingsSnapshot.autoHideWhenFloating
    }

    // MARK: - Tool Selection

    private func handleToolSelected(_ pluginID: String) {
        activeToolID = pluginID
        updateToolRowStates()
        onSelectTool?(pluginID)
    }

    /// Update the active tool highlight to match the currently selected tab.
    func setActiveToolID(_ pluginID: String?) {
        activeToolID = pluginID
        updateToolRowStates()
    }

    private func updateToolRowStates() {
        for (i, plugin) in enabledTools.enumerated() where i < toolRows.count {
            toolRows[i].setActive(plugin.id == activeToolID)
        }
    }

    private func updatePinButtonIcon() {
        let symbolName = isPinned ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isPinned ? "Unpin sidebar" : "Pin sidebar")
    }

    private func applyPinnedState(_ newPinnedState: Bool) {
        guard isPinned != newPinnedState else { return }

        isPinned = newPinnedState
        updatePinButtonIcon()
        pinButton.contentTintColor = isPinned ? Theme.textPrimary : Theme.textMuted
        Theme.animate { _ in
            self.pinButton.layer?.backgroundColor = (self.isPinned ? Theme.selectionFill.withAlphaComponent(0.65) : NSColor.clear).cgColor
        }
        pinButton.toolTip = isPinned ? "Unpin sidebar" : "Pin sidebar"

        if isPinned {
            show()
        } else if isExpanded, shouldAutoHideWhenFloating {
            scheduleHide()
        } else {
            hideTimer?.invalidate()
        }
    }

    private func applyAutoHidePreference() {
        hideTimer?.invalidate()
        guard isExpanded, shouldAutoHideWhenFloating else { return }
        scheduleHide()
    }

    @objc private func handlePinToggle() {
        let newPinnedState = !isPinned
        applyPinnedState(newPinnedState)
        settingsSnapshot = SettingsSnapshot(
            isPinned: newPinnedState,
            autoHideWhenFloating: settingsSnapshot.autoHideWhenFloating,
            showTools: settingsSnapshot.showTools,
            enabledToolIDs: settingsSnapshot.enabledToolIDs
        )
        settings.sidebarPinned = newPinnedState
    }

    override func layout() {
        super.layout()
        // PR Popover v2 rail layout: 56px column with 38x38 letter-glyph cards
        // stacked from the top, + button + tools stacked at the bottom.
        let cardSize: CGFloat = 38
        let cardSpacing: CGFloat = 6
        let topInset: CGFloat = 60   // leave room for traffic lights
        let bottomInset: CGFloat = 14
        let toolItemSize: CGFloat = 30
        let toolItemSpacing: CGFloat = 4

        let layoutWidth = max(bounds.width, Self.expandedWidth)
        let layoutBounds = NSRect(x: 0, y: 0, width: layoutWidth, height: bounds.height)

        noiseView.frame = layoutBounds
        topBand.frame = .zero
        trafficLightDock.frame = .zero
        trafficLightHalo.frame = .zero
        topBandSeparator.frame = .zero
        innerStroke.frame = layoutBounds.insetBy(dx: 1, dy: 1)
        innerStroke.cornerRadius = max(0, (layer?.cornerRadius ?? 12) - 1)
        topHighlight.frame = .zero
        edgeBlend.frame = .zero

        headerLabel.frame = .zero
        toolsHeaderLabel.frame = .zero
        toolsSeparator.frame = .zero
        pinButton.frame = .zero

        let cardX = floor((layoutBounds.width - cardSize) / 2)

        // Bottom cluster: + button on top, tool icons stacked beneath.
        let showTools = settingsSnapshot.showTools && !enabledTools.isEmpty
        var bottomCursor: CGFloat = bottomInset

        if showTools {
            for row in toolRows.reversed() {
                row.isHidden = false
                row.frame = NSRect(
                    x: floor((layoutBounds.width - toolItemSize) / 2),
                    y: bottomCursor,
                    width: toolItemSize,
                    height: toolItemSize
                )
                bottomCursor += toolItemSize + toolItemSpacing
            }
            // Subtle divider between + and tools.
            toolsSeparator.frame = NSRect(
                x: floor((layoutBounds.width - 22) / 2),
                y: bottomCursor + 4,
                width: 22,
                height: 1
            )
            bottomCursor += 12
        } else {
            for row in toolRows { row.isHidden = true }
        }

        let addButtonHeight: CGFloat = 30
        newTabButton.frame = NSRect(
            x: floor((layoutBounds.width - cardSize) / 2),
            y: bottomCursor,
            width: cardSize,
            height: addButtonHeight
        )
        // Dashed border traces the + tile.
        let dashedRect = newTabButton.frame.insetBy(dx: 0.5, dy: 0.5)
        newTabDashedBorder.frame = layoutBounds
        newTabDashedBorder.path = CGPath(
            roundedRect: dashedRect,
            cornerWidth: 7,
            cornerHeight: 7,
            transform: nil
        )
        bottomCursor += addButtonHeight + 8

        // Tab cards stacked from the top, clipping anything that runs into
        // the bottom cluster.
        let tabsTopY = layoutBounds.height - topInset
        let tabsBottomLimit = bottomCursor + 4

        var y = tabsTopY
        for row in tabRows {
            let cardBottom = y - cardSize
            if cardBottom < tabsBottomLimit {
                row.isHidden = true
            } else {
                row.isHidden = false
                row.frame = NSRect(x: cardX, y: cardBottom, width: cardSize, height: cardSize)
            }
            y -= cardSize + cardSpacing
        }
    }

    // MARK: - Tab Dragging

    private func beginDragSession(fromVisibleIndex visibleIndex: Int, event: NSEvent, dragView: NSView) {
        guard dragSourceIndex == nil,
              visibleIndex >= 0, visibleIndex < tabRowSourceIndices.count,
              let windowIdentifier = effectiveWindowIdentifier else { return }

        let sourceTabIndex = tabRowSourceIndices[visibleIndex]
        guard tabs.indices.contains(sourceTabIndex),
              let draggingImage = dragImage(for: dragView) else { return }

        let payload = TabDragPayload(sourceWindowID: windowIdentifier, tabID: tabs[sourceTabIndex].id)
        let pasteboardItem = NSPasteboardItem()
        payload.set(on: pasteboardItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(dragView.bounds, contents: draggingImage)

        dragSourceIndex = visibleIndex
        localDragSourceVisibleIndex = nil
        dragInsertionIndex = nil
        isDropAccepted = false
        ensureDragIndicator()
        dragIndicatorLayer?.isHidden = true

        let session = dragView.beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
        session.draggingFormation = .none
    }

    private func dragImage(for view: NSView) -> NSImage? {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return nil }

        if let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: representation)
            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(representation)
            return image
        }

        let pdfData = view.dataWithPDF(inside: view.bounds)
        return NSImage(data: pdfData)
    }

    private func handleLocalDragMoved(fromVisibleIndex visibleIndex: Int, event: NSEvent, dragView: NSView) {
        // Once a system drag session starts, NSDraggingSource owns the lifecycle.
        if dragSourceIndex != nil { return }

        let location = convert(event.locationInWindow, from: nil)

        if localDragSourceVisibleIndex == nil {
            localDragSourceVisibleIndex = visibleIndex
            ensureDragIndicator()
        }

        if !bounds.insetBy(dx: -12, dy: -8).contains(location) {
            beginDragSession(fromVisibleIndex: visibleIndex, event: event, dragView: dragView)
            return
        }

        dragInsertionIndex = visibleInsertionIndex(for: location)
        updateDragIndicatorFrame()
    }

    private func handleLocalDragEnded(fromVisibleIndex visibleIndex: Int, event: NSEvent) {
        // System drag session already running — let NSDraggingSource finish it.
        guard dragSourceIndex == nil else { return }
        defer { clearDragState() }

        guard localDragSourceVisibleIndex == visibleIndex,
              visibleIndex < tabRowSourceIndices.count else { return }

        let location = convert(event.locationInWindow, from: nil)
        let insertion = dragInsertionIndex ?? visibleInsertionIndex(for: location)
        let requestedInsertionIndex = sourceInsertionIndex(forVisibleInsertionIndex: insertion)
        let sourceTabIndex = tabRowSourceIndices[visibleIndex]
        let destinationIndex = Self.reorderDestinationIndex(
            sourceIndex: sourceTabIndex,
            insertionIndex: requestedInsertionIndex,
            tabCount: tabs.count
        )

        if destinationIndex != sourceTabIndex {
            onReorderTab?(sourceTabIndex, destinationIndex)
        }
    }

    private func ensureDragIndicator() {
        guard dragIndicatorLayer == nil else { return }
        let indicator = CALayer()
        indicator.backgroundColor = Theme.accent.withAlphaComponent(0.5).cgColor
        indicator.cornerRadius = 1
        layer?.addSublayer(indicator)
        dragIndicatorLayer = indicator
    }

    private func clearDragState() {
        dragSourceIndex = nil
        localDragSourceVisibleIndex = nil
        dragInsertionIndex = nil
        isDropAccepted = false
        dragIndicatorLayer?.removeFromSuperlayer()
        dragIndicatorLayer = nil
    }

    private func visibleInsertionIndex(for location: NSPoint) -> Int {
        guard !tabRows.isEmpty else { return 0 }

        for (index, row) in tabRows.enumerated() {
            if location.y > row.frame.midY {
                return index
            }
        }

        return tabRows.count
    }

    func sourceInsertionIndex(forVisibleInsertionIndex visibleInsertionIndex: Int) -> Int {
        guard !tabRowSourceIndices.isEmpty else { return 0 }
        let clampedVisibleIndex = max(0, min(visibleInsertionIndex, tabRowSourceIndices.count))

        if clampedVisibleIndex <= 0 {
            return tabRowSourceIndices[0]
        }
        if clampedVisibleIndex >= tabRowSourceIndices.count {
            return min((tabRowSourceIndices.last ?? -1) + 1, tabs.count)
        }
        return tabRowSourceIndices[clampedVisibleIndex]
    }

    private func updateDragIndicatorFrame() {
        guard let dragIndicatorLayer,
              let dragInsertionIndex else {
            self.dragIndicatorLayer?.isHidden = true
            return
        }

        let indicatorX = 18.0
        let indicatorWidth = max(0, bounds.width - 36)
        let indicatorY: CGFloat
        if tabRows.isEmpty {
            indicatorY = headerLabel.frame.minY - 24
        } else if dragInsertionIndex <= 0 {
            indicatorY = tabRows[0].frame.maxY + 2
        } else if dragInsertionIndex >= tabRows.count {
            indicatorY = tabRows[tabRows.count - 1].frame.minY - 3
        } else {
            indicatorY = tabRows[dragInsertionIndex].frame.maxY + 2
        }

        dragIndicatorLayer.frame = NSRect(x: indicatorX, y: indicatorY, width: indicatorWidth, height: 2)
        dragIndicatorLayer.isHidden = false
    }

    static func reorderDestinationIndex(sourceIndex: Int, insertionIndex: Int, tabCount: Int) -> Int {
        guard tabCount > 0 else { return 0 }
        let clampedInsertion = max(0, min(insertionIndex, tabCount))
        let adjustedIndex = clampedInsertion > sourceIndex ? clampedInsertion - 1 : clampedInsertion
        return max(0, min(adjustedIndex, tabCount - 1))
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let tabID: UUID?
        if let dragSourceIndex, dragSourceIndex < tabRowSourceIndices.count {
            let sourceTabIndex = tabRowSourceIndices[dragSourceIndex]
            tabID = tabs.indices.contains(sourceTabIndex) ? tabs[sourceTabIndex].id : nil
        } else {
            tabID = nil
        }
        let shouldTearOff = operation == [] && !isDropAccepted
        clearDragState()

        guard shouldTearOff, let tabID else { return }
        onTearOffTab?(tabID, screenPoint)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard TabDragPayload.read(from: sender.draggingPasteboard) != nil else {
            dragInsertionIndex = nil
            updateDragIndicatorFrame()
            return []
        }

        ensureDragIndicator()
        dragInsertionIndex = visibleInsertionIndex(for: convert(sender.draggingLocation, from: nil))
        updateDragIndicatorFrame()
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragInsertionIndex = nil
        updateDragIndicatorFrame()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        TabDragPayload.read(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let payload = TabDragPayload.read(from: sender.draggingPasteboard) else { return false }
        let dropVisibleInsertionIndex = dragInsertionIndex ?? visibleInsertionIndex(for: convert(sender.draggingLocation, from: nil))
        let requestedInsertionIndex = sourceInsertionIndex(forVisibleInsertionIndex: dropVisibleInsertionIndex)
        let sourceTabIndex = tabs.firstIndex(where: { $0.id == payload.tabID })

        if payload.sourceWindowID == effectiveWindowIdentifier, let sourceTabIndex {
            let destinationIndex = Self.reorderDestinationIndex(
                sourceIndex: sourceTabIndex,
                insertionIndex: requestedInsertionIndex,
                tabCount: tabs.count
            )
            if destinationIndex != sourceTabIndex {
                onReorderTab?(sourceTabIndex, destinationIndex)
            }
        } else {
            onReceiveDraggedTab?(payload, requestedInsertionIndex)
        }

        isDropAccepted = true
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dragInsertionIndex = nil
        updateDragIndicatorFrame()
    }

    // MARK: - Show / Hide

    func toggle() {
        if isExpanded { hide() } else { show() }
    }

    func show() {
        guard !isExpanded else { return }
        isExpanded = true
        hideTimer?.invalidate()
        onExpandChanged?(true)
        if shouldAutoHideWhenFloating { scheduleHide() }
    }

    func hide() {
        guard isExpanded, !isPinned else { return }
        isExpanded = false
        hideTimer?.invalidate()
        onExpandChanged?(false)
    }

    private func scheduleHide() {
        guard !isPinned else { return }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hideTimer?.invalidate()
        if let info = event.trackingArea?.userInfo, info["target"] as? String == "newTab" {
            isNewTabHovered = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let info = event.trackingArea?.userInfo, info["target"] as? String == "newTab" {
            isNewTabHovered = false
            return
        }
        if isExpanded && shouldAutoHideWhenFloating { scheduleHide() }
    }

    func hideAfterSelectionIfNeeded() {
        guard shouldAutoHideWhenFloating else { return }
        hide()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))

        // Dedicated tracking area for the + tile so we can flash a hover state
        // without piggybacking on the sidebar-wide tracker.
        if let area = newTabTrackingAreaForHover { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: newTabButton.frame,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: ["target": "newTab"]
        )
        addTrackingArea(area)
        newTabTrackingAreaForHover = area
    }

    private func applyNewTabHoverAppearance() {
        let activeColor = isNewTabHovered ? Theme.textPrimary : Theme.textSecondary
        let strokeColor: CGColor = isNewTabHovered
            ? Theme.chromeHairline.withAlphaComponent(Theme.colors.isLight ? 0.95 : 0.78).cgColor
            : Theme.chromeHairline.withAlphaComponent(Theme.colors.isLight ? 0.55 : 0.45).cgColor
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            newTabButton.contentTintColor = activeColor
            newTabDashedBorder.strokeColor = strokeColor
        }
    }

    @objc private func handleNewTab() {
        onNewTab?()
    }

    // MARK: - Theme Update

    func refreshTheme() {
        applySidebarChrome()
        rebuildTabs()
        rebuildTools(using: settingsSnapshot)
    }
}
