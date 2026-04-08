import AppKit

/// Minimal Zen-style tab bar. Sits in the titlebar area, right of the traffic lights.
/// Pill-shaped tabs, close button appears on hover only.
/// Smart tabs show distinct icons and accent colors.
final class TabBarView: NSView {
    struct Tab {
        let id: UUID
        var title: String
        var kind: TerminalContainerView.TabKind = .terminal
    }

    private(set) var tabs: [Tab] = []
    private(set) var selectedIndex: Int = 0
    private var tabViews: [TabPillView] = []

    var onSelectTab: ((Int) -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onReorderTab: ((Int, Int) -> Void)?

    private var dragSourceIndex: Int?
    private var dragTargetIndex: Int?
    private var dragIndicatorLayer: CALayer?
    private let smartPanelRegistry: SmartPanelRegistry

    private let newTabButton = NSButton()
    private let singleTabLabel = NSTextField(labelWithString: "")
    private var themeObserver: NSObjectProtocol?

    init(frame frameRect: NSRect = .zero, smartPanelRegistry: SmartPanelRegistry = .shared) {
        self.smartPanelRegistry = smartPanelRegistry
        super.init(frame: frameRect)
        setupNewTabButton()
        setupSingleTabLabel()
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshTheme()
        }
    }

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupNewTabButton() {
        newTabButton.isBordered = false
        newTabButton.title = ""
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.contentTintColor = Theme.textSecondary
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTab)
        newTabButton.setFrameSize(NSSize(width: 24, height: 24))
        addSubview(newTabButton)
        newTabButton.wantsLayer = true
        newTabButton.layer?.cornerRadius = 6
    }

    private func setupSingleTabLabel() {
        singleTabLabel.font = BellithFont.ui(12.5, weight: .medium)
        singleTabLabel.textColor = Theme.textSecondary
        singleTabLabel.isEditable = false
        singleTabLabel.isSelectable = false
        singleTabLabel.isBezeled = false
        singleTabLabel.drawsBackground = false
        singleTabLabel.lineBreakMode = .byTruncatingTail
        singleTabLabel.maximumNumberOfLines = 1
        singleTabLabel.isHidden = true
        addSubview(singleTabLabel)
    }

    func update(tabs: [Tab], selectedIndex: Int) {
        self.tabs = tabs
        self.selectedIndex = selectedIndex

        if tabs.count == 1, let firstTab = tabs.first {
            singleTabLabel.stringValue = firstTab.title
        }

        rebuildTabViews()
    }

    func refreshTheme() {
        newTabButton.contentTintColor = Theme.textSecondary
        singleTabLabel.textColor = Theme.textSecondary
        dragIndicatorLayer?.backgroundColor = Theme.accent.withAlphaComponent(0.5).cgColor
        rebuildTabViews()
    }

    private func rebuildTabViews() {
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews.removeAll()

        for (i, tab) in tabs.enumerated() {
            let pill = TabPillView(
                title: tab.title,
                isSelected: i == selectedIndex,
                kind: tab.kind,
                smartPanelRegistry: smartPanelRegistry
            )
            pill.onSelect = { [weak self] in self?.onSelectTab?(i) }
            pill.onClose = { [weak self] in self?.onCloseTab?(i) }
            pill.onDragBegan = { [weak self] in self?.beginDrag(fromIndex: i) }
            pill.onDragMoved = { [weak self] loc in self?.updateDrag(location: loc) }
            pill.onDragEnded = { [weak self] in self?.endDrag() }
            addSubview(pill)
            tabViews.append(pill)
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()

        var x: CGFloat = 0
        let height = bounds.height
        let tabHeight: CGFloat = 30
        let y = (height - tabHeight) / 2

        for pill in tabViews {
            let width: CGFloat = min(180, max(92, pill.idealWidth))
            pill.frame = NSRect(x: x, y: y, width: width, height: tabHeight)
            x += width + 6
        }

        newTabButton.frame = NSRect(x: x + 4, y: (height - 24) / 2, width: 24, height: 24)

        // Single tab: show just the label and new tab button, hide pills
        if tabs.count <= 1 {
            singleTabLabel.isHidden = false
            singleTabLabel.frame = NSRect(x: 0, y: (height - 16) / 2, width: min(240, singleTabLabel.attributedStringValue.size().width + 8), height: 16)
            newTabButton.frame = NSRect(x: singleTabLabel.frame.maxX + 8, y: (height - 24) / 2, width: 24, height: 24)
            tabViews.forEach { $0.isHidden = true }
        } else {
            singleTabLabel.isHidden = true
            tabViews.forEach { $0.isHidden = false }
        }
    }

    // MARK: - Tab Reordering

    private func beginDrag(fromIndex: Int) {
        dragSourceIndex = fromIndex
        dragTargetIndex = nil
        if dragIndicatorLayer == nil {
            let indicator = CALayer()
            indicator.backgroundColor = Theme.accent.withAlphaComponent(0.5).cgColor
            indicator.cornerRadius = 1
            wantsLayer = true
            layer?.addSublayer(indicator)
            dragIndicatorLayer = indicator
        }
    }

    private func updateDrag(location: NSPoint) {
        guard let sourceIdx = dragSourceIndex else { return }
        let loc = convert(location, from: nil)

        var targetIdx: Int?
        for (i, pill) in tabViews.enumerated() {
            if loc.x >= pill.frame.minX && loc.x <= pill.frame.maxX {
                targetIdx = i
                break
            }
        }

        if let target = targetIdx, target != sourceIdx {
            dragTargetIndex = target
            let pill = tabViews[target]
            let indicatorX = target < sourceIdx ? pill.frame.minX - 1 : pill.frame.maxX + 1
            dragIndicatorLayer?.frame = NSRect(x: indicatorX, y: pill.frame.minY + 4, width: 2, height: pill.frame.height - 8)
            dragIndicatorLayer?.isHidden = false
        } else {
            dragTargetIndex = nil
            dragIndicatorLayer?.isHidden = true
        }
    }

    private func endDrag() {
        guard let sourceIdx = dragSourceIndex else { return }
        dragIndicatorLayer?.removeFromSuperlayer()
        dragIndicatorLayer = nil

        let targetIdx = dragTargetIndex ?? sourceIdx
        dragSourceIndex = nil
        dragTargetIndex = nil
        if targetIdx != sourceIdx {
            onReorderTab?(sourceIdx, targetIdx)
        }
    }

    @objc private func handleNewTab() {
        onNewTab?()
    }
}

