import AppKit

/// Zen-style vertical sidebar — a separate panel floating in the window frame.
/// Slides in from the left with smooth content displacement.
final class SidebarView: NSView {
    static let expandedWidth: CGFloat = 200

    private var tabRows: [SidebarTabRow] = []
    private let newTabButton = NSButton()
    private let headerLabel = NSTextField(labelWithString: "")
    private let bottomBar = NSView()

    private(set) var isExpanded = false
    private var hideTimer: Timer?

    var tabs: [(id: UUID, title: String)] = []
    var selectedIndex: Int = 0

    var onSelectTab: ((Int) -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onExpandChanged: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        // Slightly elevated from the frame — between frame and content color
        layer?.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1.0).cgColor
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.07).cgColor
        layer?.borderWidth = 0.5
        layer?.masksToBounds = true
        alphaValue = 1

        // Header label — shows "Tabs" or could show workspace name
        headerLabel.stringValue = "Tabs"
        headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = Theme.textMuted
        headerLabel.isEditable = false
        headerLabel.isBezeled = false
        headerLabel.drawsBackground = false
        addSubview(headerLabel)

        // Bottom bar with separator and new tab button
        bottomBar.wantsLayer = true
        addSubview(bottomBar)

        let bottomSep = CALayer()
        bottomSep.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        bottomSep.frame = NSRect(x: 12, y: 0, width: 176, height: 0.5)
        bottomSep.autoresizingMask = [.layerWidthSizable]
        bottomBar.layer?.addSublayer(bottomSep)

        // New tab button — more intentional styling
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(tabs: [(id: UUID, title: String)], selectedIndex: Int) {
        self.tabs = tabs
        self.selectedIndex = selectedIndex
        rebuildTabs()
    }

    private func rebuildTabs() {
        tabRows.forEach { $0.removeFromSuperview() }
        tabRows.removeAll()

        for (i, tab) in tabs.enumerated() {
            let row = SidebarTabRow(title: tab.title, isSelected: i == selectedIndex)
            row.onSelect = { [weak self] in self?.onSelectTab?(i) }
            row.onClose = { [weak self] in self?.onCloseTab?(i) }
            addSubview(row)
            tabRows.append(row)
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()
        let sideInset: CGFloat = 10
        let topInset: CGFloat = 16
        let rowHeight: CGFloat = 34
        let rowSpacing: CGFloat = 2

        // Header
        headerLabel.frame = NSRect(
            x: sideInset + 8,
            y: bounds.height - topInset - 14,
            width: bounds.width - sideInset * 2,
            height: 14
        )

        // Tab rows
        var y = bounds.height - topInset - 14 - 12

        for row in tabRows {
            y -= rowHeight
            row.frame = NSRect(x: sideInset, y: y, width: bounds.width - sideInset * 2, height: rowHeight)
            y -= rowSpacing
        }

        // Bottom bar
        let bottomHeight: CGFloat = 44
        bottomBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bottomHeight)
        newTabButton.frame = NSRect(x: sideInset, y: 8, width: 28, height: 28)
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
        scheduleHide()
    }

    func hide() {
        guard isExpanded else { return }
        isExpanded = false
        hideTimer?.invalidate()
        onExpandChanged?(false)
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hideTimer?.invalidate()
    }

    override func mouseExited(with event: NSEvent) {
        if isExpanded { scheduleHide() }
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

private final class SidebarTabRow: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let selectionIndicator = CALayer()
    private let isSelected: Bool
    private var isHovered = false

    init(title: String, isSelected: Bool) {
        self.isSelected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        // Accent bar on the left edge of selected tab
        if isSelected {
            selectionIndicator.backgroundColor = Theme.accent.cgColor
            selectionIndicator.cornerRadius = 1.5
            layer?.addSublayer(selectionIndicator)
        }

        let symbolName = isSelected ? "terminal.fill" : "terminal"
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        iconView.contentTintColor = isSelected ? Theme.accent : Theme.textMuted
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12.5, weight: isSelected ? .medium : .regular)
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

        // Selection indicator — thin accent bar on left
        selectionIndicator.frame = NSRect(x: 3, y: (h - 14) / 2, width: 3, height: 14)

        let iconX: CGFloat = isSelected ? 14 : 10
        iconView.frame = NSRect(x: iconX, y: (h - 16) / 2, width: 16, height: 16)
        titleLabel.frame = NSRect(x: iconX + 22, y: (h - 16) / 2, width: bounds.width - iconX - 46, height: 16)
        closeButton.frame = NSRect(x: bounds.width - 24, y: (h - 16) / 2, width: 16, height: 16)
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
        } else {
            onSelect?()
        }
    }

    @objc private func handleClose() {
        onClose?()
    }

    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        } else if isHovered {
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.04).cgColor
        } else {
            layer?.backgroundColor = .clear
        }
    }
}
