import AppKit
import QuartzCore

/// Monochrome utility sidebar with restrained chrome and strong type hierarchy.
final class SidebarView: NSView {
    typealias TabModel = (id: UUID, title: String, kind: TerminalContainerView.TabKind)

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

    static let expandedWidth: CGFloat = 216

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

    /// Called when a tool is clicked in the sidebar. The container opens it in the main content area.
    var onSelectTool: ((String) -> Void)?

    private var newTabTrackingArea: NSTrackingArea?
    private var dragSourceIndex: Int?
    private var dragIndicatorLayer: CALayer?
    private let pinButton = NSButton()
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

        headerLabel.stringValue = "WORKSPACE"
        headerLabel.font = BellithFont.mono(11, weight: .regular)
        headerLabel.textColor = Theme.textSecondary
        headerLabel.isEditable = false
        headerLabel.isBezeled = false
        headerLabel.drawsBackground = false
        addSubview(headerLabel)

        toolsHeaderLabel.stringValue = "TOOLS"
        toolsHeaderLabel.font = BellithFont.mono(11, weight: .regular)
        toolsHeaderLabel.textColor = Theme.textMuted
        toolsHeaderLabel.isEditable = false
        toolsHeaderLabel.isBezeled = false
        toolsHeaderLabel.drawsBackground = false
        addSubview(toolsHeaderLabel)

