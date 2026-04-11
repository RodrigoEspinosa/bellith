import AppKit

final class KeybindingsPane: NSView {
    private enum ScopeFilter: String, CaseIterable {
        case all
        case globalApp
        case windowChrome
        case terminalFocused
        case modalOverlay

        var title: String {
            switch self {
            case .all: "All Scopes"
            case .globalApp: "App"
            case .windowChrome: "Window"
            case .terminalFocused: "Terminal"
            case .modalOverlay: "Overlay"
            }
        }

        var scope: ShortcutScope? {
            switch self {
            case .all: nil
            case .globalApp: .globalApp
            case .windowChrome: .windowChrome
            case .terminalFocused: .terminalFocused
            case .modalOverlay: .modalOverlay
            }
        }
    }

    private let settings: BellithSettings
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let paneTitleLabel = NSTextField(labelWithString: "Keybindings")
    private let paneSubtitleLabel = NSTextField(labelWithString: "Search commands, choose a preset, and customize shortcuts.")

    private let heroCard = SettingsCard(title: "Command Map", subtitle: "Presets, conflicts, alternates, and contextual guidance")
    private let heroCountLabel = NSTextField(labelWithString: "")
    private let heroConflictLabel = NSTextField(labelWithString: "")
    private let presetLabel = CardRowLabel("Preset")
    private let presetPopup = NSPopUpButton()
    private let scopeLabel = CardRowLabel("Scope")
    private let scopePopup = NSPopUpButton()
    private let searchLabel = CardRowLabel("Filter")
    private let searchField = NSSearchField()
    private let hintLabel = NSTextField(labelWithString: "Press Delete while recording to clear a shortcut.")
    private let resetBtn = ResetDefaultsButton(title: "Reset Visible")

    private var cards: [SettingsCard] = []
    private var categoryResetButtons: [CategoryResetButton] = []
    private var categoryLayout: [(String, [KeyBindingEntry])] = []
    private var searchQuery: String = ""
    private var scopeFilter: ScopeFilter = .all
    private var conflictTextByActionID: [String: String] = [:]

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
        content.layer?.backgroundColor = Theme.frame.cgColor
        scroll.documentView = content

        paneTitleLabel.font = BellithFont.ui(20, weight: .medium)
        paneTitleLabel.textColor = Theme.textDisplay
        content.addSubview(paneTitleLabel)

        paneSubtitleLabel.font = BellithFont.ui(12, weight: .regular)
        paneSubtitleLabel.textColor = Theme.textSecondary
        content.addSubview(paneSubtitleLabel)

        heroCountLabel.font = BellithFont.display(32)
        heroCountLabel.textColor = Theme.textDisplay
        content.addSubview(heroCard)
        heroCard.addSubview(heroCountLabel)

        heroConflictLabel.font = BellithFont.mono(11, weight: .regular)
        heroCard.addSubview(heroConflictLabel)

        for (label, popup) in [(presetLabel, presetPopup), (scopeLabel, scopePopup)] {
            popup.font = BellithFont.mono(12, weight: .regular)
            popup.focusRingType = .none
            popup.target = self
            popup.action = #selector(filterControlsChanged)
            heroCard.addSubview(label)
            heroCard.addSubview(popup)
        }

        ShortcutPresetID.allCases.forEach { presetPopup.addItem(withTitle: $0.title) }
        ScopeFilter.allCases.forEach { scopePopup.addItem(withTitle: $0.title) }

        searchField.font = BellithFont.mono(12, weight: .regular)
        searchField.focusRingType = .none
        searchField.placeholderString = "Search commands, shortcuts, or help text"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        heroCard.addSubview(searchLabel)
        heroCard.addSubview(searchField)

        hintLabel.font = BellithFont.mono(10, weight: .regular)
        hintLabel.textColor = Theme.textMuted
        heroCard.addSubview(hintLabel)

        resetBtn.onClick = { [weak self] in
            guard let self else { return }
            for (_, bindings) in self.categoryLayout {
                for binding in bindings {
                    self.settings.reset(actionId: binding.id)
                }
            }
            self.rebuildCards()
        }
        heroCard.addSubview(resetBtn)

