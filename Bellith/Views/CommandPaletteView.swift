import AppKit

/// Zen-style command palette overlay with autocomplete.
/// Frosted dark glass panel centered near the top of the window.
final class CommandPaletteView: NSView {
    private let backdrop = NSVisualEffectView()
    private let inputField = NSTextField()
    private let iconView = NSImageView()
    private let separatorLine = NSView()
    private let escHint = NSTextField(labelWithString: "esc")
    private let escHintPill = NSView()
    private var borderLayer: CALayer?

    // Results list
    private let resultsContainer = NSView()
    private var resultRows: [CommandRow] = []
    private var selectedResultIndex: Int = -1
    private var isShowingResults = false

    var onSubmit: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    /// Available commands for autocomplete
    static let commands: [(id: String, label: String, description: String, icon: String, shortcutId: String?)] = [
        ("newTab", "New Tab", "Open a new terminal tab", "plus.square", "newTab"),
        ("closeTab", "Close Tab", "Close the current tab", "xmark.square", "closeTab"),
        ("reopenTab", "Reopen Closed Tab", "Restore last closed tab", "arrow.uturn.left", "reopenTab"),
        ("splitRight", "Split Right", "Split pane to the right", "rectangle.split.1x2", "splitRight"),
        ("splitDown", "Split Down", "Split pane downward", "rectangle.split.2x1", "splitDown"),
        ("closePane", "Close Pane", "Close the current pane", "xmark.rectangle", "closePane"),
        ("zoomPane", "Zoom Pane", "Toggle pane zoom", "arrow.up.left.and.arrow.down.right", "zoomPane"),
        ("equalizePanes", "Equalize Panes", "Reset all pane sizes", "equal.square", "equalizePanes"),
        ("navLeft", "Focus Left Pane", "Move focus left", "arrow.left.square", "navLeft"),
        ("navRight", "Focus Right Pane", "Move focus right", "arrow.right.square", "navRight"),
        ("navUp", "Focus Up Pane", "Move focus up", "arrow.up.square", "navUp"),
        ("navDown", "Focus Down Pane", "Move focus down", "arrow.down.square", "navDown"),
        ("toggleSidebar", "Toggle Sidebar", "Show or hide the sidebar", "sidebar.left", "toggleSidebar"),
        ("toggleBroadcast", "Broadcast Mode", "Send input to all panes", "antenna.radiowaves.left.and.right", "broadcastInput"),
        ("showHUD", "Show HUD", "Display terminal info overlay", "info.circle", "showHUD"),
        ("find", "Find", "Search in terminal", "magnifyingglass", "search"),
        ("preferences", "Settings", "Open preferences window", "gear", nil),
        ("reloadConfig", "Reload Config", "Reload terminal configuration", "arrow.clockwise", "reloadConfig"),
        ("increaseFontSize", "Increase Font Size", "Make text larger", "textformat.size.larger", "fontSizeUp"),
        ("decreaseFontSize", "Decrease Font Size", "Make text smaller", "textformat.size.smaller", "fontSizeDown"),
        ("resetFontSize", "Reset Font Size", "Reset to default size", "textformat.size", "fontSizeReset"),
        ("clearBuffer", "Clear Buffer", "Clear terminal output", "trash", "clearBuffer"),
        ("processTree", "Process Tree", "Inspect running processes", "list.bullet.indent", nil),
        ("network", "Network", "View network connections", "network", nil),
        ("environment", "Environment", "View environment variables", "text.alignleft", nil),
        ("fileActivity", "File Activity", "View open files", "doc.text.magnifyingglass", nil),
        ("performance", "Performance", "View resource usage", "chart.xyaxis.line", nil),
        ("fullscreen", "Toggle Fullscreen", "Enter or exit fullscreen", "arrow.up.backward.and.arrow.down.forward", "toggleFullscreen"),
        ("copySelection", "Copy", "Copy selected text", "doc.on.doc", "copy"),
        ("pasteClipboard", "Paste", "Paste from clipboard", "doc.on.clipboard", "paste"),
        ("newWindow", "New Window", "Open a new window", "macwindow.badge.plus", "newWindow"),
        ("selectAll", "Select All", "Select all text", "selection.pin.in.out", "selectAll"),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true
        alphaValue = 0

        // Accessibility
        setAccessibilityRole(.group)
        setAccessibilityLabel("Command Palette")

        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.shadowRadius = 20
        layer?.shadowOpacity = 1
        layer?.cornerRadius = Theme.radiusPanel

        // Frosted backdrop
        backdrop.material = .sidebar
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Theme.radiusPanel
        backdrop.layer?.masksToBounds = true
        backdrop.appearance = NSAppearance(named: .darkAqua)
        addSubview(backdrop)

        let border = CALayer()
        border.borderColor = Theme.border.cgColor
        border.borderWidth = 0.5
        border.cornerRadius = Theme.radiusPanel
        backdrop.layer?.addSublayer(border)
        self.borderLayer = border

        // Search icon
        iconView.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)
        iconView.contentTintColor = Theme.accent
        iconView.setFrameSize(NSSize(width: 18, height: 18))
        addSubview(iconView)

