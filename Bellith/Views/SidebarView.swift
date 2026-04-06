import AppKit

/// Zen-style vertical sidebar — a separate panel floating in the window frame.
/// Slides in from the left with smooth content displacement.
/// Shows terminal tabs and an inline tools inspector section.
final class SidebarView: NSView {
    typealias TabModel = (id: UUID, title: String, kind: TerminalContainerView.TabKind)

    static let expandedWidth: CGFloat = 220

    private var tabRows: [SidebarTabRow] = []
    private var tabRowSourceIndices: [Int] = []
    private let newTabButton = NSButton()
    private let headerLabel = NSTextField(labelWithString: "")
    private let bottomBar = NSView()
    private let bottomSeparator = CALayer()
    private let topHighlight = CALayer()

    // Tools section
    private let toolsSeparator = CALayer()
    private let toolsHeaderLabel = NSTextField(labelWithString: "Tools")
    private var toolRows: [SidebarToolRow] = []
    private var enabledTools: [SmartPanelKind] = []

    /// Which tool kind is currently open in the main content area (for highlight state).
    private var activeToolKind: SmartPanelKind?

    private(set) var isExpanded = false
    private var hideTimer: Timer?
    private(set) var isPinned: Bool = BellithSettings.shared.sidebarPinned

    var tabs: [TabModel] = []
    var selectedIndex: Int = 0

    var onSelectTab: ((Int) -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onExpandChanged: ((Bool) -> Void)?
    var onReorderTab: ((Int, Int) -> Void)?
    var onTabContextMenu: ((Int, NSPoint) -> Void)?

    /// Called when a tool is clicked in the sidebar. The container opens it in the main content area.
    var onSelectTool: ((SmartPanelKind) -> Void)?

    private var newTabTrackingArea: NSTrackingArea?
    private var dragSourceIndex: Int?
    private var dragIndicatorLayer: CALayer?
    private let pinButton = NSButton()
    private var settingsObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        layer?.backgroundColor = Theme.surface.cgColor
        layer?.borderColor = Theme.border.cgColor
        layer?.borderWidth = 0.5
        layer?.masksToBounds = true
        alphaValue = 1

        headerLabel.stringValue = "Tabs"
        headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = Theme.textMuted
        headerLabel.isEditable = false
        headerLabel.isBezeled = false
        headerLabel.drawsBackground = false
        addSubview(headerLabel)

        // Pin button
        pinButton.isBordered = false
        pinButton.title = ""
        updatePinButtonIcon()
        pinButton.contentTintColor = isPinned ? Theme.accent : Theme.textMuted
        pinButton.imageScaling = .scaleProportionallyDown
        pinButton.target = self
        pinButton.action = #selector(handlePinToggle)
        pinButton.toolTip = isPinned ? "Unpin sidebar" : "Pin sidebar"
        addSubview(pinButton)
        pinButton.wantsLayer = true
        pinButton.layer?.cornerRadius = 4
        if isPinned {
            pinButton.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.1).cgColor
        }

        // Start expanded if pinned
        if isPinned {
            isExpanded = true
        }

        // Tools section
        toolsSeparator.backgroundColor = Theme.border.cgColor
        layer?.addSublayer(toolsSeparator)

        toolsHeaderLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        toolsHeaderLabel.textColor = Theme.textMuted
        toolsHeaderLabel.isEditable = false
        toolsHeaderLabel.isBezeled = false
        toolsHeaderLabel.drawsBackground = false
        addSubview(toolsHeaderLabel)

        bottomBar.wantsLayer = true
        bottomBar.layer?.backgroundColor = Theme.surface.cgColor
        addSubview(bottomBar)

        bottomSeparator.backgroundColor = Theme.border.cgColor
        bottomSeparator.frame = NSRect(x: 12, y: 43.5, width: 176, height: 0.5)
        bottomSeparator.autoresizingMask = [.layerWidthSizable]
        bottomBar.layer?.addSublayer(bottomSeparator)

