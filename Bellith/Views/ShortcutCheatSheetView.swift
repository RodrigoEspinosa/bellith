import AppKit

fileprivate struct ShortcutCheatSheetSection {
    let title: String
    let bindings: [KeyBindingEntry]
}

final class ShortcutCheatSheetView: NSView {

    private let settings: BellithSettings
    private let backdrop = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "Keyboard Shortcuts")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let dismissLabel = NSTextField(labelWithString: "ESC to close")
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private var sections: [ShortcutCheatSheetSection] = []
    private var sectionViews: [ShortcutCheatSheetSectionView] = []
    private var searchVisible = false
    private var paletteVisible = false

    var onDismiss: (() -> Void)?

    init(frame frameRect: NSRect = .zero, settings: BellithSettings = .shared) {
        self.settings = settings
        super.init(frame: frameRect)
        wantsLayer = true
        alphaValue = 0

        backdrop.material = .hudWindow
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Theme.radiusPanel
        backdrop.layer?.masksToBounds = true
        addSubview(backdrop)

        titleLabel.font = BellithFont.display(26)
        titleLabel.textColor = Theme.textDisplay
        addSubview(titleLabel)

        subtitleLabel.font = BellithFont.mono(11, weight: .regular)
        subtitleLabel.textColor = Theme.textSecondary
        addSubview(subtitleLabel)

        dismissLabel.font = BellithFont.mono(10, weight: .regular)
        dismissLabel.textColor = Theme.textMuted
        addSubview(dismissLabel)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = content
        addSubview(scroll)

        refreshTheme()
        rebuildSections()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    func refreshTheme() {
        backdrop.appearance = Theme.overlayAppearance
        backdrop.layer?.backgroundColor = Theme.chromePanel.cgColor
        titleLabel.textColor = Theme.textDisplay
        subtitleLabel.textColor = Theme.textSecondary
        dismissLabel.textColor = Theme.textMuted
        content.layer?.backgroundColor = NSColor.clear.cgColor
        sectionViews.forEach { $0.refreshTheme() }
    }

    func setContext(searchVisible: Bool, paletteVisible: Bool) {
        self.searchVisible = searchVisible
        self.paletteVisible = paletteVisible
        rebuildSections()
    }

    func show(in parent: NSView) {
        let width = min(760, parent.bounds.width - 80)
        let height = min(560, parent.bounds.height - 80)
        let x = (parent.bounds.width - width) / 2
        let y = (parent.bounds.height - height) / 2
        frame = NSRect(x: x, y: y + 12, width: width, height: height)
        parent.addSubview(self)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.animMedium
            context.allowsImplicitAnimation = true
            animator().alphaValue = 1
            animator().frame = NSRect(x: x, y: y, width: width, height: height)
        }
    }

    func hide() {
        let targetFrame = NSRect(x: frame.origin.x, y: frame.origin.y + 12, width: frame.width, height: frame.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.animFast
            context.allowsImplicitAnimation = true
            animator().alphaValue = 0
            animator().frame = targetFrame
        } completionHandler: {
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds

        titleLabel.frame = NSRect(x: 24, y: 18, width: bounds.width - 200, height: 28)
        subtitleLabel.frame = NSRect(x: 24, y: 50, width: bounds.width - 220, height: 14)
        dismissLabel.frame = NSRect(x: bounds.width - 110, y: 22, width: 86, height: 12)
        scroll.frame = NSRect(x: 16, y: 76, width: bounds.width - 32, height: bounds.height - 92)

        var y: CGFloat = 0
        for sectionView in sectionViews {
            let height = sectionView.preferredHeight(width: scroll.contentSize.width)
            sectionView.frame = NSRect(x: 0, y: y, width: scroll.contentSize.width, height: height)
            y += height + 14
        }
        content.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(y, scroll.contentSize.height))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            hide()
            return
        }
        super.keyDown(with: event)
    }

    private func rebuildSections() {
        sectionViews.forEach { $0.removeFromSuperview() }
        sectionViews.removeAll()

        let prioritizedCategories = prioritizedCategoryOrder()
        let allBindings = settings.keybindings.filter { !$0.allShortcuts.isEmpty }
        var grouped: [String: [KeyBindingEntry]] = [:]
        for binding in allBindings {
            grouped[binding.category, default: []].append(binding)
        }

        sections = prioritizedCategories.compactMap { category in
            guard let bindings = grouped[category] else { return nil }
            return ShortcutCheatSheetSection(title: category, bindings: bindings)
        }

        subtitleLabel.stringValue = contextualSubtitle()

        for section in sections {
            let view = ShortcutCheatSheetSectionView(section: section)
            content.addSubview(view)
            sectionViews.append(view)
        }

        needsLayout = true
    }

    private func prioritizedCategoryOrder() -> [String] {
        let defaultOrder = settings.keybindings.map(\.category).reduce(into: [String]()) { order, category in
            if !order.contains(category) { order.append(category) }
        }

        let preferred: [String]
        if searchVisible {
            preferred = ["Search"]
        } else if paletteVisible {
            preferred = ["Navigation", "App"]
        } else {
            preferred = ["Navigation", "Tabs", "Panes", "Edit", "Window", "App", "View", "Terminal", "Search"]
        }

        return (preferred + defaultOrder).reduce(into: [String]()) { order, category in
            if !order.contains(category) { order.append(category) }
        }
    }

    private func contextualSubtitle() -> String {
        if searchVisible {
            return "[ Search focus ] Find, next, previous, and dismiss shortcuts are highlighted first."
        }
        if paletteVisible {
            return "[ Palette focus ] Use the palette for command discovery, then return here for muscle memory."
        }
        return "[ Terminal focus ] Bellith reserves only the listed combos; everything else keeps flowing to the terminal."
    }
}

