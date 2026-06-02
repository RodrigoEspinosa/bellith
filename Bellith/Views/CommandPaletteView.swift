import AppKit

/// Zen-style command palette overlay with autocomplete.
/// Frosted dark glass panel centered near the top of the window.
final class CommandPaletteView: NSView {
    private let backdrop = NSVisualEffectView()
    private let inputField = NSTextField()
    private let iconView = NSImageView()
    private let separatorLine = NSView()
    private let escKbd = KbdView(text: "esc")
    private var borderLayer: CALayer?

    // Results list
    private let resultsContainer = NSView()
    private var resultRows: [CommandRow] = []
    private var selectedResultIndex: Int = -1
    private var isShowingResults = false
    private let commandRegistry: CommandRegistry
    private let settings: BellithSettings

    // PR Popover v2 footer keymap row.
    private let footerContainer = NSView()
    private let footerLineLayer = CALayer()
    private let footerNavHint = KbdHintView(key: "↑↓", hint: "navigate")
    private let footerRunHint = KbdHintView(key: "⏎", hint: "run")
    private let footerEscHint = KbdHintView(key: "esc", hint: "close")
    private let footerHeight: CGFloat = 28

    var onSubmit: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    typealias CommandItem = (id: String, label: String, description: String, icon: String, shortcutId: String?)

    static func commands(using commandRegistry: CommandRegistry = .shared) -> [CommandItem] {
        commandRegistry.allCommands.map { command in
            (command.id, command.title, command.description, command.iconName, command.shortcutID)
        }
    }

    private var themeObserver: NSObjectProtocol?

