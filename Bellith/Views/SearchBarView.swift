import AppKit

/// Find-in-buffer search bar overlay, positioned top-right of terminal area.
final class SearchBarView: NSView {
    private let backdrop = NSVisualEffectView()
    private let iconView = NSImageView()
    private let inputField = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let caseSensitiveButton = NSButton()
    private let regexButton = NSButton()
    private var borderLayer: CALayer?
    private let escBadge = NSView()
    private let escLabel = NSTextField(labelWithString: "esc")
    private var themeObserver: NSObjectProtocol?

    var onSearch: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrev: (() -> Void)?
    var onDismiss: (() -> Void)?

    private(set) var isCaseSensitive = false
    private(set) var isRegex = false
    private var searchTotal: Int = 0
    private var searchSelected: Int = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshTheme()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
    }

    private func setupViews() {
        wantsLayer = true
        alphaValue = 0

        // Accessibility
        setAccessibilityRole(.group)
        setAccessibilityLabel("Find in Terminal")

        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.shadowRadius = 10
        layer?.shadowOpacity = 0.8
        layer?.cornerRadius = Theme.radiusPanel

        // Frosted backdrop
        backdrop.material = .sidebar
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Theme.radiusPanel
        backdrop.layer?.masksToBounds = true
        backdrop.appearance = Theme.overlayAppearance
        addSubview(backdrop)

        let border = CALayer()
        border.borderColor = Theme.border.cgColor
        border.borderWidth = 0.5
        border.cornerRadius = Theme.radiusPanel
        backdrop.layer?.addSublayer(border)
        self.borderLayer = border

        // Search icon
        iconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        iconView.contentTintColor = Theme.textMuted
        iconView.setFrameSize(NSSize(width: 16, height: 16))
        addSubview(iconView)

        // Input field
        inputField.isBezeled = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.font = .systemFont(ofSize: 13, weight: .regular)
        inputField.textColor = Theme.textPrimary
        inputField.placeholderAttributedString = NSAttributedString(
            string: "Find...",
            attributes: [
                .foregroundColor: Theme.textMuted,
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            ]
        )
        inputField.cell?.sendsActionOnEndEditing = false
        inputField.target = self
        inputField.action = #selector(handleSubmit)
        inputField.delegate = self
        addSubview(inputField)

        // Count label
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = Theme.textMuted
        countLabel.alignment = .right
        countLabel.isEditable = false
        countLabel.isBezeled = false
        countLabel.drawsBackground = false
        countLabel.wantsLayer = true
        addSubview(countLabel)

        // Toggle buttons
        configureToggleButton(caseSensitiveButton, title: "Aa", action: #selector(handleToggleCase))
        caseSensitiveButton.toolTip = "Case Sensitive"
        addSubview(caseSensitiveButton)

        configureToggleButton(regexButton, title: ".*", action: #selector(handleToggleRegex))
        regexButton.toolTip = "Regular Expression"
        addSubview(regexButton)

        // Nav buttons
        configureNavButton(prevButton, symbolName: "chevron.up", action: #selector(handlePrev))
        configureNavButton(nextButton, symbolName: "chevron.down", action: #selector(handleNext))
        prevButton.toolTip = "Previous Match (Shift+Enter)"
        nextButton.toolTip = "Next Match (Enter)"
        addSubview(prevButton)
        addSubview(nextButton)

        // Esc key hint badge
        escBadge.wantsLayer = true
        escBadge.layer?.cornerRadius = 3
        escBadge.layer?.backgroundColor = Theme.overlay.cgColor
        addSubview(escBadge)

        escLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        escLabel.textColor = Theme.textMuted
        escLabel.isEditable = false
        escLabel.isBezeled = false
        escLabel.drawsBackground = false
        escLabel.alignment = .center
        escBadge.addSubview(escLabel)

        refreshTheme()
    }

    private func configureNavButton(_ button: NSButton, symbolName: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = Theme.textSecondary
        button.target = self
        button.action = action
        button.setFrameSize(NSSize(width: 24, height: 24))
    }

    private func configureToggleButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.font = .systemFont(ofSize: 10, weight: .semibold)
        button.bezelStyle = .inline
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.contentTintColor = Theme.textMuted
        button.target = self
        button.action = action
        button.setFrameSize(NSSize(width: 24, height: 20))
    }

    private func updateToggleAppearance(_ button: NSButton, isActive: Bool) {
        Theme.animate { _ in
            if isActive {
                button.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.2).cgColor
                button.contentTintColor = Theme.accent
            } else {
                button.layer?.backgroundColor = NSColor.clear.cgColor
                button.contentTintColor = Theme.textMuted
            }
        }
    }

    func refreshTheme() {
        borderLayer?.borderColor = Theme.border.cgColor
        backdrop.appearance = Theme.overlayAppearance
        inputField.textColor = Theme.textPrimary
        inputField.placeholderAttributedString = NSAttributedString(
            string: "Find...",
            attributes: [
                .foregroundColor: Theme.textMuted,
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            ]
        )
        prevButton.contentTintColor = Theme.textSecondary
        nextButton.contentTintColor = Theme.textSecondary
        escBadge.layer?.backgroundColor = Theme.overlay.cgColor
        escLabel.textColor = Theme.textMuted
        updateToggleAppearance(caseSensitiveButton, isActive: isCaseSensitive)
        updateToggleAppearance(regexButton, isActive: isRegex)
        updateCount(selected: searchSelected, total: searchTotal)
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        borderLayer?.frame = bounds

        let h = bounds.height
        iconView.frame = NSRect(x: 10, y: (h - 16) / 2, width: 16, height: 16)

        // Esc badge at far right
        escBadge.frame = NSRect(x: bounds.width - 34, y: (h - 16) / 2, width: 28, height: 16)
        escLabel.frame = escBadge.bounds

        let btnY = (h - 24) / 2
        nextButton.frame = NSRect(x: bounds.width - 66, y: btnY, width: 24, height: 24)
        prevButton.frame = NSRect(x: bounds.width - 90, y: btnY, width: 24, height: 24)

        let toggleY = (h - 20) / 2
        regexButton.frame = NSRect(x: bounds.width - 116, y: toggleY, width: 24, height: 20)
        caseSensitiveButton.frame = NSRect(x: bounds.width - 140, y: toggleY, width: 24, height: 20)

        let countW: CGFloat = 64
        countLabel.frame = NSRect(x: bounds.width - 140 - countW - 4, y: (h - 16) / 2, width: countW, height: 16)

        let inputX: CGFloat = 32
        let inputW = bounds.width - inputX - 140 - countW - 12
        inputField.frame = NSRect(x: inputX, y: (h - 20) / 2, width: max(inputW, 40), height: 20)
    }

    // MARK: - Public

    func setQuery(_ text: String) {
        inputField.stringValue = text
    }

    func updateCount(selected: Int, total: Int) {
        searchSelected = selected
        searchTotal = total
        if total > 0 {
            countLabel.stringValue = "\(selected)/\(total)"
            countLabel.textColor = Theme.textSecondary
            countLabel.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.08).cgColor
            countLabel.layer?.cornerRadius = 4
            iconView.contentTintColor = Theme.accent
        } else if !inputField.stringValue.isEmpty {
            countLabel.stringValue = "No results"
            countLabel.textColor = Theme.destructive.withAlphaComponent(0.8)
            countLabel.layer?.backgroundColor = Theme.destructive.withAlphaComponent(0.08).cgColor
            countLabel.layer?.cornerRadius = 4
            iconView.contentTintColor = Theme.destructive.withAlphaComponent(0.6)
        } else {
            countLabel.stringValue = ""
            countLabel.layer?.backgroundColor = NSColor.clear.cgColor
            iconView.contentTintColor = Theme.textMuted
        }
    }

    // MARK: - Show / Hide

    func show(in parent: NSView, rightMargin: CGFloat = 16, topMargin: CGFloat = 50) {
        let width: CGFloat = 380
        let height: CGFloat = 36
        let x = parent.bounds.width - width - rightMargin
        let y = parent.bounds.height - height - topMargin

        frame = NSRect(x: x, y: y + 8, width: width, height: height)
        parent.addSubview(self)
        inputField.stringValue = ""
        countLabel.stringValue = ""

        let finalFrame = NSRect(x: x, y: y, width: width, height: height)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animMedium
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
            self.animator().frame = finalFrame
            self.animator().alphaValue = 1
        } completionHandler: {
            self.window?.makeFirstResponder(self.inputField)
        }
    }

    func hide() {
        let targetFrame = frame.offsetBy(dx: 0, dy: 8)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().frame = targetFrame
            self.animator().alphaValue = 0
        } completionHandler: {
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }

    // MARK: - Actions

    @objc private func handleSubmit() {
        let text = inputField.stringValue
        guard !text.isEmpty else { return }
        onNext?()
    }

    @objc private func handleNext() { onNext?() }
    @objc private func handlePrev() { onPrev?() }
    @objc private func handleToggleCase() {
        isCaseSensitive.toggle()
        updateToggleAppearance(caseSensitiveButton, isActive: isCaseSensitive)
        // Re-trigger search with current query
        let text = inputField.stringValue
        if !text.isEmpty { onSearch?(text) }
    }
    @objc private func handleToggleRegex() {
        isRegex.toggle()
        updateToggleAppearance(regexButton, isActive: isRegex)
        let text = inputField.stringValue
        if !text.isEmpty { onSearch?(text) }
    }
}

// MARK: - NSTextFieldDelegate

extension SearchBarView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let mods = NSApp.currentEvent?.modifierFlags ?? []
            if mods.contains(.shift) {
                onPrev?()
            } else {
                let text = inputField.stringValue
                if !text.isEmpty {
                    onSearch?(text)
                }
            }
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        let text = inputField.stringValue
        if text.isEmpty {
            countLabel.stringValue = ""
        } else {
            onSearch?(text)
        }
    }
}