private final class ShortcutCheatSheetSectionView: NSView {
    private let section: ShortcutCheatSheetSection
    private let card: SettingsCard
    private var rows: [ShortcutCheatSheetRow] = []

    init(section: ShortcutCheatSheetSection) {
        self.section = section
        self.card = SettingsCard(title: section.title)
        super.init(frame: .zero)
        card.refresh()
        addSubview(card)

        for binding in section.bindings {
            let row = ShortcutCheatSheetRow(binding: binding)
            rows.append(row)
            card.addSubview(row)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refreshTheme() {
        card.refresh()
        rows.forEach { $0.refreshTheme() }
    }

    func preferredHeight(width: CGFloat) -> CGFloat {
        card.headerHeight + CGFloat(rows.count) * 48 + CGFloat(max(0, rows.count - 1)) * 8 + PreferencesLayout.cardPad
    }

    override func layout() {
        super.layout()
        card.frame = bounds
        var y = card.headerHeight
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: PreferencesLayout.cardPad, y: y, width: bounds.width - PreferencesLayout.cardPad * 2, height: 48)
            y += 48
            if index < rows.count - 1 {
                y += 8
            }
        }
    }
}

private final class ShortcutCheatSheetRow: NSView {
    private let binding: KeyBindingEntry
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    init(binding: KeyBindingEntry) {
        self.binding = binding
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        titleLabel.stringValue = binding.label
        titleLabel.font = BellithFont.ui(13, weight: .regular)
        addSubview(titleLabel)

        detailLabel.stringValue = "[\(binding.scope.title.uppercased())] \(binding.discoverabilityText)"
        detailLabel.font = BellithFont.mono(10, weight: .regular)
        addSubview(detailLabel)

        shortcutLabel.stringValue = binding.shortcutSummary
        shortcutLabel.font = BellithFont.mono(12, weight: .regular)
        shortcutLabel.alignment = .right
        addSubview(shortcutLabel)

        refreshTheme()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refreshTheme() {
        layer?.backgroundColor = Theme.surface.withAlphaComponent(0.45).cgColor
        titleLabel.textColor = Theme.textPrimary
        detailLabel.textColor = Theme.textMuted
        shortcutLabel.textColor = Theme.textSecondary
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 12, y: 9, width: bounds.width - 220, height: 16)
        detailLabel.frame = NSRect(x: 12, y: 26, width: bounds.width - 220, height: 12)
        shortcutLabel.frame = NSRect(x: bounds.width - 210, y: 14, width: 198, height: 18)
    }
}

