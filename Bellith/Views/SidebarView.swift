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

// MARK: - Sidebar Tab Row

fileprivate final class SidebarTabRow: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onDragMoved: ((NSEvent) -> Void)?
    var onDragEnded: ((NSEvent) -> Void)?
    var onRightClick: ((NSPoint) -> Void)?
    private var isDragging = false
    private var mouseDownLocation: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }

    private let selectionIndicator = CALayer()
    private let glyphLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let badgeContainer = CALayer()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let title: String
    private let isSelected: Bool
    private let kind: TerminalContainerView.TabKind
    private let smartPanelRegistry: SmartPanelRegistry
    private var isHovered = false
    private var hotkeyDigit: Int?
    private var paneCount: Int = 1
    private weak var hoverTipView: WorkspaceTipView?
    private var hoverTipShowWorkItem: DispatchWorkItem?

    private var isSmartTab: Bool {
        if case .smart = kind { return true }
        return false
    }

    /// PR Popover v2 hue per workspace, derived deterministically from the title.
    /// Returns a hue value usable for tinted gradient.
    private var workspaceHue: CGFloat { WorkspaceTint.hue(for: title) }

    init(
        title: String,
        isSelected: Bool,
        kind: TerminalContainerView.TabKind,
        smartPanelRegistry: SmartPanelRegistry
    ) {
        self.title = title
        self.isSelected = isSelected
        self.kind = kind
        self.smartPanelRegistry = smartPanelRegistry
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.masksToBounds = false

        setAccessibilityRole(.button)
        setAccessibilityLabel("Tab: \(title)")
        setAccessibilityValue(isSelected ? "selected" : "")
        toolTip = title

        selectionIndicator.cornerRadius = 1.5
        selectionIndicator.cornerCurve = .continuous
        layer?.addSublayer(selectionIndicator)

        glyphLabel.font = BellithFont.mono(15, weight: .semibold)
        glyphLabel.alignment = .center
        glyphLabel.isEditable = false
        glyphLabel.isBezeled = false
        glyphLabel.drawsBackground = false
        glyphLabel.maximumNumberOfLines = 1
        addSubview(glyphLabel)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.isHidden = true
        addSubview(iconView)

        if case .smart(let pluginID) = kind,
           let plugin = smartPanelRegistry.plugin(for: pluginID) {
            iconView.image = NSImage(systemSymbolName: plugin.iconName, accessibilityDescription: nil)
            iconView.isHidden = false
            glyphLabel.stringValue = ""
        } else {
            glyphLabel.stringValue = Self.makeGlyph(from: title)
        }

        badgeContainer.cornerRadius = 6
        badgeContainer.cornerCurve = .continuous
        badgeContainer.borderWidth = 1
        layer?.addSublayer(badgeContainer)

        badgeLabel.font = BellithFont.mono(8.5, weight: .semibold)
        badgeLabel.alignment = .center
        badgeLabel.isEditable = false
        badgeLabel.isBezeled = false
        badgeLabel.drawsBackground = false
        badgeLabel.stringValue = ""
        badgeLabel.maximumNumberOfLines = 1
        addSubview(badgeLabel)

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let bounds = self.bounds

        // 3px accent strip flush with the rail's left edge. Card is centered in
        // the 56px rail (so card.x ≈ 9), so x = -9 puts the strip at rail.x = 0.
        selectionIndicator.frame = NSRect(x: -9, y: 8, width: 3, height: max(0, bounds.height - 16))

        let glyphSize = NSSize(width: bounds.width, height: 18)
        glyphLabel.frame = NSRect(
            x: 0,
            y: floor((bounds.height - glyphSize.height) / 2),
            width: glyphSize.width,
            height: glyphSize.height
        )

        let iconSize: CGFloat = 16
        iconView.frame = NSRect(
            x: floor((bounds.width - iconSize) / 2),
            y: floor((bounds.height - iconSize) / 2),
            width: iconSize,
            height: iconSize
        )

        // Pane-count badge anchored to bottom-right.
        let badgeText = badgeLabel.stringValue
        let badgeIntrinsic = badgeLabel.intrinsicContentSize
        let badgeW = badgeText.isEmpty ? 0 : max(14, ceil(badgeIntrinsic.width) + 8)
        let badgeH: CGFloat = 13
        let badgeX = bounds.width - badgeW + 2
        let badgeY: CGFloat = -2
        badgeContainer.frame = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
        badgeLabel.frame = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
    }

    func setPaneCount(_ count: Int) {
        paneCount = count
        if count <= 1 {
            badgeLabel.stringValue = ""
        } else {
            badgeLabel.stringValue = "\(count)"
        }
        updateAppearance()
        needsLayout = true
    }

    func setHotkeyDigit(_ digit: Int?) {
        hotkeyDigit = digit
        // System tooltip kept as a fallback (e.g. for VoiceOver) — the rich
        // floating tip view replaces it visually on hover.
        if let digit, (1...9).contains(digit) {
            toolTip = "\(title)  ⌘\(digit)"
        } else {
            toolTip = title
        }
    }

    private static func makeGlyph(from title: String) -> String {
        guard let first = title.unicodeScalars.first(where: { $0.properties.isAlphabetic || ("0"..."9").contains(Character($0)) }) else {
            return "•"
        }
        return String(first).uppercased()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        scheduleShowHoverTip()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        hideHoverTip()
    }

    private func scheduleShowHoverTip() {
        hoverTipShowWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showHoverTip() }
        hoverTipShowWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func showHoverTip() {
        guard isHovered, hoverTipView == nil, let window = window else { return }

        let tip = WorkspaceTipView(
            title: title,
            hotkeyDigit: hotkeyDigit,
            paneCount: paneCount,
            tint: WorkspaceTint.accent(for: title)
        )
        tip.alphaValue = 0
        window.contentView?.addSubview(tip)

        // Position the tip just to the right of the card, vertically centered.
        let cardOriginInWindow = convert(bounds, to: window.contentView)
        let tipSize = tip.intrinsicContentSize
        let tipX = cardOriginInWindow.maxX + 10
        let tipY = cardOriginInWindow.midY - tipSize.height / 2
        tip.frame = NSRect(x: tipX, y: tipY, width: tipSize.width, height: tipSize.height)

        hoverTipView = tip
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            tip.animator().alphaValue = 1
        }
    }

    private func hideHoverTip() {
        hoverTipShowWorkItem?.cancel()
        hoverTipShowWorkItem = nil
        guard let tip = hoverTipView else { return }
        hoverTipView = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            tip.animator().alphaValue = 0
        } completionHandler: {
            tip.removeFromSuperview()
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let loc = event.locationInWindow
        if !isDragging && hypot(loc.x - start.x, loc.y - start.y) > 4 {
            isDragging = true
        }
        if isDragging { onDragMoved?(event) }
    }

    override func mouseUp(with event: NSEvent) {
        let shouldSelect = !isDragging
        if isDragging { onDragEnded?(event) }
        isDragging = false
        mouseDownLocation = nil
        // Fire selection after drag handling so refreshTabUI doesn't rebuild the row mid-interaction.
        if shouldSelect { onSelect?() }
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick?(event.locationInWindow) }
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }

    private func updateAppearance() {
        let hue = workspaceHue
        let backgroundColor: CGColor
        let borderColor: CGColor
        let glyphColor: NSColor
        let iconColor: NSColor
        let indicatorColor: CGColor
        let badgeFillColor: CGColor
        let badgeBorderColor: CGColor
        let badgeTextColor: NSColor
        let shadowOpacity: Float

        let isLight = Theme.colors.isLight
        // Tinted bg pulled toward the surface gray so the active card glows
        // gently rather than screaming. The saturated accent is reserved for
        // the strip, border, glyph, and badge.
        let huedTint = NSColor(deviceHue: hue / 360, saturation: 0.30, brightness: isLight ? 0.92 : 0.62, alpha: 1)
        let huedAccent = WorkspaceTint.accent(for: title)

        if isSelected {
            backgroundColor = huedTint.withAlphaComponent(isLight ? 0.16 : 0.20).cgColor
            borderColor = huedAccent.withAlphaComponent(0.55).cgColor
            glyphColor = huedAccent
            iconColor = huedAccent
            indicatorColor = huedAccent.cgColor
            badgeFillColor = (isLight ? NSColor.white : Theme.frame).cgColor
            badgeBorderColor = huedAccent.withAlphaComponent(0.7).cgColor
            badgeTextColor = huedAccent
            shadowOpacity = 0.35
        } else if isHovered {
            backgroundColor = Theme.chromeElevated.withAlphaComponent(isLight ? 0.55 : 0.55).cgColor
            borderColor = Theme.chromeHairline.withAlphaComponent(0.4).cgColor
            glyphColor = Theme.textPrimary
            iconColor = Theme.textPrimary
            indicatorColor = NSColor.clear.cgColor
            badgeFillColor = Theme.frame.cgColor
            badgeBorderColor = Theme.chromeHairline.cgColor
            badgeTextColor = Theme.textSecondary
            shadowOpacity = 0
        } else {
            backgroundColor = NSColor.clear.cgColor
            borderColor = NSColor.clear.cgColor
            glyphColor = Theme.textSecondary
            iconColor = Theme.textSecondary
            indicatorColor = NSColor.clear.cgColor
            badgeFillColor = Theme.frame.cgColor
            badgeBorderColor = Theme.chromeHairline.cgColor
            badgeTextColor = Theme.textTertiary
            shadowOpacity = 0
        }

        layer?.shadowColor = huedAccent.withAlphaComponent(0.4).cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            self.layer?.backgroundColor = backgroundColor
            self.layer?.borderColor = borderColor
            self.selectionIndicator.backgroundColor = indicatorColor
            self.glyphLabel.animator().textColor = glyphColor
            self.iconView.animator().contentTintColor = iconColor
            self.badgeContainer.backgroundColor = badgeFillColor
            self.badgeContainer.borderColor = badgeBorderColor
            self.badgeContainer.opacity = self.badgeLabel.stringValue.isEmpty ? 0 : 1
            self.badgeLabel.animator().textColor = badgeTextColor
        }
    }
}