    init(
        frame frameRect: NSRect = .zero,
        commandRegistry: CommandRegistry = .shared,
        settings: BellithSettings = .shared
    ) {
        self.commandRegistry = commandRegistry
        self.settings = settings
        super.init(frame: frameRect)
        setupViews()
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshTheme() }
    }

    deinit {
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func refreshTheme() {
        backdrop.layer?.backgroundColor = Theme.chromePanel.cgColor
        borderLayer?.borderColor = Theme.chromeHairline.cgColor
        iconView.contentTintColor = Theme.textSecondary
        inputField.textColor = Theme.textPrimary
        inputField.font = BellithFont.mono(14, weight: .regular)
        inputField.placeholderAttributedString = NSAttributedString(
            string: "[COMMAND]",
            attributes: [
                .foregroundColor: Theme.textTertiary,
                .font: BellithFont.mono(14, weight: .regular),
            ]
        )
        separatorLine.layer?.backgroundColor = Theme.chromeHairline.cgColor
        escKbd.refreshTheme()
        backdrop.appearance = Theme.overlayAppearance
        footerLineLayer.backgroundColor = Theme.chromeHairline.cgColor
        footerNavHint.refreshTheme()
        footerRunHint.refreshTheme()
        footerEscHint.refreshTheme()
        resultRows.forEach { $0.refreshTheme() }
    }

    private func setupViews() {
        wantsLayer = true
        alphaValue = 0

        // Accessibility
        setAccessibilityRole(.group)
        setAccessibilityLabel("Command Palette")

        shadow = nil
        layer?.shadowOpacity = 0
        layer?.cornerRadius = Theme.radiusPanel

        // Flatter backdrop
        backdrop.material = .menu
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Theme.radiusPanel
        backdrop.layer?.masksToBounds = true
        backdrop.layer?.backgroundColor = Theme.chromePanel.cgColor
        backdrop.appearance = Theme.overlayAppearance
        addSubview(backdrop)

        let border = CALayer()
        border.borderColor = Theme.chromeHairline.cgColor
        border.borderWidth = 1.0
        border.cornerRadius = Theme.radiusPanel
        backdrop.layer?.addSublayer(border)
        self.borderLayer = border

        // Search icon
        iconView.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        iconView.contentTintColor = Theme.textSecondary
        iconView.setFrameSize(NSSize(width: 18, height: 18))
        addSubview(iconView)

        // Input field
        inputField.isBezeled = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.font = BellithFont.mono(14, weight: .regular)
        inputField.textColor = Theme.textPrimary
        inputField.placeholderAttributedString = NSAttributedString(
            string: "[COMMAND]",
            attributes: [
                .foregroundColor: Theme.textTertiary,
                .font: BellithFont.mono(14, weight: .regular),
            ]
        )
        inputField.cell?.sendsActionOnEndEditing = false
        inputField.target = self
        inputField.action = #selector(handleSubmit)
        inputField.delegate = self
        addSubview(inputField)

        // Separator between input and results
        separatorLine.wantsLayer = true
        separatorLine.layer?.backgroundColor = Theme.chromeHairline.cgColor
        addSubview(separatorLine)

        // Esc kbd chip — shared component, consistent with footer/cheat sheet/search.
        addSubview(escKbd)

        // Results container
        resultsContainer.wantsLayer = true
        resultsContainer.alphaValue = 0
        addSubview(resultsContainer)

        // PR Popover v2 footer keymap (only visible when results are showing).
        footerContainer.wantsLayer = true
        footerContainer.alphaValue = 0
        footerContainer.layer?.addSublayer(footerLineLayer)
        footerContainer.addSubview(footerNavHint)
        footerContainer.addSubview(footerRunHint)
        footerContainer.addSubview(footerEscHint)
        addSubview(footerContainer)
    }

    private let inputHeight: CGFloat = 44
    private let rowHeight: CGFloat = 40
    private let maxVisibleResults = 8

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        borderLayer?.frame = bounds

        let iconX: CGFloat = 14
        iconView.frame = NSRect(x: iconX, y: bounds.height - inputHeight + (inputHeight - 18) / 2, width: 18, height: 18)

        // Esc kbd chip — positioned at right edge of input bar
        let escSize = escKbd.intrinsicContentSize
        let escX = bounds.width - escSize.width - 14
        let escY = bounds.height - inputHeight + (inputHeight - escSize.height) / 2
        escKbd.frame = NSRect(x: escX, y: escY, width: escSize.width, height: escSize.height)

        let inputX = iconX + 26
        inputField.frame = NSRect(
            x: inputX,
            y: bounds.height - inputHeight + (inputHeight - 22) / 2,
            width: escX - inputX - 8,
            height: 22
        )

        // Separator line between input and results
        let separatorY = bounds.height - inputHeight
        separatorLine.frame = NSRect(x: 14, y: separatorY, width: bounds.width - 28, height: 0.5)

        // Footer keymap (when results visible, occupies bottom 28pt).
        let footerVisible = isShowingResults
        let footerSpace = footerVisible ? footerHeight : 0
        let resultsH = max(0, bounds.height - inputHeight - footerSpace)
        resultsContainer.frame = NSRect(x: 0, y: footerSpace, width: bounds.width, height: resultsH)

        // Layout result rows from top of resultsContainer
        var y = resultsH
        for row in resultRows {
            y -= rowHeight
            row.frame = NSRect(x: 8, y: y, width: bounds.width - 16, height: rowHeight)
        }

        // Footer keymap layout
        footerContainer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: footerSpace)
        footerLineLayer.frame = NSRect(x: 12, y: footerSpace - 0.5, width: bounds.width - 24, height: 0.5)

        let navW = ceil(footerNavHint.intrinsicContentSize.width)
        let runW = ceil(footerRunHint.intrinsicContentSize.width)
        let escW = ceil(footerEscHint.intrinsicContentSize.width)
        let footY = max(0, (footerSpace - 16) / 2)
        footerNavHint.frame = NSRect(x: 14, y: footY, width: navW, height: 16)
        footerRunHint.frame = NSRect(x: 14 + navW + 14, y: footY, width: runW, height: 16)
        footerEscHint.frame = NSRect(x: bounds.width - escW - 14, y: footY, width: escW, height: 16)
    }

    // MARK: - Results

    /// Fuzzy match score — returns nil if no match, higher score = better match
    static func fuzzyScore(query: String, target: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let queryChars = Array(query.lowercased())
        let targetChars = Array(target.lowercased())
        var qi = 0
        var score = 0
        var lastMatchIndex = -1

        for (ti, tc) in targetChars.enumerated() {
            if qi < queryChars.count && tc == queryChars[qi] {
                score += 10
                // Bonus for consecutive matches
                if ti == lastMatchIndex + 1 { score += 5 }
                // Bonus for matching at word start
                if ti == 0 || targetChars[ti - 1] == " " { score += 8 }
                lastMatchIndex = ti
                qi += 1
            }
        }
        return qi == queryChars.count ? score : nil
    }

    /// Shared filtering logic — returns commands ranked by fuzzy relevance.
    static func filteredCommands(for query: String, limit: Int, commands: [CommandItem]? = nil) -> [CommandItem] {
        let sourceCommands = commands ?? Self.commands()
        if query.isEmpty {
            return Array(sourceCommands.prefix(limit))
        }
        var scored: [(cmd: CommandItem, score: Int)] = []
        for cmd in sourceCommands {
            if let labelScore = fuzzyScore(query: query, target: cmd.label) {
                scored.append((cmd, labelScore + 10)) // Boost label matches
            } else if let idScore = fuzzyScore(query: query, target: cmd.id) {
                scored.append((cmd, idScore))
            } else if let shortcutId = cmd.shortcutId,
                      let shortcutText = BellithSettings.shared.shortcutSummary(for: shortcutId),
                      let shortcutScore = fuzzyScore(query: query, target: shortcutText) {
                scored.append((cmd, shortcutScore))
            }
        }
        return scored.sorted { $0.score > $1.score }.map { $0.cmd }
    }

    private func updateResults(for query: String) {
        let filtered = Self.filteredCommands(
            for: query,
            limit: maxVisibleResults,
            commands: Self.commands(using: commandRegistry)
        )

        // Remove old rows
        resultRows.forEach { $0.removeFromSuperview() }
        resultRows.removeAll()
        selectedResultIndex = filtered.isEmpty ? -1 : 0

        for (i, cmd) in filtered.prefix(maxVisibleResults).enumerated() {
            let shortcutStr = cmd.shortcutId.flatMap { settings.shortcutSummary(for: $0) }

            let row = CommandRow(
                label: cmd.label,
                description: cmd.description,
                icon: cmd.icon,
                query: query,
                isSelected: i == selectedResultIndex,
                shortcut: shortcutStr
            )
            row.onSelect = { [weak self] in
                self?.executeCommand(cmd.id)
            }
            row.alphaValue = 0
            resultsContainer.addSubview(row)
            resultRows.append(row)
        }

        // Stagger row entry
        for (i, row) in resultRows.enumerated() {
            let delay = Double(i) * 0.02
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = Theme.animFast
                    row.animator().alphaValue = 1
                }
            }
        }

        // Animate height change. Footer joins the panel only when there are
        // results to navigate — empty input shows just the prompt.
        let showResults = !resultRows.isEmpty
        let footerSpace: CGFloat = showResults ? footerHeight : 0
        let targetH = inputHeight + CGFloat(resultRows.count) * rowHeight + (resultRows.isEmpty ? 0 : 8) + footerSpace

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true

            var f = self.frame
            let dy = f.height - targetH
            f.origin.y += dy
            f.size.height = targetH
            self.animator().frame = f
            self.resultsContainer.animator().alphaValue = showResults ? 1 : 0
            self.footerContainer.animator().alphaValue = showResults ? 1 : 0
        }

        isShowingResults = showResults
        needsLayout = true
    }

    private func updateSelection() {
        for (i, row) in resultRows.enumerated() {
            row.setSelected(i == selectedResultIndex)
        }
    }

    private func executeCommand(_ id: String) {
        onSubmit?(id)
        hide()
    }

    // MARK: - Show / Hide

    func show(in parent: NSView) {
        let width: CGFloat = min(560, parent.bounds.width - 100)
        let x = (parent.bounds.width - width) / 2
        let y = parent.bounds.height - inputHeight - 50

        frame = NSRect(x: x, y: y + 8, width: width, height: inputHeight)
        parent.addSubview(self)
        inputField.stringValue = ""

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animMedium
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
            self.animator().frame = NSRect(x: x, y: y, width: width, height: inputHeight)
            self.animator().alphaValue = 1
        } completionHandler: {
            self.window?.makeFirstResponder(self.inputField)
            // Show all commands initially
            self.updateResults(for: "")
        }
    }

    func hide() {
        let targetFrame = NSRect(x: frame.origin.x, y: frame.maxY, width: frame.width, height: inputHeight)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().frame = targetFrame
            self.animator().alphaValue = 0
        } completionHandler: {
            self.resultRows.forEach { $0.removeFromSuperview() }
            self.resultRows.removeAll()
            self.isShowingResults = false
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }

    // MARK: - Actions

    @objc private func handleSubmit() {
        if selectedResultIndex >= 0 && selectedResultIndex < resultRows.count {
            let filtered = Self.filteredCommands(for: inputField.stringValue, limit: maxVisibleResults)
            if selectedResultIndex < filtered.count {
                executeCommand(filtered[selectedResultIndex].id)
                return
            }
        }

        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { hide(); return }
        onSubmit?(text)
        hide()
    }
}