        newTabButton.title = ""
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.contentTintColor = Theme.textSecondary
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTab)
        configureHeaderButton(newTabButton)
        addSubview(newTabButton)

        pinButton.title = ""
        updatePinButtonIcon()
        pinButton.contentTintColor = isPinned ? Theme.textPrimary : Theme.textMuted
        pinButton.target = self
        pinButton.action = #selector(handlePinToggle)
        pinButton.toolTip = isPinned ? "Unpin sidebar" : "Pin sidebar"
        configureHeaderButton(pinButton)
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
        toolsHeaderLabel.textColor = Theme.textMuted
        noiseView.alphaValue = 0
        noiseView.refreshTheme()
        newTabButton.contentTintColor = Theme.textSecondary
        newTabButton.layer?.backgroundColor = NSColor.clear.cgColor
        newTabButton.layer?.borderColor = Theme.borderSubtle.cgColor
        pinButton.contentTintColor = isPinned ? Theme.textPrimary : Theme.textMuted
        pinButton.layer?.backgroundColor = (isPinned ? Theme.selectionFill.withAlphaComponent(0.65) : NSColor.clear).cgColor
        pinButton.layer?.borderColor = Theme.borderSubtle.cgColor
    }

    func update(tabs: [(id: UUID, title: String, kind: TerminalContainerView.TabKind)], selectedIndex: Int) {
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
            row.onSelect = { [weak self] in self?.onSelectTab?(sourceIndex) }
            row.onClose = { [weak self] in self?.onCloseTab?(sourceIndex) }
            row.onDragBegan = { [weak self] in self?.beginDrag(fromIndex: visibleIndex) }
            row.onDragMoved = { [weak self] loc in self?.updateDrag(location: loc) }
            row.onDragEnded = { [weak self] in self?.endDrag() }
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
        let sideInset: CGFloat = 14
        let topBandHeight: CGFloat = 0
        let headerTopInset: CGFloat = 42
        let rowHeight: CGFloat = 34
        let rowSpacing: CGFloat = 6
        let toolItemSize: CGFloat = 28
        let toolItemSpacing: CGFloat = 8
        let layoutWidth = max(bounds.width, Self.expandedWidth)
        let layoutBounds = NSRect(x: 0, y: 0, width: layoutWidth, height: bounds.height)

        noiseView.frame = layoutBounds
        topBand.frame = NSRect(x: 0, y: layoutBounds.height - topBandHeight, width: layoutBounds.width, height: topBandHeight)
        trafficLightDock.frame = .zero
        trafficLightHalo.frame = .zero
        topBandSeparator.frame = NSRect(
            x: sideInset,
            y: layoutBounds.height - topBandHeight,
            width: max(0, layoutBounds.width - sideInset * 2),
            height: 1
        )
        innerStroke.frame = layoutBounds.insetBy(dx: 1, dy: 1)
        innerStroke.cornerRadius = max(0, (layer?.cornerRadius ?? 12) - 1)
        topHighlight.frame = .zero
        edgeBlend.frame = .zero

        let visibleTabCount = tabRows.count
        headerLabel.stringValue = visibleTabCount > 0 ? "WORKSPACE (\(visibleTabCount))" : "WORKSPACE"
        headerLabel.frame = NSRect(
            x: sideInset,
            y: layoutBounds.height - headerTopInset,
            width: layoutBounds.width - sideInset * 2 - 68,
            height: 14
        )

        newTabButton.frame = NSRect(
            x: layoutBounds.width - sideInset - 50,
            y: layoutBounds.height - headerTopInset - 6,
            width: 24,
            height: 24
        )
        pinButton.frame = NSRect(
            x: layoutBounds.width - sideInset - 24,
            y: layoutBounds.height - headerTopInset - 6,
            width: 24,
            height: 24
        )

        let showTools = settingsSnapshot.showTools && !enabledTools.isEmpty
        let contentWidth = layoutBounds.width - sideInset * 2

        let tabBottomLimit: CGFloat
        if showTools {
            let toolsBottomInset: CGFloat = 18
            let toolColumnCount = max(1, Int((contentWidth + toolItemSpacing) / (toolItemSize + toolItemSpacing)))
            let toolRowCount = Int(ceil(Double(toolRows.count) / Double(toolColumnCount)))
            let toolGridHeight = CGFloat(toolRowCount) * toolItemSize
                + CGFloat(max(0, toolRowCount - 1)) * toolItemSpacing
            let toolGridTopY = toolsBottomInset + toolGridHeight

            for (index, row) in toolRows.enumerated() {
                let gridRow = index / toolColumnCount
                let gridColumn = index % toolColumnCount
                let rowY = toolGridTopY
                    - CGFloat(gridRow + 1) * toolItemSize
                    - CGFloat(gridRow) * toolItemSpacing
                let rowX = sideInset + CGFloat(gridColumn) * (toolItemSize + toolItemSpacing)
                row.isHidden = false
                row.frame = NSRect(x: rowX, y: rowY, width: toolItemSize, height: toolItemSize)
            }

            toolsHeaderLabel.frame = NSRect(
                x: sideInset,
                y: toolGridTopY + 10,
                width: contentWidth,
                height: 13
            )
            toolsSeparator.frame = NSRect(
                x: sideInset,
                y: toolsHeaderLabel.frame.maxY + 9,
                width: contentWidth,
                height: 1
            )
            tabBottomLimit = toolsSeparator.frame.maxY + 18
        } else {
            toolsSeparator.frame = .zero
            toolsHeaderLabel.frame = .zero
            for row in toolRows {
                row.isHidden = true
            }
            tabBottomLimit = 16
        }

        var y = headerLabel.frame.minY - 18
        for row in tabRows {
            if y - rowHeight < tabBottomLimit {
                row.isHidden = true
            } else {
                row.isHidden = false
                row.frame = NSRect(x: sideInset, y: y - rowHeight, width: contentWidth, height: rowHeight)
            }
            y -= rowHeight + rowSpacing
        }
    }

    // MARK: - Tab Reordering

    private func beginDrag(fromIndex: Int) {
        dragSourceIndex = fromIndex
        if dragIndicatorLayer == nil {
            let indicator = CALayer()
            indicator.backgroundColor = Theme.accent.withAlphaComponent(0.5).cgColor
            indicator.cornerRadius = 1
            layer?.addSublayer(indicator)
            dragIndicatorLayer = indicator
        }
    }

    private func updateDrag(location: NSPoint) {
        guard let sourceIdx = dragSourceIndex else { return }
        let loc = convert(location, from: nil)

        var targetIdx: Int?
        for (i, row) in tabRows.enumerated() {
            if loc.y >= row.frame.minY && loc.y <= row.frame.maxY {
                targetIdx = i
                break
            }
        }

        if let target = targetIdx, target != sourceIdx {
            let row = tabRows[target]
            let indicatorY = target < sourceIdx ? row.frame.maxY + 1 : row.frame.minY - 2
            dragIndicatorLayer?.frame = NSRect(x: row.frame.minX + 4, y: indicatorY, width: row.frame.width - 8, height: 2)
            dragIndicatorLayer?.isHidden = false
        } else {
            dragIndicatorLayer?.isHidden = true
        }
    }

    private func endDrag() {
        guard let sourceIdx = dragSourceIndex else { return }
        dragIndicatorLayer?.removeFromSuperlayer()
        dragIndicatorLayer = nil

        var targetIdx = sourceIdx

        if let window = window {
            let loc = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            for (i, row) in tabRows.enumerated() {
                if loc.y >= row.frame.minY && loc.y <= row.frame.maxY && i != sourceIdx {
                    targetIdx = i
                    break
                }
            }
        }

        dragSourceIndex = nil

        if targetIdx != sourceIdx,
           sourceIdx < tabRowSourceIndices.count,
           targetIdx < tabRowSourceIndices.count {
            let sourceTabIndex = tabRowSourceIndices[sourceIdx]
            let targetTabIndex = tabRowSourceIndices[targetIdx]
            onReorderTab?(sourceTabIndex, targetTabIndex)
        }
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
        let loc = convert(event.locationInWindow, from: nil)
        if newTabButton.frame.insetBy(dx: -4, dy: -4).contains(loc) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Theme.animFast
                ctx.allowsImplicitAnimation = true
                self.newTabButton.layer?.backgroundColor = Theme.hoverOverlay.cgColor
                self.newTabButton.layer?.borderColor = Theme.border.cgColor
                self.newTabButton.contentTintColor = Theme.textPrimary
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        if isExpanded && shouldAutoHideWhenFloating { scheduleHide() }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            self.newTabButton.layer?.backgroundColor = NSColor.clear.cgColor
            self.newTabButton.layer?.borderColor = Theme.borderSubtle.cgColor
            self.newTabButton.contentTintColor = Theme.textSecondary
        }
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
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var onRightClick: ((NSPoint) -> Void)?
    private var isDragging = false
    private var mouseDownLocation: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }

    private let selectionIndicator = CALayer()
    private let iconPlate = CALayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let isSelected: Bool
    private let kind: TerminalContainerView.TabKind
    private let smartPanelRegistry: SmartPanelRegistry
    private var isHovered = false

    private var isSmartTab: Bool {
        if case .smart = kind { return true }
        return false
    }

    init(
        title: String,
        isSelected: Bool,
        kind: TerminalContainerView.TabKind,
        smartPanelRegistry: SmartPanelRegistry
    ) {
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

        selectionIndicator.cornerRadius = 1.5
        selectionIndicator.cornerCurve = .continuous
        layer?.addSublayer(selectionIndicator)

        iconPlate.cornerRadius = 6
        iconPlate.cornerCurve = .continuous
        iconPlate.borderWidth = 1
        layer?.addSublayer(iconPlate)

        let symbolName: String
        if case .smart(let pluginID) = kind,
           let plugin = smartPanelRegistry.plugin(for: pluginID) {
            symbolName = plugin.iconName
        } else {
            symbolName = "folder.fill"
        }
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = BellithFont.ui(12, weight: isSelected ? .semibold : .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        closeButton.isBordered = false
        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.alphaValue = 0
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 6
        closeButton.layer?.cornerCurve = .continuous
        addSubview(closeButton)

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        selectionIndicator.frame = NSRect(x: 6, y: (h - 16) / 2, width: 3, height: 16)
        iconPlate.frame = NSRect(x: 14, y: (h - 20) / 2, width: 20, height: 20)
        let iconX: CGFloat = 18
        iconView.frame = NSRect(x: iconX, y: (h - 12) / 2, width: 12, height: 12)
        titleLabel.frame = NSRect(x: 42, y: (h - 16) / 2, width: bounds.width - 74, height: 16)
        closeButton.frame = NSRect(x: bounds.width - 28, y: (h - 18) / 2, width: 18, height: 18)
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
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            closeButton.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            closeButton.animator().alphaValue = 0
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if closeButton.frame.contains(loc) { onClose?(); return }
        mouseDownLocation = event.locationInWindow
        isDragging = false
        onSelect?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let loc = event.locationInWindow
        if !isDragging && hypot(loc.x - start.x, loc.y - start.y) > 4 {
            isDragging = true
            onDragBegan?()
        }
        if isDragging { onDragMoved?(event.locationInWindow) }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging { onDragEnded?() }
        isDragging = false
        mouseDownLocation = nil
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick?(event.locationInWindow) }
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }

    @objc private func handleClose() { onClose?() }

    private func updateAppearance() {
        let backgroundColor: NSColor
        let borderColor: NSColor
        let iconPlateColor: NSColor
        let iconPlateBorder: NSColor
        let iconColor: NSColor
        let titleColor: NSColor
        let indicatorColor: NSColor

        if isSelected {
            backgroundColor = NSColor(white: 1.0, alpha: 0.035)
            borderColor = NSColor.clear
            iconPlateColor = NSColor.clear
            iconPlateBorder = NSColor.clear
            iconColor = Theme.textPrimary
            titleColor = Theme.textDisplay
            indicatorColor = Theme.accent.withAlphaComponent(0.92)
            layer?.shadowOpacity = 0
        } else if isHovered {
            backgroundColor = Theme.hoverOverlay
            borderColor = NSColor.clear
            iconPlateColor = NSColor.clear
            iconPlateBorder = NSColor.clear
            iconColor = Theme.textPrimary
            titleColor = Theme.textPrimary
            indicatorColor = NSColor.clear
            layer?.shadowOpacity = 0
        } else {
            backgroundColor = NSColor.clear
            borderColor = NSColor.clear
            iconPlateColor = NSColor.clear
            iconPlateBorder = NSColor.clear
            iconColor = Theme.textSecondary
            titleColor = Theme.textSecondary
            indicatorColor = NSColor.clear
            layer?.shadowOpacity = 0
        }

        closeButton.contentTintColor = isHovered ? Theme.textPrimary : Theme.textSecondary
        closeButton.layer?.backgroundColor = NSColor.clear.cgColor
        closeButton.layer?.borderColor = NSColor.clear.cgColor
        closeButton.layer?.borderWidth = 0

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            self.layer?.backgroundColor = backgroundColor.cgColor
            self.layer?.borderColor = borderColor.cgColor
            self.selectionIndicator.backgroundColor = indicatorColor.cgColor
            self.iconPlate.backgroundColor = iconPlateColor.cgColor
            self.iconPlate.borderColor = iconPlateBorder.cgColor
            self.iconView.animator().contentTintColor = iconColor
            self.titleLabel.animator().textColor = titleColor
            self.closeButton.animator().contentTintColor = self.closeButton.contentTintColor
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
            iconColor = Theme.textSecondary
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