// MARK: - Sidebar Tool Row

fileprivate final class SidebarToolRow: NSView {
    var onSelect: (() -> Void)?
    private let plugin: SmartPanelPlugin
    private let iconView = NSImageView()
    private let tooltipText: String
    private var isHovered = false
    private var isActive = false

    init(plugin: SmartPanelPlugin, isActive: Bool = false) {
        self.plugin = plugin
        self.tooltipText = "\(plugin.title)\n\(plugin.commandDescription)"
        self.isActive = isActive
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        iconView.image = NSImage(systemSymbolName: plugin.iconName, accessibilityDescription: plugin.title)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.toolTip = tooltipText
        addSubview(iconView)

        setAccessibilityRole(.button)
        setAccessibilityLabel(plugin.title)
        setAccessibilityHelp(plugin.commandDescription)
        toolTip = tooltipText

        applyStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        applyStyle()
    }

    private func applyStyle() {
        let backgroundColor: NSColor
        let borderColor: NSColor
        let iconColor: NSColor

        if isActive {
            backgroundColor = Theme.textPrimary.withAlphaComponent(Theme.colors.isLight ? 0.08 : 0.14)
            borderColor = Theme.textPrimary.withAlphaComponent(Theme.colors.isLight ? 0.12 : 0.18)
            iconColor = Theme.accent
            layer?.shadowOpacity = 0
        } else if isHovered {
            backgroundColor = Theme.hoverOverlay
            borderColor = Theme.borderSubtle
            iconColor = Theme.textPrimary
            layer?.shadowOpacity = 0
        } else {
            backgroundColor = NSColor.clear
            borderColor = NSColor.clear
            iconColor = Theme.textPrimary.withAlphaComponent(Theme.colors.isLight ? 0.68 : 0.72)
            layer?.shadowOpacity = 0
        }

        iconView.contentTintColor = iconColor
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderColor = borderColor.cgColor
    }

    override func layout() {
        super.layout()
        let iconSize = min(bounds.width, bounds.height) - 14
        iconView.frame = NSRect(
            x: (bounds.width - iconSize) / 2,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            self.applyStyle()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            self.applyStyle()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }
}

// MARK: - Noise Overlay

fileprivate final class SidebarNoiseView: NSView {
    private var cachedSize: CGSize = .zero
    private var cachedIsLight = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        refreshTheme()
    }

    func refreshTheme() {
        let size = bounds.size
        let isLight = Theme.colors.isLight
        guard size.width > 0, size.height > 0 else { return }
        guard size != cachedSize || isLight != cachedIsLight || layer?.contents == nil else { return }

        cachedSize = size
        cachedIsLight = isLight
        layer?.contents = makeNoiseImage(tileSize: NSSize(width: 72, height: 72), isLight: isLight)
        layer?.contentsCenter = CGRect(x: 0.49, y: 0.49, width: 0.02, height: 0.02)
        layer?.contentsGravity = .resizeAspectFill
        layer?.opacity = isLight ? 0.055 : 0.08
    }

    private func makeNoiseImage(tileSize: NSSize, isLight: Bool) -> CGImage? {
        let width = max(1, Int(tileSize.width))
        let height = max(1, Int(tileSize.height))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let base = isLight ? 0.0 : 1.0
        let majorCount = 320
        let minorCount = 110

        for _ in 0..<majorCount {
            let x = CGFloat(Int.random(in: 0..<width))
            let y = CGFloat(Int.random(in: 0..<height))
            let alpha = CGFloat.random(in: isLight ? 0.006...0.016 : 0.008...0.02)
            context.setFillColor(NSColor(white: base, alpha: alpha).cgColor)
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }

        for _ in 0..<minorCount {
            let x = CGFloat(Int.random(in: 0..<width))
            let y = CGFloat(Int.random(in: 0..<height))
            let alpha = CGFloat.random(in: isLight ? 0.002...0.008 : 0.003...0.01)
            context.setFillColor(Theme.accent.withAlphaComponent(alpha).cgColor)
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }

        return context.makeImage()
    }
}