// MARK: - NSTextFieldDelegate

extension CommandPaletteView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            if selectedResultIndex > 0 {
                selectedResultIndex -= 1
                updateSelection()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            if selectedResultIndex < resultRows.count - 1 {
                selectedResultIndex += 1
                updateSelection()
            }
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        updateResults(for: inputField.stringValue)
    }
}

// MARK: - Command Row

private final class CommandRow: NSView {
    var onSelect: (() -> Void)?
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")
    private let descField = NSTextField(labelWithString: "")
    private let shortcutField = NSTextField(labelWithString: "")
    private let accentBar = CALayer()
    private let labelText: String
    private let queryText: String
    private var isSelected = false
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(label: String, description: String, icon: String, query: String, isSelected: Bool, shortcut: String? = nil) {
        self.labelText = label
        self.queryText = query
        self.isSelected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        // Left accent bar (visible only when selected)
        accentBar.backgroundColor = Theme.accent.withAlphaComponent(0.6).cgColor
        accentBar.cornerRadius = 1.5
        accentBar.isHidden = !isSelected
        layer?.addSublayer(accentBar)

        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: label)
        iconView.contentTintColor = isSelected ? Theme.accent : Theme.textSecondary
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        labelField.font = BellithFont.ui(13, weight: .medium)
        labelField.textColor = Theme.textPrimary
        labelField.lineBreakMode = .byTruncatingTail
        applyLabelText()
        addSubview(labelField)

