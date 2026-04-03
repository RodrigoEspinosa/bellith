import AppKit

/// Zen-style command palette overlay.
/// Frosted dark glass panel centered near the top of the window.
final class CommandPaletteView: NSView {
    private let backdrop = NSVisualEffectView()
    private let inputField = NSTextField()
    private let iconView = NSImageView()

    var onSubmit: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true
        alphaValue = 0

        // Shadow for depth
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.shadowRadius = 20
        layer?.shadowOpacity = 1
        layer?.cornerRadius = Theme.radiusPanel

        // Frosted backdrop — blurs content within the window
        backdrop.material = .sidebar
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Theme.radiusPanel
        backdrop.layer?.masksToBounds = true
        backdrop.appearance = NSAppearance(named: .darkAqua)
        addSubview(backdrop)

        // Subtle border
        let borderLayer = CALayer()
        borderLayer.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        borderLayer.borderWidth = 0.5
        borderLayer.cornerRadius = Theme.radiusPanel
        backdrop.layer?.addSublayer(borderLayer)
        // Store for layout
        self.borderLayer = borderLayer

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
            string: "Ask AI or type a command...",
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
    }

    private var borderLayer: CALayer?

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        borderLayer?.frame = bounds

        let iconX: CGFloat = 14
        iconView.frame = NSRect(x: iconX, y: (bounds.height - 18) / 2, width: 18, height: 18)

        let inputX = iconX + 26
        inputField.frame = NSRect(
            x: inputX,
            y: (bounds.height - 22) / 2,
            width: bounds.width - inputX - 14,
            height: 22
        )
    }

    // MARK: - Show / Hide

    func show(in parent: NSView) {
        let width: CGFloat = min(520, parent.bounds.width - 100)
        let height: CGFloat = 44
        let x = (parent.bounds.width - width) / 2
        let y = parent.bounds.height - height - 50

        frame = NSRect(x: x, y: y, width: width, height: height)

        // Start slightly above final position for slide-down effect
        let startFrame = frame.offsetBy(dx: 0, dy: 8)
        self.frame = startFrame
        parent.addSubview(self)

        inputField.stringValue = ""

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animMedium
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().frame = NSRect(x: x, y: y, width: width, height: height)
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
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            hide()
            return
        }
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
        return false
    }
}