// MARK: - Workspace Card Hover Tip

/// Floating tooltip view that mirrors the design's `.tip`: a dark glass pill with
/// the workspace name, an aligned hotkey badge, and a sub-line for pane count.
fileprivate final class WorkspaceTipView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let hotkeyKbd = KbdView()
    private let subLabel = NSTextField(labelWithString: "")
    private let borderLayer = CALayer()
    private let backgroundLayer = CALayer()
    private let tint: NSColor

    init(title: String, hotkeyDigit: Int?, paneCount: Int, tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)
        wantsLayer = true
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.55).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.masksToBounds = false

        backgroundLayer.cornerRadius = 6
        backgroundLayer.cornerCurve = .continuous
        backgroundLayer.masksToBounds = true
        layer?.addSublayer(backgroundLayer)

        borderLayer.cornerRadius = 6
        borderLayer.cornerCurve = .continuous
        borderLayer.borderWidth = 1
        borderLayer.borderColor = Theme.chromeHairline.withAlphaComponent(0.7).cgColor
        layer?.addSublayer(borderLayer)

        titleLabel.stringValue = title
        titleLabel.font = BellithFont.mono(11.5, weight: .medium)
        titleLabel.textColor = tint
        titleLabel.isEditable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        if let digit = hotkeyDigit, (1...9).contains(digit) {
            hotkeyKbd.text = "⌘\(digit)"
            addSubview(hotkeyKbd)
        }

        let countText = paneCount > 1 ? "\(paneCount) panes" : "1 pane"
        subLabel.stringValue = countText
        subLabel.font = BellithFont.mono(10, weight: .regular)
        subLabel.textColor = Theme.textTertiary
        subLabel.isEditable = false
        subLabel.isBezeled = false
        subLabel.drawsBackground = false
        addSubview(subLabel)

        applyBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func applyBackground() {
        let isLight = Theme.colors.isLight
        backgroundLayer.backgroundColor = (isLight
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor(white: 0.10, alpha: 0.96)).cgColor
    }

    override var intrinsicContentSize: NSSize {
        let titleW = ceil(titleLabel.attributedStringValue.size().width)
        let kbdW = hotkeyKbd.superview != nil ? ceil(hotkeyKbd.intrinsicContentSize.width) + 8 : 0
        let subW = ceil(subLabel.attributedStringValue.size().width)
        let topRow = titleW + kbdW
        let width = max(topRow, subW) + 18
        return NSSize(width: max(120, width), height: 38)
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
        borderLayer.frame = bounds

        let titleSize = titleLabel.attributedStringValue.size()
        titleLabel.frame = NSRect(
            x: 9,
            y: bounds.height - 7 - 14,
            width: ceil(titleSize.width) + 2,
            height: 14
        )
        if hotkeyKbd.superview != nil {
            let kbdSize = hotkeyKbd.intrinsicContentSize
            hotkeyKbd.frame = NSRect(
                x: bounds.width - kbdSize.width - 9,
                y: bounds.height - 6 - kbdSize.height,
                width: kbdSize.width,
                height: kbdSize.height
            )
        }
        subLabel.frame = NSRect(
            x: 9,
            y: 5,
            width: bounds.width - 18,
            height: 12
        )
    }
}