        // Input field
        inputField.isBezeled = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.font = .systemFont(ofSize: 15, weight: .regular)
        inputField.textColor = Theme.textPrimary
        inputField.placeholderAttributedString = NSAttributedString(
            string: "Type a command\u{2026}",
            attributes: [
                .foregroundColor: Theme.textMuted,
                .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            ]
        )
        inputField.cell?.sendsActionOnEndEditing = false
        inputField.target = self
        inputField.action = #selector(handleSubmit)
        inputField.delegate = self
        addSubview(inputField)

        // Separator between input and results
        separatorLine.wantsLayer = true
        separatorLine.layer?.backgroundColor = Theme.border.cgColor
        addSubview(separatorLine)

        // Esc hint keycap badge
        escHintPill.wantsLayer = true
        escHintPill.layer?.backgroundColor = Theme.overlay.cgColor
        escHintPill.layer?.cornerRadius = 4
        addSubview(escHintPill)

        escHint.font = .systemFont(ofSize: 10, weight: .medium)
        escHint.textColor = Theme.textMuted
        escHint.isBezeled = false
        escHint.drawsBackground = false
        escHint.isEditable = false
        escHint.isSelectable = false
        escHint.sizeToFit()
        addSubview(escHint)

        // Results container
        resultsContainer.wantsLayer = true
        resultsContainer.alphaValue = 0
        addSubview(resultsContainer)
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

        // Esc hint badge — positioned at right edge of input bar
        let hintPadH: CGFloat = 6
        let hintPadV: CGFloat = 2
        let hintW = escHint.intrinsicContentSize.width + hintPadH * 2
        let hintH = escHint.intrinsicContentSize.height + hintPadV * 2
        let hintX = bounds.width - hintW - 14
        let hintY = bounds.height - inputHeight + (inputHeight - hintH) / 2
        escHintPill.frame = NSRect(x: hintX, y: hintY, width: hintW, height: hintH)
        escHint.frame = NSRect(x: hintX + hintPadH, y: hintY + hintPadV, width: escHint.intrinsicContentSize.width, height: escHint.intrinsicContentSize.height)

        let inputX = iconX + 26
        inputField.frame = NSRect(
            x: inputX,
            y: bounds.height - inputHeight + (inputHeight - 22) / 2,
            width: hintX - inputX - 8,
            height: 22
        )

        // Separator line between input and results
        let separatorY = bounds.height - inputHeight
        separatorLine.frame = NSRect(x: 14, y: separatorY, width: bounds.width - 28, height: 0.5)

