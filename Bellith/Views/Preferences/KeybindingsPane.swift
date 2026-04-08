import AppKit

// MARK: - Keybindings Pane

final class KeybindingsPane: NSView {
    private let settings: BellithSettings
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let heroCard = SettingsCard(title: "Command Map", subtitle: "Search, edit, and resolve shortcut conflicts")
    private let heroCountLabel = NSTextField(labelWithString: "")
    private let heroConflictLabel = NSTextField(labelWithString: "")
    private let searchLabel = CardRowLabel("Filter")
    private let searchField = NSSearchField()
    private let resetBtn = ResetDefaultsButton(title: "Reset All to Defaults")

    private var cards: [SettingsCard] = []
    private var categoryLayout: [(String, [Int])] = []
    private var searchQuery: String = ""
    private var conflictActionIDs: Set<String> = []

    init(frame frameRect: NSRect = .zero, settings: BellithSettings = .shared) {
        self.settings = settings
        super.init(frame: frameRect)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        addSubview(scroll)

        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.base.cgColor
        scroll.documentView = content

        heroCountLabel.font = BellithFont.display(34)
        heroCountLabel.textColor = Theme.textDisplay
        heroConflictLabel.font = BellithFont.mono(11, weight: .regular)
        heroConflictLabel.textColor = Theme.textSecondary
        content.addSubview(heroCard)
        heroCard.addSubview(heroCountLabel)
        heroCard.addSubview(heroConflictLabel)
        heroCard.addSubview(searchLabel)

        searchField.font = BellithFont.mono(12, weight: .regular)
        searchField.focusRingType = .none
        searchField.placeholderString = "Search commands or categories"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        heroCard.addSubview(searchField)

        resetBtn.onClick = { [weak self] in
            guard let self else { return }
            self.settings.keybindings = BellithSettings.defaultKeybindings
            self.searchQuery = ""
            self.searchField.stringValue = ""
            self.rebuildCards()
        }
        heroCard.addSubview(resetBtn)

        rebuildCards()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        content.layer?.backgroundColor = Theme.base.cgColor
        heroCard.refresh()
        searchField.stringValue = searchQuery
        rebuildCards()
    }

    @objc private func searchChanged() {
        searchQuery = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rebuildCards()
    }

    private func rebuildCards() {
        cards.forEach { $0.removeFromSuperview() }
        cards.removeAll()

        conflictActionIDs = computeConflictActionIDs()
        categoryLayout = filteredCategories()

        for (category, indices) in categoryLayout {
            let card = SettingsCard(title: category)
            content.addSubview(card)

            for index in indices {
                let binding = settings.keybindings[index]
                let row = KeybindingActionRow(binding: binding, index: index, isConflict: conflictActionIDs.contains(binding.id))
                row.onShortcutChanged = { [weak self] rowIndex, shortcut in
                    guard let self else { return }
                    var all = self.settings.keybindings
                    all[rowIndex].shortcut = shortcut
                    self.settings.keybindings = all
                    self.rebuildCards()
                }
                card.addSubview(row)
            }

            cards.append(card)
        }

        updateHero()
        needsLayout = true
    }

    private func updateHero() {
        let total = settings.keybindings.count
        let visible = categoryLayout.reduce(0) { $0 + $1.1.count }
        let conflictCount = conflictActionIDs.count
        heroCountLabel.stringValue = "\(visible) / \(total)"
        heroConflictLabel.stringValue = conflictCount == 0
            ? "[ CLEAN MAP ]"
            : "[ \(conflictCount) CONFLICT\(conflictCount == 1 ? "" : "S") ]"
        heroConflictLabel.textColor = conflictCount == 0 ? Theme.textSecondary : Theme.accent
    }

    private func filteredCategories() -> [(String, [Int])] {
        let bindings = settings.keybindings
        let query = searchQuery.lowercased()
        var categories: [(String, [Int])] = []
        var lastCategory = ""

        for (index, binding) in bindings.enumerated() {
            if !query.isEmpty {
                let haystack = [binding.label, binding.category, binding.id, binding.shortcut.displayString]
                    .joined(separator: " ")
                    .lowercased()
                guard haystack.contains(query) else { continue }
            }

            if binding.category != lastCategory {
                categories.append((binding.category, [index]))
                lastCategory = binding.category
            } else {
                categories[categories.count - 1].1.append(index)
            }
        }

        return categories
    }