        rebuildCards()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        content.layer?.backgroundColor = Theme.frame.cgColor
        paneTitleLabel.textColor = Theme.textDisplay
        paneSubtitleLabel.textColor = Theme.textSecondary
        heroCard.refresh()
        presetPopup.selectItem(at: ShortcutPresetID.allCases.firstIndex(of: settings.shortcutPreset) ?? 0)
        scopePopup.selectItem(at: ScopeFilter.allCases.firstIndex(of: scopeFilter) ?? 0)
        searchField.stringValue = searchQuery
        rebuildCards()
    }

    @objc private func searchChanged() {
        searchQuery = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rebuildCards()
    }

    @objc private func filterControlsChanged() {
        if let preset = ShortcutPresetID.allCases[safe: presetPopup.indexOfSelectedItem],
           preset != settings.shortcutPreset {
            settings.applyPreset(preset)
        }

        if let selectedScope = ScopeFilter.allCases[safe: scopePopup.indexOfSelectedItem] {
            scopeFilter = selectedScope
        }

        rebuildCards()
    }

    private func rebuildCards() {
        cards.forEach { $0.removeFromSuperview() }
        cards.removeAll()
        categoryResetButtons.removeAll()

        conflictTextByActionID = computeConflictTextByActionID()
        categoryLayout = filteredCategories()

        for (category, bindings) in categoryLayout {
            let card = SettingsCard(title: category)
            let resetButton = CategoryResetButton(title: "Reset Category")
            resetButton.onClick = { [weak self] in
                self?.settings.reset(category: category)
                self?.rebuildCards()
            }
            card.addSubview(resetButton)

            for binding in bindings {
                let row = KeybindingActionRow(
                    binding: binding,
                    conflictText: conflictTextByActionID[binding.id]
                )
                row.onUpdate = { [weak self] updated in
                    self?.replaceBinding(updated)
                }
                row.onReset = { [weak self] actionID in
                    self?.settings.reset(actionId: actionID)
                    self?.rebuildCards()
                }
                card.addSubview(row)
            }

            content.addSubview(card)
            cards.append(card)
            categoryResetButtons.append(resetButton)
        }

        updateHero()
        needsLayout = true
    }

    private func replaceBinding(_ updated: KeyBindingEntry) {
        var all = settings.keybindings
        guard let index = all.firstIndex(where: { $0.id == updated.id }) else { return }
        all[index] = updated
        settings.keybindings = all
        rebuildCards()
    }

    private func updateHero() {
        let total = settings.keybindings.count
        let visible = categoryLayout.reduce(0) { $0 + $1.1.count }
        let conflictCount = Set(conflictTextByActionID.keys).count
        heroCountLabel.stringValue = "\(visible) / \(total)"
        heroConflictLabel.stringValue = conflictCount == 0
            ? "[ CLEAN MAP ]"
            : "[ \(conflictCount) ACTION\(conflictCount == 1 ? "" : "S") IN CONFLICT ]"
        heroConflictLabel.textColor = conflictCount == 0 ? Theme.textSecondary : Theme.accent
        hintLabel.stringValue = settings.shortcutPreset.subtitle
        presetPopup.selectItem(at: ShortcutPresetID.allCases.firstIndex(of: settings.shortcutPreset) ?? 0)
        scopePopup.selectItem(at: ScopeFilter.allCases.firstIndex(of: scopeFilter) ?? 0)
    }

    private func filteredCategories() -> [(String, [KeyBindingEntry])] {
        let bindings = settings.keybindings
        let query = searchQuery.lowercased()
        var categories: [(String, [KeyBindingEntry])] = []
        var lastCategory = ""

        for binding in bindings {
            if let selectedScope = scopeFilter.scope, binding.scope != selectedScope {
                continue
            }

            if !query.isEmpty {
                let haystack = [
                    binding.label,
                    binding.category,
                    binding.id,
                    binding.scope.title,
                    binding.discoverabilityText,
                    binding.shortcutSummary,
                ]
                .joined(separator: " ")
                .lowercased()
                guard haystack.contains(query) else { continue }
            }

            if binding.category != lastCategory {
                categories.append((binding.category, [binding]))
                lastCategory = binding.category
            } else {
                categories[categories.count - 1].1.append(binding)
            }
        }

        return categories
    }

    private func computeConflictTextByActionID() -> [String: String] {
        var result: [String: String] = [:]
        for conflict in settings.conflicts() {
            let text = "[CONFLICT \(conflict.shortcut.displayString)]"
            for actionID in conflict.actionIDs {
                result[actionID] = result[actionID].map { "\($0)  \(text)" } ?? text
            }
        }
        return result
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let width = bounds.width
        let cardW = width - PreferencesLayout.hPad * 2
        let innerW = cardW - PreferencesLayout.cardPad * 2
        var y: CGFloat = PreferencesLayout.hPad

        paneTitleLabel.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: 280, height: 24)
        paneSubtitleLabel.frame = NSRect(x: PreferencesLayout.hPad, y: y + 28, width: cardW, height: 16)
        y += 60

        let heroHeight: CGFloat = 248
        heroCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: heroHeight)
        heroCountLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 26, width: 180, height: 40)
        heroConflictLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 72, width: 320, height: 14)

        let searchRowY = heroHeight - heroCard.headerHeight - 46
        searchLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: searchRowY + 2, width: 56, height: PreferencesLayout.rowH)
        searchField.frame = NSRect(x: PreferencesLayout.cardPad + 74, y: searchRowY + 8, width: innerW - 260, height: 28)
        resetBtn.frame = NSRect(x: cardW - PreferencesLayout.cardPad - 160, y: searchRowY + 2, width: 160, height: 36)

        let controlsRowY = searchRowY - 46
        presetLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: controlsRowY + 2, width: 62, height: PreferencesLayout.rowH)
        presetPopup.frame = NSRect(x: PreferencesLayout.cardPad + 74, y: controlsRowY + 8, width: 200, height: 28)
        scopeLabel.frame = NSRect(x: PreferencesLayout.cardPad + 296, y: controlsRowY + 2, width: 52, height: PreferencesLayout.rowH)
        scopePopup.frame = NSRect(x: PreferencesLayout.cardPad + 358, y: controlsRowY + 8, width: 148, height: 28)

        hintLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 14, width: innerW - 180, height: 12)
        y += heroHeight + PreferencesLayout.sectionGap

        for (cardIndex, _) in categoryLayout.enumerated() {
            guard cardIndex < cards.count else { continue }
            let card = cards[cardIndex]
            let rows = card.subviews.compactMap { $0 as? KeybindingActionRow }
            let cardHeight = card.headerHeight
                + rows.reduce(CGFloat(0)) { $0 + $1.preferredHeight }
                + CGFloat(max(0, rows.count - 1)) * 10
                + PreferencesLayout.cardPad * 2
            card.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: cardHeight)

            if cardIndex < categoryResetButtons.count {
                let resetButton = categoryResetButtons[cardIndex]
                resetButton.frame = NSRect(
                    x: cardW - PreferencesLayout.cardPad - 122,
                    y: cardHeight - 18 - 28,
                    width: 122,
                    height: 28
                )
            }

            var rowY = cardHeight - card.headerHeight - PreferencesLayout.cardPad
            for (index, row) in rows.enumerated() {
                rowY -= row.preferredHeight
                row.frame = NSRect(
                    x: PreferencesLayout.cardPad,
                    y: rowY,
                    width: innerW,
                    height: row.preferredHeight
                )
                if index < rows.count - 1 {
                    rowY -= 10
                }
            }

            y += cardHeight + PreferencesLayout.sectionGap
        }

        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, bounds.height))
    }
}