        descField.stringValue = description
        descField.font = BellithFont.mono(10, weight: .regular)
        descField.textColor = Theme.textSecondary
        descField.lineBreakMode = .byTruncatingTail
        addSubview(descField)

        // Keyboard shortcut display
        if let shortcut {
            shortcutField.stringValue = shortcut
            shortcutField.font = BellithFont.mono(10, weight: .regular)
            shortcutField.textColor = Theme.textSecondary
            shortcutField.alignment = .right
            shortcutField.isEditable = false
            shortcutField.isBezeled = false
            shortcutField.drawsBackground = false
            addSubview(shortcutField)
        }

        updateAppearance()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        Theme.animate { _ in
            self.iconView.animator().contentTintColor = selected ? Theme.textPrimary : Theme.textSecondary
            self.layer?.backgroundColor = selected ? Theme.chromeElevated.withAlphaComponent(0.65).cgColor : NSColor.clear.cgColor
        }
        accentBar.isHidden = !selected
    }

    func refreshTheme() {
        accentBar.backgroundColor = Theme.accent.withAlphaComponent(0.45).cgColor
        applyLabelText()
        descField.textColor = Theme.textSecondary
        shortcutField.textColor = Theme.textSecondary
        iconView.contentTintColor = isSelected ? Theme.textPrimary : Theme.textSecondary
        updateAppearance()
    }

    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = Theme.chromeElevated.withAlphaComponent(0.65).cgColor
        } else if isHovered {
            layer?.backgroundColor = Theme.chrome.withAlphaComponent(0.5).cgColor
        } else {
            layer?.backgroundColor = .clear
        }
    }

    private func applyLabelText() {
        if !queryText.isEmpty, let range = labelText.lowercased().range(of: queryText.lowercased()) {
            let attr = NSMutableAttributedString(string: labelText, attributes: [
                .font: BellithFont.ui(13, weight: .medium),
                .foregroundColor: Theme.textPrimary,
            ])
            let nsRange = NSRange(range, in: labelText)
            attr.addAttributes([
                .foregroundColor: Theme.textDisplay,
                .font: BellithFont.ui(13, weight: .medium),
            ], range: nsRange)
            labelField.attributedStringValue = attr
        } else {
            labelField.attributedStringValue = NSAttributedString(
                string: labelText,
                attributes: [
                    .font: BellithFont.ui(13, weight: .medium),
                    .foregroundColor: Theme.textPrimary,
                ]
            )
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let shortcutW: CGFloat = shortcutField.superview != nil ? 80 : 0
        accentBar.frame = NSRect(x: 3, y: (h - 14) / 2, width: 3, height: 14)
        iconView.frame = NSRect(x: 10, y: (h - 16) / 2, width: 16, height: 16)
        labelField.frame = NSRect(x: 34, y: h - 22, width: bounds.width - 44 - shortcutW, height: 16)
        descField.frame = NSRect(x: 34, y: 4, width: bounds.width - 44 - shortcutW, height: 14)
        if shortcutField.superview != nil {
            shortcutField.frame = NSRect(x: bounds.width - shortcutW - 10, y: (h - 14) / 2, width: shortcutW, height: 14)
        }
    }

    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; updateAppearance() }
    override func mouseExited(with event: NSEvent) { isHovered = false; updateAppearance() }
    override func mouseDown(with event: NSEvent) { onSelect?() }
}
