import AppKit

/// Zen-style vertical sidebar that overlays the terminal.
/// Dark opaque panel, auto-hides, fades in from the left edge.
final class SidebarView: NSView {
    static let expandedWidth: CGFloat = 220

    private var tabRows: [SidebarTabRow] = []
    private let newTabButton = NSButton()
    private let separator = CALayer()

    private(set) var isExpanded = false
    private var hideTimer: Timer?

    var tabs: [(id: UUID, title: String)] = []
    var selectedIndex: Int = 0

    var onSelectTab: ((Int) -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onNewTab: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 0.97).cgColor
        alphaValue = 0

        // Right edge separator
        separator.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        layer?.addSublayer(separator)

        // New tab button at bottom
        newTabButton.isBordered = false
        newTabButton.title = ""
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.contentTintColor = Theme.textMuted
        newTabButton.imageScaling = .scaleProportionallyDown
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTab)
        addSubview(newTabButton)
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
        separator.frame = NSRect(x: bounds.width - 0.5, y: 0, width: 0.5, height: bounds.height)

        let topInset: CGFloat = 46
        let sideInset: CGFloat = 8
        let rowHeight: CGFloat = 32
        let rowSpacing: CGFloat = 2

        var y = bounds.height - topInset

        for row in tabRows {
            y -= rowHeight
            row.frame = NSRect(x: sideInset, y: y, width: bounds.width - sideInset * 2, height: rowHeight)
            y -= rowSpacing
        }

        newTabButton.frame = NSRect(x: sideInset, y: 10, width: 28, height: 28)
    }

    // MARK: - Show / Hide

    func toggle() {
        if isExpanded { hide() } else { show() }
    }

    func show() {
        guard !isExpanded else { return }
        isExpanded = true
        hideTimer?.invalidate()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animMedium
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }

        scheduleHide()
    }

    func hide() {
        guard isExpanded else { return }
        isExpanded = false
        hideTimer?.invalidate()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animMedium
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }
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
    private let isSelected: Bool
    private var isHovered = false

    init(title: String, isSelected: Bool) {
        self.isSelected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.radiusElement

        let symbolName = isSelected ? "terminal.fill" : "terminal"
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        iconView.contentTintColor = isSelected ? Theme.accent : Theme.textSecondary
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: isSelected ? .medium : .regular)
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
        iconView.frame = NSRect(x: 8, y: (h - 16) / 2, width: 16, height: 16)
        titleLabel.frame = NSRect(x: 30, y: (h - 16) / 2, width: bounds.width - 54, height: 16)
        closeButton.frame = NSRect(x: bounds.width - 22, y: (h - 14) / 2, width: 14, height: 14)
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
        // Check if click is on close button area
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
            layer?.backgroundColor = Theme.accentSubtle.cgColor
        } else if isHovered {
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.04).cgColor
        } else {
            layer?.backgroundColor = .clear
        }
    }
}