final class ModifierShortcutHintsView: NSView {
    struct Item {
        let key: String
        let label: String
        let detail: String?
        let isSelected: Bool
    }

    struct Section {
        let title: String
        let items: [Item]
    }

    fileprivate enum Metrics {
        static let horizontalInset: CGFloat = 28
        static let headerBlockHeight: CGFloat = 72
        static let contentBottomInset: CGFloat = 22
        static let sectionGap: CGFloat = 24
        static let rowHeight: CGFloat = 44
        static let categoryColumn: CGFloat = 88
        static let keyColumn: CGFloat = 56
        static let keyBadgeWidth: CGFloat = 42
        static let keyBadgeHeight: CGFloat = 26
        static let stateColumn: CGFloat = 60
    }

    private let backdrop = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let accentRule = NSView()
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private var sections: [Section] = []
    private var sectionViews: [ModifierShortcutHintsSectionView] = []

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        wantsLayer = true
        alphaValue = 0

        backdrop.material = .hudWindow
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Theme.radiusPanel
        backdrop.layer?.masksToBounds = true
        addSubview(backdrop)

        titleLabel.font = BellithFont.ui(22, weight: .medium)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        hintLabel.font = BellithFont.mono(10, weight: .regular)
        hintLabel.alignment = .right
        addSubview(hintLabel)

        accentRule.wantsLayer = true
        accentRule.layer?.cornerRadius = 1
        addSubview(accentRule)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = content
        addSubview(scroll)

        refreshTheme()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func update(title: String, subtitle: String, sections: [Section]) {
        titleLabel.stringValue = formattedTitle(from: title)
        hintLabel.stringValue = subtitle.uppercased()
        self.sections = sections
        rebuildSections()
    }

    func refreshTheme() {
        backdrop.appearance = Theme.overlayAppearance
        backdrop.layer?.backgroundColor = Theme.chromePanel.cgColor
        titleLabel.textColor = Theme.textDisplay
        hintLabel.textColor = Theme.textMuted
        accentRule.layer?.backgroundColor = Theme.accent.cgColor
        sectionViews.forEach { $0.refreshTheme() }
    }