// MARK: - Tab Pill View

fileprivate final class TabPillView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    private var isDragging = false
    private var mouseDownLocation: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let isSelected: Bool
    private let kind: TerminalContainerView.TabKind
    private let smartPanelRegistry: SmartPanelRegistry
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    var idealWidth: CGFloat {
        let iconWidth: CGFloat = isSmartTab ? 22 : 0
        return titleLabel.attributedStringValue.size().width + 40 + iconWidth
    }

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
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5

        // Accessibility
        setAccessibilityRole(.button)
        setAccessibilityLabel("Tab: \(title)")
        setAccessibilityValue(isSelected ? "selected" : "")

        // Icon for smart tabs
        if case .smart(let pluginID) = kind,
           let plugin = smartPanelRegistry.plugin(for: pluginID) {
            iconView.image = NSImage(systemSymbolName: plugin.iconName, accessibilityDescription: nil)
            iconView.contentTintColor = isSelected ? Theme.textPrimary : Theme.textTertiary
            iconView.imageScaling = .scaleProportionallyDown
            addSubview(iconView)
        }

        titleLabel.stringValue = title
        titleLabel.font = BellithFont.ui(12, weight: isSelected ? .medium : .regular)
        titleLabel.textColor = isSelected ? Theme.textPrimary : Theme.textSecondary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        closeButton.isBordered = false
        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.contentTintColor = Theme.textTertiary
        closeButton.setFrameSize(NSSize(width: 18, height: 18))
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
        var labelX: CGFloat = 12

        if isSmartTab {
            iconView.frame = NSRect(x: 10, y: (bounds.height - 12) / 2, width: 12, height: 12)
            labelX = 28
        }

        titleLabel.frame = NSRect(x: labelX, y: (bounds.height - 16) / 2, width: bounds.width - labelX - 28, height: 16)
        closeButton.frame = NSRect(x: bounds.width - 24, y: (bounds.height - 18) / 2, width: 18, height: 18)
    }

    override func updateTrackingAreas() {
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
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
        mouseDownLocation = event.locationInWindow
        isDragging = false
        onSelect?()
    }

    override func otherMouseDown(with event: NSEvent) {
        // Middle-click to close tab
        if event.buttonNumber == 2 {
            onClose?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let loc = event.locationInWindow
        if !isDragging && hypot(loc.x - start.x, loc.y - start.y) > 4 {
            isDragging = true
            onDragBegan?()
        }
        if isDragging {
            onDragMoved?(event.locationInWindow)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging { onDragEnded?() }
        isDragging = false
        mouseDownLocation = nil
    }

    @objc private func handleClose() {
        onClose?()
    }

    private func updateAppearance() {
        let bgColor: CGColor
        let borderColor: CGColor
        if isSelected {
            bgColor = Theme.chromeElevated.withAlphaComponent(0.58).cgColor
            borderColor = Theme.chromeHairline.cgColor
        } else if isHovered {
            bgColor = Theme.hoverOverlay.cgColor
            borderColor = Theme.chromeHairline.cgColor
        } else {
            bgColor = NSColor.clear.cgColor
            borderColor = NSColor.clear.cgColor
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            self.layer?.backgroundColor = bgColor
            self.layer?.borderColor = borderColor
        }
    }
}
