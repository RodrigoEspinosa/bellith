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