        newTabButton.isBordered = false
        newTabButton.title = ""
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.contentTintColor = Theme.textSecondary
        newTabButton.imageScaling = .scaleProportionallyDown
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTab)
        newTabButton.wantsLayer = true
        newTabButton.layer?.cornerRadius = 6
        newTabButton.setFrameSize(NSSize(width: 28, height: 28))
        bottomBar.addSubview(newTabButton)

        // Subtle top-edge highlight for visual depth
        topHighlight.backgroundColor = Theme.hoverOverlay.cgColor
        topHighlight.frame = NSRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5)
        topHighlight.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
        layer?.addSublayer(topHighlight)

        // Rebuild tools from settings
        rebuildTools()

        // Watch for settings changes to update tools
        settingsObserver = NotificationCenter.default.addObserver(
            forName: BellithSettings.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildTools() }
    }

    deinit {
        hideTimer?.invalidate()
        if let obs = settingsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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
            let row = SidebarTabRow(title: tab.title, isSelected: sourceIndex == selectedIndex, kind: tab.kind)
            row.onSelect = { [weak self] in self?.onSelectTab?(sourceIndex) }
            row.onClose = { [weak self] in self?.onCloseTab?(sourceIndex) }
            row.onDragBegan = { [weak self] in self?.beginDrag(fromIndex: visibleIndex) }
            row.onDragMoved = { [weak self] loc in self?.updateDrag(location: loc) }
            row.onDragEnded = { [weak self] in self?.endDrag() }
            row.onRightClick = { [weak self] point in self?.onTabContextMenu?(sourceIndex, point) }
            addSubview(row, positioned: .below, relativeTo: bottomBar)
            tabRows.append(row)
            tabRowSourceIndices.append(sourceIndex)
        }

        needsLayout = true
    }

    // MARK: - Tools Section

    private func rebuildTools() {
        let settings = BellithSettings.shared
        let showTools = settings.sidebarShowTools
        let enabledRawValues = settings.sidebarTools
        let newTools = showTools ? SmartPanelKind.allCases.filter { enabledRawValues.contains($0.rawValue) } : []

        // Skip rebuild if nothing changed
        if newTools == enabledTools && showTools == !toolsHeaderLabel.isHidden {
            return
        }

        toolRows.forEach { $0.removeFromSuperview() }
        toolRows.removeAll()

        toolsHeaderLabel.isHidden = !showTools
        toolsSeparator.isHidden = !showTools

        // Clear active highlight if its kind was removed
        if let active = activeToolKind, !newTools.contains(active) {
            activeToolKind = nil
        }

        enabledTools = newTools

        for kind in enabledTools {
            let isActive = kind == activeToolKind
            let row = SidebarToolRow(kind: kind, isActive: isActive)
            row.onSelect = { [weak self] in self?.handleToolSelected(kind) }
            addSubview(row, positioned: .below, relativeTo: bottomBar)
            toolRows.append(row)
        }

        // Tool visibility affects whether smart tabs should appear in the tabs list.
        rebuildTabs()
        needsLayout = true
    }

    private var shouldHideSmartTabsInTabList: Bool {
        BellithSettings.shared.sidebarShowTools && !enabledTools.isEmpty
    }

    // MARK: - Tool Selection

    private func handleToolSelected(_ kind: SmartPanelKind) {
        activeToolKind = kind
        updateToolRowStates()
        onSelectTool?(kind)
    }

    /// Update the active tool highlight to match the currently selected tab.
    func setActiveToolKind(_ kind: SmartPanelKind?) {
        activeToolKind = kind
        updateToolRowStates()
    }

    private func updateToolRowStates() {
        for (i, kind) in enabledTools.enumerated() where i < toolRows.count {
            toolRows[i].setActive(kind == activeToolKind)
        }
    }

    private func updatePinButtonIcon() {
        let symbolName = isPinned ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isPinned ? "Unpin sidebar" : "Pin sidebar")
    }

    @objc private func handlePinToggle() {
        isPinned.toggle()
        BellithSettings.shared.sidebarPinned = isPinned
        updatePinButtonIcon()
        pinButton.contentTintColor = isPinned ? Theme.accent : Theme.textMuted
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            pinButton.layer?.backgroundColor = isPinned ? Theme.accent.withAlphaComponent(0.1).cgColor : NSColor.clear.cgColor
        }
        pinButton.toolTip = isPinned ? "Unpin sidebar" : "Pin sidebar"
        if !isPinned && isExpanded {
            scheduleHide()
        }
    }

    override func layout() {
        super.layout()
        let sideInset: CGFloat = 10
        let topInset: CGFloat = 38
        let rowHeight: CGFloat = 38
        let rowSpacing: CGFloat = 3
        let toolRowHeight: CGFloat = 32
        let toolRowSpacing: CGFloat = 2

        // Update tab count in header (visible tab rows only).
        let visibleTabCount = tabRows.count
        headerLabel.stringValue = visibleTabCount > 0 ? "Tabs (\(visibleTabCount))" : "Tabs"

        headerLabel.frame = NSRect(
            x: sideInset + 8,
            y: bounds.height - topInset - 14,
            width: bounds.width - sideInset * 2 - 30,
            height: 14
        )

        pinButton.frame = NSRect(
            x: bounds.width - sideInset - 24,
            y: bounds.height - topInset - 16,
            width: 20,
            height: 20
        )

        let bottomHeight: CGFloat = 44
        bottomBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bottomHeight)
        newTabButton.frame = NSRect(x: sideInset, y: 8, width: 28, height: 28)

        // Build layout from the bottom up
        var floorY = bottomHeight

        // Calculate tools section height
        let showTools = BellithSettings.shared.sidebarShowTools && !enabledTools.isEmpty
        let toolsSectionHeight: CGFloat
        if showTools {
            let toolsRowsHeight = CGFloat(toolRows.count) * toolRowHeight + CGFloat(max(0, toolRows.count - 1)) * toolRowSpacing
            toolsSectionHeight = 8 + 16 + 6 + toolsRowsHeight + 8
        } else {
            toolsSectionHeight = 0
        }

        // Layout tools section above the panel (or bottom bar)
        if showTools {
            var toolY = floorY + 8

            // Tool rows (bottom-up)
            for row in toolRows.reversed() {
                row.frame = NSRect(x: sideInset, y: toolY, width: bounds.width - sideInset * 2, height: toolRowHeight)
                toolY += toolRowHeight + toolRowSpacing
            }

            toolY += 2
            toolsHeaderLabel.stringValue = "Tools (\(enabledTools.count))"
            toolsHeaderLabel.frame = NSRect(
                x: sideInset + 8,
                y: toolY,
                width: bounds.width - sideInset * 2 - 16,
                height: 14
            )
            toolY += 14 + 4

            toolsSeparator.frame = NSRect(
                x: sideInset + 8,
                y: toolY,
                width: bounds.width - sideInset * 2 - 16,
                height: 0.5
            )
        }

        // Tab rows fill space between header and tools/bottom
        let minY = floorY + toolsSectionHeight + 4
        var y = bounds.height - topInset - 14 - 12

        for row in tabRows {
            y -= rowHeight
            if y < minY {
                row.isHidden = true
            } else {
                row.isHidden = false
                row.frame = NSRect(x: sideInset, y: y, width: bounds.width - sideInset * 2, height: rowHeight)
            }
            y -= rowSpacing
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
        if !isPinned { scheduleHide() }
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
                self.newTabButton.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.1).cgColor
                self.newTabButton.contentTintColor = Theme.accent
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        if isExpanded && !isPinned { scheduleHide() }
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
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.borderColor = Theme.border.cgColor
        topHighlight.backgroundColor = Theme.hoverOverlay.cgColor
        bottomSeparator.backgroundColor = Theme.border.cgColor
        headerLabel.textColor = Theme.textMuted
        toolsHeaderLabel.textColor = Theme.textMuted
        toolsSeparator.backgroundColor = Theme.border.cgColor
        bottomBar.layer?.backgroundColor = Theme.surface.cgColor
        pinButton.contentTintColor = isPinned ? Theme.accent : Theme.textMuted
        pinButton.layer?.backgroundColor = isPinned ? Theme.accent.withAlphaComponent(0.1).cgColor : NSColor.clear.cgColor
        newTabButton.contentTintColor = Theme.textSecondary
        rebuildTabs()
        rebuildTools()
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

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let selectionIndicator = CALayer()
    private let isSelected: Bool
    private let kind: TerminalContainerView.TabKind
    private var isHovered = false

    private var isSmartTab: Bool {
        if case .smart = kind { return true }
        return false
    }

    init(title: String, isSelected: Bool, kind: TerminalContainerView.TabKind) {
        self.isSelected = isSelected
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        // Accessibility
        setAccessibilityRole(.button)
        setAccessibilityLabel("Tab: \(title)")
        setAccessibilityValue(isSelected ? "selected" : "")

        // Accent bar on the left edge of selected tab
        if isSelected {
            selectionIndicator.backgroundColor = isSmartTab
                ? Theme.accent.withAlphaComponent(0.8).cgColor
                : Theme.accent.cgColor
            selectionIndicator.cornerRadius = 1.5
            layer?.addSublayer(selectionIndicator)
        }

        // Icon
        let symbolName: String
        if case .smart(let panelKind) = kind {
            symbolName = panelKind.iconName
        } else {
            symbolName = isSelected ? "terminal.fill" : "terminal"
        }
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        iconView.contentTintColor = isSelected ? Theme.accent : Theme.textMuted
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular)
        titleLabel.textColor = isSelected ? Theme.textPrimary : Theme.textSecondary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        closeButton.isBordered = false
        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.contentTintColor = Theme.textMuted
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.alphaValue = 0
        addSubview(closeButton)

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        selectionIndicator.frame = NSRect(x: 3, y: (h - 16) / 2, width: 3, height: 16)
        let iconX: CGFloat = isSelected ? 14 : 10
        iconView.frame = NSRect(x: iconX, y: (h - 18) / 2, width: 18, height: 18)
        titleLabel.frame = NSRect(x: iconX + 24, y: (h - 16) / 2, width: bounds.width - iconX - 50, height: 16)
        closeButton.frame = NSRect(x: bounds.width - 26, y: (h - 16) / 2, width: 16, height: 16)
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
        let bgColor: CGColor
        if isSelected {
            bgColor = isSmartTab
                ? Theme.accent.withAlphaComponent(0.08).cgColor
                : Theme.border.cgColor
        } else if isHovered {
            bgColor = Theme.borderSubtle.cgColor
        } else {
            bgColor = NSColor.clear.cgColor
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            self.layer?.backgroundColor = bgColor
        }
    }
}