    func show(in parent: NSView) {
        let width = min(640, parent.bounds.width - 96)
        let targetHeight = min(max(preferredHeight(width: width), 200), parent.bounds.height - 120)
        let x = (parent.bounds.width - width) / 2
        let y = parent.bounds.height - targetHeight - 54
        let targetFrame = NSRect(x: x, y: y, width: width, height: targetHeight)

        if superview == nil {
            frame = targetFrame.offsetBy(dx: 0, dy: 10)
            parent.addSubview(self)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Theme.animFast
                context.allowsImplicitAnimation = true
                animator().alphaValue = 1
                animator().frame = targetFrame
            }
        } else {
            frame = targetFrame
        }
    }

    func hide() {
        guard superview != nil else { return }
        let targetFrame = frame.offsetBy(dx: 0, dy: 10)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Theme.animFast
            context.allowsImplicitAnimation = true
            animator().alphaValue = 0
            animator().frame = targetFrame
        }, completionHandler: { [weak self] in
            self?.removeFromSuperview()
        })
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds

        let inset = Metrics.horizontalInset
        let titleHeight: CGFloat = 26
        let titleY = bounds.height - inset - titleHeight + 2
        let hintHeight: CGFloat = 12
        let hintWidth: CGFloat = 260

        titleLabel.frame = NSRect(
            x: inset,
            y: titleY,
            width: max(0, bounds.width - inset * 2 - hintWidth - 16),
            height: titleHeight
        )
        hintLabel.frame = NSRect(
            x: bounds.width - inset - hintWidth,
            y: titleY + (titleHeight - hintHeight) / 2,
            width: hintWidth,
            height: hintHeight
        )

        let ruleY = titleY - 14
        accentRule.frame = NSRect(x: inset, y: ruleY, width: 24, height: 2)

        let scrollTop = ruleY - 12
        let scrollBottom = Metrics.contentBottomInset
        scroll.frame = NSRect(
            x: inset - 4,
            y: scrollBottom,
            width: bounds.width - (inset - 4) * 2,
            height: max(0, scrollTop - scrollBottom)
        )

        var y: CGFloat = 0
        for (index, sectionView) in sectionViews.enumerated() {
            let height = sectionView.preferredHeight(width: scroll.contentSize.width)
            sectionView.frame = NSRect(x: 0, y: y, width: scroll.contentSize.width, height: height)
            y += height
            if index < sectionViews.count - 1 { y += Metrics.sectionGap }
        }
        content.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(y, scroll.contentSize.height))
    }

    private func rebuildSections() {
        sectionViews.forEach { $0.removeFromSuperview() }
        sectionViews.removeAll()

        for section in sections {
            let view = ModifierShortcutHintsSectionView(section: section)
            content.addSubview(view)
            sectionViews.append(view)
        }

        needsLayout = true
    }

    private func preferredHeight(width: CGFloat) -> CGFloat {
        let contentWidth = max(width - (Metrics.horizontalInset - 4) * 2, 320)
        let sectionsHeight = sections.reduce(CGFloat.zero) { partial, section in
            partial + ModifierShortcutHintsSectionView.preferredHeight(for: section, width: contentWidth)
        }
        let sectionGaps = CGFloat(max(0, sections.count - 1)) * Metrics.sectionGap
        return Metrics.headerBlockHeight + sectionsHeight + sectionGaps + Metrics.contentBottomInset + 8
    }

    private func formattedTitle(from raw: String) -> String {
        // Controller passes e.g. "⇧⌘ shortcuts" — uppercase the word portion only.
        let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return raw.uppercased() }
        return "\(parts[0])  \(parts[1].uppercased())"
    }
}

private final class ModifierShortcutHintsSectionView: NSView {
    override var isFlipped: Bool { true }

    private let section: ModifierShortcutHintsView.Section
    private var rows: [ModifierShortcutHintsRow] = []