        // Results below the input area
        let resultsH = bounds.height - inputHeight
        resultsContainer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: resultsH)

        // Layout result rows from top
        var y = resultsH
        for row in resultRows {
            y -= rowHeight
            row.frame = NSRect(x: 8, y: y, width: bounds.width - 16, height: rowHeight)
        }
    }

    // MARK: - Results

    /// Fuzzy match score — returns nil if no match, higher score = better match
    private static func fuzzyScore(query: String, target: String) -> Int? {
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

    private func updateResults(for query: String) {
        let filtered: [(id: String, label: String, description: String, icon: String, shortcutId: String?)]
        if query.isEmpty {
            filtered = Array(Self.commands.prefix(maxVisibleResults))
        } else {
            // Fuzzy search with scoring
            var scored: [(cmd: (id: String, label: String, description: String, icon: String, shortcutId: String?), score: Int)] = []
            for cmd in Self.commands {
                if let labelScore = Self.fuzzyScore(query: query, target: cmd.label) {
                    scored.append((cmd, labelScore + 10)) // Boost label matches
                } else if let idScore = Self.fuzzyScore(query: query, target: cmd.id) {
                    scored.append((cmd, idScore))
                }
            }
            filtered = scored.sorted { $0.score > $1.score }.map { $0.cmd }
        }

        // Remove old rows
        resultRows.forEach { $0.removeFromSuperview() }
        resultRows.removeAll()
        selectedResultIndex = filtered.isEmpty ? -1 : 0

        for (i, cmd) in filtered.prefix(maxVisibleResults).enumerated() {
            // Look up keyboard shortcut
            let shortcutStr: String?
            if let sid = cmd.shortcutId, let shortcut = BellithSettings.shared.shortcut(for: sid) {
                shortcutStr = shortcut.displayString
            } else {
                shortcutStr = nil
            }

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
            resultsContainer.addSubview(row)
            resultRows.append(row)
        }

        // Animate height change
        let targetH = inputHeight + CGFloat(resultRows.count) * rowHeight + (resultRows.isEmpty ? 0 : 8)
        let showResults = !resultRows.isEmpty

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
        let width: CGFloat = min(520, parent.bounds.width - 100)
        let x = (parent.bounds.width - width) / 2
        let y = parent.bounds.height - inputHeight - 50

        frame = NSRect(x: x, y: y + 8, width: width, height: inputHeight)
        parent.addSubview(self)
        inputField.stringValue = ""

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animMedium
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
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
            let query = inputField.stringValue
            let filtered: [(id: String, label: String, description: String, icon: String, shortcutId: String?)]
            if query.isEmpty {
                filtered = Array(Self.commands.prefix(maxVisibleResults))
            } else {
                var scored: [(cmd: (id: String, label: String, description: String, icon: String, shortcutId: String?), score: Int)] = []
                for cmd in Self.commands {
                    if let labelScore = Self.fuzzyScore(query: query, target: cmd.label) {
                        scored.append((cmd, labelScore + 10))
                    } else if let idScore = Self.fuzzyScore(query: query, target: cmd.id) {
                        scored.append((cmd, idScore))
                    }
                }
                filtered = scored.sorted { $0.score > $1.score }.map { $0.cmd }
            }
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
    private var isSelected = false
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(label: String, description: String, icon: String, query: String, isSelected: Bool, shortcut: String? = nil) {
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

        labelField.font = .systemFont(ofSize: 13, weight: .medium)
        labelField.textColor = Theme.textPrimary
        labelField.lineBreakMode = .byTruncatingTail

        // Highlight matching text
        if !query.isEmpty, let range = label.lowercased().range(of: query.lowercased()) {
            let attr = NSMutableAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: Theme.textPrimary,
            ])
            let nsRange = NSRange(range, in: label)
            attr.addAttributes([
                .foregroundColor: Theme.accent,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ], range: nsRange)
            labelField.attributedStringValue = attr
        } else {
            labelField.stringValue = label
        }
        addSubview(labelField)

        descField.stringValue = description
        descField.font = .systemFont(ofSize: 11)
        descField.textColor = Theme.textMuted
        descField.lineBreakMode = .byTruncatingTail
        addSubview(descField)

        // Keyboard shortcut display
        if let shortcut {
            shortcutField.stringValue = shortcut
            shortcutField.font = .systemFont(ofSize: 11, weight: .medium)
            shortcutField.textColor = Theme.textMuted
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
        iconView.contentTintColor = selected ? Theme.accent : Theme.textSecondary
        accentBar.isHidden = !selected
        updateAppearance()
    }

    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = Theme.accent.withAlphaComponent(0.1).cgColor
        } else if isHovered {
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.04).cgColor
        } else {
            layer?.backgroundColor = .clear
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