private final class KeybindingActionRow: NSView {
    var onUpdate: ((KeyBindingEntry) -> Void)?
    var onReset: ((String) -> Void)?

    private var binding: KeyBindingEntry
    private let titleLabel = NSTextField(labelWithString: "")
    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let conflictLabel = NSTextField(labelWithString: "")
    private let primaryLabel = SmallLabel("Primary")
    private let primaryBadge: ShortcutBadge
    private let addAlternateButton = InlineTextButton(title: "+ Alternate")
    private let resetButton = InlineTextButton(title: "Reset")
    private var alternateEditors: [AlternateEditorRow] = []
    private var pendingAlternateSlots = 0
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    var preferredHeight: CGFloat {
        94 + CGFloat(alternateEditors.count) * 34
    }

    init(binding: KeyBindingEntry, conflictText: String?) {
        self.binding = binding
        self.primaryBadge = ShortcutBadge(shortcut: binding.primaryShortcut)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10

        titleLabel.stringValue = binding.label
        titleLabel.font = BellithFont.ui(13, weight: .regular)
        titleLabel.textColor = Theme.textPrimary
        addSubview(titleLabel)

        descriptionLabel.stringValue = binding.discoverabilityText
        descriptionLabel.font = BellithFont.ui(11, weight: .regular)
        descriptionLabel.textColor = Theme.textSecondary
        addSubview(descriptionLabel)

        let reservedTag = binding.isReserved ? "RESERVED" : "PASS-THROUGH"
        metaLabel.stringValue = "[\(binding.scope.title.uppercased())] [\(reservedTag)]"
        metaLabel.font = BellithFont.mono(10, weight: .regular)
        metaLabel.textColor = Theme.textMuted
        addSubview(metaLabel)

        conflictLabel.stringValue = conflictText ?? ""
        conflictLabel.font = BellithFont.mono(10, weight: .regular)
        conflictLabel.textColor = Theme.accent
        conflictLabel.isHidden = conflictText == nil
        addSubview(conflictLabel)

        addSubview(primaryLabel)
        addSubview(primaryBadge)
        primaryBadge.onNewShortcut = { [weak self] shortcut in
            guard let self else { return }
            self.binding.primaryShortcut = shortcut
            self.onUpdate?(self.binding)
        }

        addAlternateButton.onClick = { [weak self] in
            guard let self else { return }
            self.pendingAlternateSlots += 1
            self.rebuildAlternateEditors()
            self.needsLayout = true
            self.superview?.needsLayout = true
        }
        addSubview(addAlternateButton)

        resetButton.onClick = { [weak self] in
            guard let self else { return }
            self.onReset?(self.binding.id)
        }
        addSubview(resetButton)

        rebuildAlternateEditors()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let rowInset: CGFloat = 12
        let actionColumnWidth: CGFloat = 286
        let actionColumnX = bounds.width - actionColumnWidth - rowInset
        let textWidth = actionColumnX - rowInset * 2

        titleLabel.frame = NSRect(x: rowInset, y: bounds.height - 26, width: textWidth, height: 16)
        metaLabel.frame = NSRect(x: rowInset, y: bounds.height - 44, width: textWidth, height: 12)
        descriptionLabel.frame = NSRect(x: rowInset, y: bounds.height - 72, width: textWidth, height: 26)
        conflictLabel.frame = NSRect(x: rowInset, y: 12, width: textWidth, height: 12)

        primaryLabel.frame = NSRect(x: actionColumnX, y: bounds.height - 28, width: 56, height: 18)
        primaryBadge.frame = NSRect(x: actionColumnX + 64, y: bounds.height - 34, width: 140, height: 30)
        addAlternateButton.frame = NSRect(x: actionColumnX + 214, y: bounds.height - 28, width: 68, height: 18)
        resetButton.frame = NSRect(x: actionColumnX + 214, y: 12, width: 68, height: 18)

        var altY = bounds.height - 68
        for editor in alternateEditors {
            editor.frame = NSRect(x: actionColumnX, y: altY, width: actionColumnWidth, height: 28)
            altY -= 34
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if conflictLabel.isHidden == false {
            Theme.accent.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        } else if isHovered {
            Theme.hoverOverlay.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        }
    }

    override func updateTrackingAreas() {
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    private func rebuildAlternateEditors() {
        alternateEditors.forEach { $0.removeFromSuperview() }
        alternateEditors.removeAll()

        for (index, shortcut) in binding.alternateShortcuts.enumerated() {
            let editor = AlternateEditorRow(index: index + 1, shortcut: shortcut, isPending: false)
            editor.onShortcutChanged = { [weak self] altIndex, newShortcut in
                guard let self else { return }
                self.binding.setAlternateShortcut(newShortcut, at: altIndex)
                self.onUpdate?(self.binding)
            }
            editor.onRemove = { [weak self] altIndex in
                guard let self else { return }
                self.binding.setAlternateShortcut(nil, at: altIndex)
                self.onUpdate?(self.binding)
            }
            addSubview(editor)
            alternateEditors.append(editor)
        }

        let startIndex = binding.alternateShortcuts.count
        for pendingOffset in 0..<pendingAlternateSlots {
            let editor = AlternateEditorRow(index: startIndex + pendingOffset + 1, shortcut: nil, isPending: true)
            editor.onShortcutChanged = { [weak self] altIndex, newShortcut in
                guard let self, let newShortcut else { return }
                self.binding.setAlternateShortcut(newShortcut, at: altIndex)
                self.pendingAlternateSlots = max(0, self.pendingAlternateSlots - 1)
                self.onUpdate?(self.binding)
            }
            editor.onRemove = { [weak self] _ in
                guard let self else { return }
                self.pendingAlternateSlots = max(0, self.pendingAlternateSlots - 1)
                self.rebuildAlternateEditors()
                self.needsLayout = true
                self.superview?.needsLayout = true
            }
            addSubview(editor)
            alternateEditors.append(editor)
        }
    }
}

private final class AlternateEditorRow: NSView {
    var onShortcutChanged: ((Int, KeyShortcut?) -> Void)?
    var onRemove: ((Int) -> Void)?

    private let index: Int
    private let label: SmallLabel
    private let badge: ShortcutBadge
    private let removeButton = InlineTextButton(title: "Remove")

    init(index: Int, shortcut: KeyShortcut?, isPending: Bool) {
        self.index = index - 1
        self.label = SmallLabel(isPending ? "Alt \(index) *" : "Alt \(index)")
        self.badge = ShortcutBadge(shortcut: shortcut)
        super.init(frame: .zero)
        addSubview(label)
        addSubview(badge)
        addSubview(removeButton)

        badge.onNewShortcut = { [weak self] shortcut in
            guard let self else { return }
            self.onShortcutChanged?(self.index, shortcut)
        }

        removeButton.onClick = { [weak self] in
            guard let self else { return }
            self.onRemove?(self.index)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: 5, width: 44, height: 18)
        badge.frame = NSRect(x: 54, y: 0, width: 190, height: 28)
        removeButton.frame = NSRect(x: bounds.width - 60, y: 5, width: 52, height: 18)
    }
}

private final class InlineTextButton: NSView {
    var onClick: (() -> Void)?

    private let label: NSTextField
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(title: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        label.font = BellithFont.mono(10, weight: .regular)
        label.textColor = Theme.textMuted
        addSubview(label)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        label.frame = bounds
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func updateTrackingAreas() {
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        label.textColor = Theme.textSecondary
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        label.textColor = Theme.textMuted
    }
}

private final class CategoryResetButton: NSView {
    var onClick: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        label.stringValue = title.uppercased()
        label.font = BellithFont.mono(10, weight: .regular)
        label.alignment = .center
        addSubview(label)
        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        label.frame = bounds
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func updateTrackingAreas() {
        if let area = trackingArea { removeTrackingArea(area) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; refresh() }
    override func mouseExited(with event: NSEvent) { isHovered = false; refresh() }

    private func refresh() {
        layer?.backgroundColor = (isHovered ? Theme.overlay : Theme.surface.withAlphaComponent(0.6)).cgColor
        label.textColor = isHovered ? Theme.textSecondary : Theme.textMuted
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension KeybindingsPane: PreferencesPaneRefreshable {
    func refreshPreferencesPane() { refresh() }
}