// MARK: - Sidebar Tool Row

fileprivate final class SidebarToolRow: NSView {
    var onSelect: (() -> Void)?
    private let kind: SmartPanelKind
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var isHovered = false
    private var isActive = false

    init(kind: SmartPanelKind, isActive: Bool = false) {
        self.kind = kind
        self.isActive = isActive
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        iconView.image = NSImage(systemSymbolName: kind.iconName, accessibilityDescription: kind.displayName)
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleLabel.stringValue = kind.displayName
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        setAccessibilityRole(.button)
        setAccessibilityLabel(kind.displayName)

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
        if isActive {
            iconView.contentTintColor = Theme.accent
            titleLabel.textColor = Theme.textPrimary
            layer?.backgroundColor = Theme.accent.withAlphaComponent(0.10).cgColor
        } else {
            iconView.contentTintColor = Theme.textMuted
            titleLabel.textColor = Theme.textSecondary
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 8, y: (h - 14) / 2, width: 14, height: 14)
        titleLabel.frame = NSRect(x: 28, y: (h - 14) / 2, width: bounds.width - 36, height: 14)
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
            self.iconView.animator().contentTintColor = Theme.accent
            self.titleLabel.animator().textColor = Theme.textPrimary
            self.layer?.backgroundColor = Theme.accent.withAlphaComponent(self.isActive ? 0.14 : 0.06).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            self.iconView.animator().contentTintColor = self.isActive ? Theme.accent : Theme.textMuted
            self.titleLabel.animator().textColor = self.isActive ? Theme.textPrimary : Theme.textSecondary
            self.layer?.backgroundColor = self.isActive ? Theme.accent.withAlphaComponent(0.10).cgColor : NSColor.clear.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }
}
