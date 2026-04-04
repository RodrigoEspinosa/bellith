import AppKit

// MARK: - Keybindings Pane

final class KeybindingsPane: NSView {
    private let settings = BellithSettings.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()
    private var cards: [SettingsCard] = []
    private let resetBtn = ResetDefaultsButton(title: "Reset All to Defaults")

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        addSubview(scroll)
        content.wantsLayer = true
        scroll.documentView = content

        resetBtn.onClick = { [weak self] in
            guard let self else { return }
            self.settings.keybindings = BellithSettings.defaultKeybindings
            self.buildCards()
        }
        content.addSubview(resetBtn)

        buildCards()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func buildCards() {
        cards.forEach { $0.removeFromSuperview() }
        cards.removeAll()

        let bindings = settings.keybindings

        // Group by category
        var categories: [(String, [Int])] = []
        var lastCategory = ""
        for (i, binding) in bindings.enumerated() {
            if binding.category != lastCategory {
                categories.append((binding.category, [i]))
                lastCategory = binding.category
            } else {
                categories[categories.count - 1].1.append(i)
            }
        }

        for (category, indices) in categories {
            let card = SettingsCard(title: category)
            content.addSubview(card)

            for idx in indices {
                let row = KeybindingActionRow(binding: bindings[idx], index: idx)
                row.onShortcutChanged = { [weak self] i, shortcut in
                    guard let self else { return }
                    var all = self.settings.keybindings
                    all[i].shortcut = shortcut
                    self.settings.keybindings = all
                }
                card.addSubview(row)
            }

            cards.append(card)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        let w = bounds.width
        let cardW = w - PreferencesLayout.hPad * 2
        let innerW = cardW - PreferencesLayout.cardPad * 2

        var y: CGFloat = PreferencesLayout.hPad

        let bindings = settings.keybindings
        var categories: [(String, [Int])] = []
        var lastCategory = ""
        for (i, binding) in bindings.enumerated() {
            if binding.category != lastCategory {
                categories.append((binding.category, [i]))
                lastCategory = binding.category
            } else {
                categories[categories.count - 1].1.append(i)
            }
        }

        for (cardIdx, (_, indices)) in categories.enumerated() {
            guard cardIdx < cards.count else { break }
            let card = cards[cardIdx]
            let rowCount = CGFloat(indices.count)
            let cardH = card.headerHeight + rowCount * PreferencesLayout.rowH + (rowCount - 1) * PreferencesLayout.rowGap + PreferencesLayout.cardPad

            card.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: cardH)

            // Layout rows inside card
            let rows = card.subviews.compactMap { $0 as? KeybindingActionRow }
            var ry = cardH - card.headerHeight - PreferencesLayout.rowH
            for row in rows {
                row.frame = NSRect(x: PreferencesLayout.cardPad, y: ry, width: innerW, height: PreferencesLayout.rowH)
                ry -= PreferencesLayout.rowH + PreferencesLayout.rowGap
            }

            y += cardH + PreferencesLayout.sectionGap
        }

        // Reset button
        let resetBtnH: CGFloat = 36
        resetBtn.frame = NSRect(x: PreferencesLayout.hPad + cardW - 180, y: y, width: 180, height: resetBtnH)
        y += resetBtnH + PreferencesLayout.hPad

        content.frame = NSRect(x: 0, y: 0, width: w, height: max(y, bounds.height))
    }
}

// Keybinding action row
final class KeybindingActionRow: NSView {
    var onShortcutChanged: ((Int, KeyShortcut) -> Void)?
    private let binding: KeyBindingEntry
    private let index: Int
    private let actionLabel: NSTextField
    private let shortcutBadge: ShortcutBadge
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(binding: KeyBindingEntry, index: Int) {
        self.binding = binding
        self.index = index
        self.actionLabel = NSTextField(labelWithString: binding.label)
        self.shortcutBadge = ShortcutBadge(shortcut: binding.shortcut)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        actionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        actionLabel.textColor = Theme.textPrimary
        addSubview(actionLabel)
        addSubview(shortcutBadge)

        shortcutBadge.onNewShortcut = { [weak self] shortcut in
            guard let self else { return }
            self.onShortcutChanged?(self.index, shortcut)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        actionLabel.frame = NSRect(x: 8, y: (h - 16) / 2, width: bounds.width - 170, height: 16)
        shortcutBadge.frame = NSRect(x: bounds.width - 155, y: (h - 28) / 2, width: 150, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor(white: 1, alpha: 0.03).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
    }

    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
}
