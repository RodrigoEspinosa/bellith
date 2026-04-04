import AppKit

/// Zen-style vertical sidebar — a separate panel floating in the window frame.
/// Slides in from the left with smooth content displacement.
/// Shows both terminal tabs and smart inspector tabs with distinct icons.
final class SidebarView: NSView {
    static let expandedWidth: CGFloat = 220

    private var tabRows: [SidebarTabRow] = []
    private let newTabButton = NSButton()
    private let headerLabel = NSTextField(labelWithString: "")
    private let bottomBar = NSView()

    private(set) var isExpanded = false
    private var hideTimer: Timer?
    private(set) var isPinned: Bool = BellithSettings.shared.sidebarPinned

    var tabs: [(id: UUID, title: String, kind: TerminalContainerView.TabKind)] = []
    var selectedIndex: Int = 0

    var onSelectTab: ((Int) -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onExpandChanged: ((Bool) -> Void)?
    var onReorderTab: ((Int, Int) -> Void)?
    var onTabContextMenu: ((Int, NSPoint) -> Void)?

    private var dragSourceIndex: Int?
    private var dragIndicatorLayer: CALayer?
    private let pinButton = NSButton()

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

        // Start expanded if pinned
        if isPinned {
            isExpanded = true
        }

        bottomBar.wantsLayer = true
        bottomBar.layer?.backgroundColor = Theme.surface.cgColor
        addSubview(bottomBar)

        let bottomSep = CALayer()
        bottomSep.backgroundColor = Theme.border.cgColor
        bottomSep.frame = NSRect(x: 12, y: 43.5, width: 176, height: 0.5)
        bottomSep.autoresizingMask = [.layerWidthSizable]
        bottomBar.layer?.addSublayer(bottomSep)

        newTabButton.isBordered = false
        newTabButton.title = ""
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.contentTintColor = Theme.textSecondary
        newTabButton.imageScaling = .scaleProportionallyDown
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTab)
        newTabButton.wantsLayer = true
        newTabButton.layer?.cornerRadius = 6
        bottomBar.addSubview(newTabButton)

        // Subtle top-edge highlight for visual depth
        let topHighlight = CALayer()
        topHighlight.backgroundColor = NSColor(white: 1, alpha: 0.04).cgColor
        topHighlight.frame = NSRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5)
        topHighlight.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
        layer?.addSublayer(topHighlight)
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

        for (i, tab) in tabs.enumerated() {
            let row = SidebarTabRow(title: tab.title, isSelected: i == selectedIndex, kind: tab.kind)
            row.onSelect = { [weak self] in self?.onSelectTab?(i) }
            row.onClose = { [weak self] in self?.onCloseTab?(i) }
            row.onDragBegan = { [weak self] in self?.beginDrag(fromIndex: i) }
            row.onDragMoved = { [weak self] loc in self?.updateDrag(location: loc) }
            row.onDragEnded = { [weak self] in self?.endDrag() }
            row.onRightClick = { [weak self] point in self?.onTabContextMenu?(i, point) }
            // Insert below bottom bar to maintain z-order
            addSubview(row, positioned: .below, relativeTo: bottomBar)
            tabRows.append(row)
        }

        needsLayout = true
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

        // Update tab count in header
        headerLabel.stringValue = tabs.count > 0 ? "Tabs (\(tabs.count))" : "Tabs"

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

        var y = bounds.height - topInset - 14 - 12
        let minY = bottomHeight + 4 // don't overflow into bottom bar

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

        if targetIdx != sourceIdx {
            onReorderTab?(sourceIdx, targetIdx)
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

        // Icon — use panel-specific icon for smart tabs, terminal icon for terminal tabs
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
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
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
        if closeButton.frame.contains(loc) {
            onClose?()
            return
        }
        mouseDownLocation = event.locationInWindow
        isDragging = false
        onSelect?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let loc = event.locationInWindow
        let distance = hypot(loc.x - start.x, loc.y - start.y)
        if !isDragging && distance > 4 {
            isDragging = true
            onDragBegan?()
        }
        if isDragging {
            onDragMoved?(event.locationInWindow)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onDragEnded?()
        }
        isDragging = false
        mouseDownLocation = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event.locationInWindow)
    }

    override func otherMouseDown(with event: NSEvent) {
        // Middle-click to close tab
        if event.buttonNumber == 2 {
            onClose?()
        }
    }

    @objc private func handleClose() {
        onClose?()
    }

    private func updateAppearance() {
        if isSelected {
            if isSmartTab {
                layer?.backgroundColor = Theme.accent.withAlphaComponent(0.08).cgColor
            } else {
                layer?.backgroundColor = Theme.border.cgColor
            }
        } else if isHovered {
            layer?.backgroundColor = Theme.borderSubtle.cgColor
        } else {
            layer?.backgroundColor = .clear
        }
    }
}
