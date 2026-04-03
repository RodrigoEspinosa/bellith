import AppKit

/// Minimal Zen-style tab bar. Sits in the titlebar area, right of the traffic lights.
/// Pill-shaped tabs, close button appears on hover only.
final class TabBarView: NSView {
    struct Tab {
        let id: UUID
        var title: String
    }

    private(set) var tabs: [Tab] = []
    private(set) var selectedIndex: Int = 0
    private var tabViews: [TabPillView] = []

    var onSelectTab: ((Int) -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onNewTab: (() -> Void)?

    private let newTabButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupNewTabButton()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupNewTabButton() {
        newTabButton.isBordered = false
        newTabButton.title = ""
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.contentTintColor = Theme.textMuted
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTab)
        newTabButton.setFrameSize(NSSize(width: 24, height: 24))
        addSubview(newTabButton)
    }

    func update(tabs: [Tab], selectedIndex: Int) {
        self.tabs = tabs
        self.selectedIndex = selectedIndex
        rebuildTabViews()
    }

    private func rebuildTabViews() {
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews.removeAll()

        for (i, tab) in tabs.enumerated() {
            let pill = TabPillView(title: tab.title, isSelected: i == selectedIndex)
            pill.onSelect = { [weak self] in self?.onSelectTab?(i) }
            pill.onClose = { [weak self] in self?.onCloseTab?(i) }
            addSubview(pill)
            tabViews.append(pill)
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()

        var x: CGFloat = 0
        let height = bounds.height
        let tabHeight: CGFloat = 28
        let y = (height - tabHeight) / 2

        for pill in tabViews {
            let width: CGFloat = min(160, max(80, pill.idealWidth))
            pill.frame = NSRect(x: x, y: y, width: width, height: tabHeight)
            x += width + 2
        }

        newTabButton.frame = NSRect(x: x + 4, y: (height - 24) / 2, width: 24, height: 24)

        // Only show if more than 1 tab
        isHidden = tabs.count <= 1
    }

    @objc private func handleNewTab() {
        onNewTab?()
    }
}

// MARK: - Tab Pill View

private final class TabPillView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let isSelected: Bool
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    var idealWidth: CGFloat {
        titleLabel.attributedStringValue.size().width + 40
    }

    init(title: String, isSelected: Bool) {
        self.isSelected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.radiusElement

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
        closeButton.setFrameSize(NSSize(width: 16, height: 16))
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
        titleLabel.frame = NSRect(x: 10, y: (bounds.height - 16) / 2, width: bounds.width - 32, height: 16)
        closeButton.frame = NSRect(x: bounds.width - 22, y: (bounds.height - 16) / 2, width: 16, height: 16)
    }

    override func updateTrackingAreas() {
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
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
        onSelect?()
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