    private func computeConflictActionIDs() -> Set<String> {
        let bindings = settings.keybindings
        var groups: [String: [String]] = [:]
        for binding in bindings {
            groups[binding.shortcut.displayString, default: []].append(binding.id)
        }

        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0 })
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let width = bounds.width
        let cardW = width - PreferencesLayout.hPad * 2
        let innerW = cardW - PreferencesLayout.cardPad * 2

        var y: CGFloat = PreferencesLayout.hPad

        let heroHeight: CGFloat = 176
        heroCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: heroHeight)
        heroCountLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 76, width: 180, height: 40)
        heroConflictLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 120, width: 220, height: 14)
        let searchRowY: CGFloat = 34
        searchLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: searchRowY, width: 60, height: PreferencesLayout.rowH)
        searchField.frame = NSRect(x: PreferencesLayout.cardPad + 74, y: searchRowY + 6, width: innerW - 270, height: 28)
        resetBtn.frame = NSRect(x: cardW - PreferencesLayout.cardPad - 180, y: searchRowY + 2, width: 180, height: 36)
        y += heroHeight + PreferencesLayout.sectionGap

        for (cardIndex, (_, indices)) in categoryLayout.enumerated() {
            guard cardIndex < cards.count else { continue }
            let card = cards[cardIndex]
            let rowCount = CGFloat(indices.count)
            let cardHeight = card.headerHeight + rowCount * PreferencesLayout.rowH + max(0, rowCount - 1) * PreferencesLayout.rowGap + PreferencesLayout.cardPad
            card.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: cardHeight)

            let rows = card.subviews.compactMap { $0 as? KeybindingActionRow }
            var rowY = cardHeight - card.headerHeight - PreferencesLayout.rowH
            for row in rows {
                row.frame = NSRect(x: PreferencesLayout.cardPad, y: rowY, width: innerW, height: PreferencesLayout.rowH)
                rowY -= PreferencesLayout.rowH + PreferencesLayout.rowGap
            }

            y += cardHeight + PreferencesLayout.sectionGap
        }

        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, bounds.height))
    }
}

// MARK: - Keybinding Action Row

final class KeybindingActionRow: NSView {
    var onShortcutChanged: ((Int, KeyShortcut) -> Void)?

    private let binding: KeyBindingEntry
    private let index: Int
    private let actionLabel: NSTextField
    private let conflictLabel = NSTextField(labelWithString: "[CONFLICT]")
    private let shortcutBadge: ShortcutBadge
    private let isConflict: Bool
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(binding: KeyBindingEntry, index: Int, isConflict: Bool) {
        self.binding = binding
        self.index = index
        self.isConflict = isConflict
        self.actionLabel = NSTextField(labelWithString: binding.label)
        self.shortcutBadge = ShortcutBadge(shortcut: binding.shortcut)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        actionLabel.font = BellithFont.ui(13, weight: .regular)
        actionLabel.textColor = Theme.textPrimary
        addSubview(actionLabel)

        conflictLabel.font = BellithFont.mono(10, weight: .regular)
        conflictLabel.textColor = Theme.accent
        conflictLabel.isHidden = !isConflict
        addSubview(conflictLabel)

        addSubview(shortcutBadge)
        shortcutBadge.onNewShortcut = { [weak self] shortcut in
            guard let self else { return }
            self.onShortcutChanged?(self.index, shortcut)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let labelWidth = bounds.width - 250
        actionLabel.frame = NSRect(x: 10, y: 12, width: labelWidth, height: 16)
        conflictLabel.frame = NSRect(x: 10 + labelWidth - 92, y: 14, width: 88, height: 12)
        shortcutBadge.frame = NSRect(x: bounds.width - 158, y: 6, width: 148, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isConflict {
            Theme.accent.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        } else if isHovered {
            Theme.hoverOverlay.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
    }

    override func updateTrackingAreas() {
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
}

extension KeybindingsPane: PreferencesPaneRefreshable {
    func refreshPreferencesPane() { refresh() }
}