    init(section: ModifierShortcutHintsView.Section) {
        self.section = section
        super.init(frame: .zero)

        for (index, item) in section.items.enumerated() {
            let row = ModifierShortcutHintsRow(
                item: item,
                categoryTitle: section.title,
                showsCategory: index == 0
            )
            rows.append(row)
            addSubview(row)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    static func preferredHeight(for section: ModifierShortcutHintsView.Section, width: CGFloat) -> CGFloat {
        CGFloat(section.items.count) * ModifierShortcutHintsView.Metrics.rowHeight
    }

    func preferredHeight(width: CGFloat) -> CGFloat {
        Self.preferredHeight(for: section, width: width)
    }

    func refreshTheme() {
        rows.forEach { $0.refreshTheme() }
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for row in rows {
            row.frame = NSRect(x: 0, y: y, width: bounds.width, height: ModifierShortcutHintsView.Metrics.rowHeight)
            y += ModifierShortcutHintsView.Metrics.rowHeight
        }
    }
}

private final class ModifierShortcutHintsRow: NSView {
    override var isFlipped: Bool { true }

    private let item: ModifierShortcutHintsView.Item
    private let showsCategory: Bool
    private let categoryLabel = NSTextField(labelWithString: "")
    private let selectionDot = NSView()
    private let keyBadge = NSView()
    private let keyLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "CURRENT")

    init(item: ModifierShortcutHintsView.Item, categoryTitle: String, showsCategory: Bool) {
        self.item = item
        self.showsCategory = showsCategory
        super.init(frame: .zero)

        categoryLabel.stringValue = showsCategory ? categoryTitle.uppercased() : ""
        categoryLabel.font = BellithFont.mono(10, weight: .regular)
        addSubview(categoryLabel)

        selectionDot.wantsLayer = true
        selectionDot.layer?.cornerRadius = 2.5
        selectionDot.isHidden = !item.isSelected
        addSubview(selectionDot)

        keyBadge.wantsLayer = true
        keyBadge.layer?.cornerRadius = 5
        keyBadge.layer?.borderWidth = 0.5
        addSubview(keyBadge)

        keyLabel.stringValue = item.key
        keyLabel.font = BellithFont.mono(12, weight: .regular)
        keyLabel.alignment = .center
        keyBadge.addSubview(keyLabel)

        titleLabel.stringValue = item.label
        titleLabel.font = BellithFont.ui(13, weight: .regular)
        addSubview(titleLabel)

        detailLabel.stringValue = item.detail ?? ""
        detailLabel.font = BellithFont.mono(10, weight: .regular)
        detailLabel.isHidden = item.detail?.isEmpty != false
        addSubview(detailLabel)

        stateLabel.font = BellithFont.mono(9, weight: .regular)
        stateLabel.alignment = .right
        stateLabel.isHidden = !item.isSelected
        addSubview(stateLabel)

        refreshTheme()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refreshTheme() {
        categoryLabel.textColor = Theme.textMuted
        keyBadge.layer?.backgroundColor = NSColor.clear.cgColor
        keyBadge.layer?.borderColor = (item.isSelected ? Theme.accent.withAlphaComponent(0.5) : Theme.border).cgColor
        keyLabel.textColor = item.isSelected ? Theme.accent : Theme.textPrimary
        titleLabel.textColor = Theme.textPrimary
        detailLabel.textColor = Theme.textMuted
        selectionDot.layer?.backgroundColor = Theme.accent.cgColor
        stateLabel.textColor = Theme.accent
    }

    override func layout() {
        super.layout()
        typealias M = ModifierShortcutHintsView.Metrics
        let keyX = M.categoryColumn
        let textX = keyX + M.keyColumn

        categoryLabel.frame = NSRect(
            x: 0,
            y: 8,
            width: M.categoryColumn - 10,
            height: 14
        )

        let badgeY = (bounds.height - M.keyBadgeHeight) / 2
        keyBadge.frame = NSRect(x: keyX, y: badgeY, width: M.keyBadgeWidth, height: M.keyBadgeHeight)
        keyLabel.frame = keyBadge.bounds

        if item.isSelected {
            selectionDot.frame = NSRect(x: keyX - 12, y: bounds.height / 2 - 2.5, width: 5, height: 5)
        }

        let stateReserve: CGFloat = item.isSelected ? M.stateColumn : 0
        let textWidth = max(0, bounds.width - textX - 12 - stateReserve)
        if detailLabel.isHidden {
            titleLabel.frame = NSRect(x: textX, y: (bounds.height - 16) / 2, width: textWidth, height: 16)
            detailLabel.frame = .zero
        } else {
            titleLabel.frame = NSRect(x: textX, y: 8, width: textWidth, height: 16)
            detailLabel.frame = NSRect(x: textX, y: 26, width: textWidth, height: 12)
        }

        if item.isSelected {
            stateLabel.frame = NSRect(
                x: bounds.width - M.stateColumn - 4,
                y: (bounds.height - 12) / 2,
                width: M.stateColumn,
                height: 12
            )
        }
    }
}
