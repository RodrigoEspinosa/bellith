import AppKit

final class CommandFailureSuggestionView: NSView {
    private enum Metrics {
        static let width: CGFloat = 360
        static let minHeight: CGFloat = 176
        static let padding: CGFloat = 14
        static let buttonHeight: CGFloat = 28
        static let commandBlockHeight: CGFloat = 44
    }

    private let blurView = BlurView(material: .hudWindow, radius: 16)
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let explanationLabel = NSTextField(wrappingLabelWithString: "")
    private let commandCaptionLabel = NSTextField(labelWithString: "SUGGESTED FIX")
    private let commandPlate = NSView()
    private let commandLabel = NSTextField(labelWithString: "")
    private let insertButton = NSButton()
    private let dismissButton = NSButton()

    var onInsertFix: (() -> Void)?
    var onDismiss: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 22
        layer?.shadowOffset = CGSize(width: 0, height: -8)

        addSubview(blurView)

        iconView.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        iconView.imageScaling = .scaleProportionallyDown
        blurView.addSubview(iconView)

        titleLabel.font = BellithFont.ui(13, weight: .semibold)
        blurView.addSubview(titleLabel)

        explanationLabel.font = BellithFont.ui(12, weight: .regular)
        explanationLabel.maximumNumberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        blurView.addSubview(explanationLabel)

        commandCaptionLabel.font = BellithFont.mono(10, weight: .semibold)
        blurView.addSubview(commandCaptionLabel)

        commandPlate.wantsLayer = true
        commandPlate.layer?.cornerRadius = 10
        commandPlate.layer?.borderWidth = 0.5
        blurView.addSubview(commandPlate)

        commandLabel.font = BellithFont.mono(12, weight: .regular)
        commandLabel.lineBreakMode = .byTruncatingMiddle
        commandPlate.addSubview(commandLabel)

        configureButton(insertButton, title: "Insert Fix", action: #selector(handleInsertFix))
        configureButton(dismissButton, title: "Dismiss", action: #selector(handleDismiss))
        blurView.addSubview(insertButton)
        blurView.addSubview(dismissButton)

        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(with suggestion: CommandFailureSuggestion) {
        titleLabel.stringValue = suggestion.title
        explanationLabel.stringValue = suggestion.explanation
        commandLabel.stringValue = suggestion.fixCommand
        toolTip = suggestion.matchedLine
        needsLayout = true
    }

    func preferredHeight(for width: CGFloat = Metrics.width) -> CGFloat {
        let innerWidth = width - Metrics.padding * 2
        let explanationWidth = innerWidth
        let explanationHeight = textHeight(
            for: explanationLabel.attributedStringValue,
            width: explanationWidth
        )

        let totalHeight = Metrics.padding
            + 18
            + 8
            + explanationHeight
            + 10
            + 14
            + 6
            + Metrics.commandBlockHeight
            + 12
            + Metrics.buttonHeight
            + Metrics.padding
        return max(Metrics.minHeight, ceil(totalHeight))
    }

    override func layout() {
        super.layout()
        blurView.frame = bounds

        let pad = Metrics.padding
        let innerWidth = bounds.width - pad * 2

        iconView.frame = NSRect(x: pad, y: bounds.height - pad - 18, width: 16, height: 16)
        titleLabel.frame = NSRect(x: pad + 24, y: bounds.height - pad - 19, width: innerWidth - 24, height: 18)

        let explanationHeight = textHeight(
            for: explanationLabel.attributedStringValue,
            width: innerWidth
        )
        let explanationY = titleLabel.frame.minY - 8 - explanationHeight
        explanationLabel.frame = NSRect(x: pad, y: explanationY, width: innerWidth, height: explanationHeight)

        commandCaptionLabel.frame = NSRect(x: pad, y: explanationLabel.frame.minY - 22, width: innerWidth, height: 14)
        commandPlate.frame = NSRect(x: pad, y: commandCaptionLabel.frame.minY - 6 - Metrics.commandBlockHeight, width: innerWidth, height: Metrics.commandBlockHeight)
        commandLabel.frame = NSRect(x: 12, y: 12, width: commandPlate.bounds.width - 24, height: 18)

        let buttonWidth = (innerWidth - 8) / 2
        dismissButton.frame = NSRect(x: pad, y: pad, width: buttonWidth, height: Metrics.buttonHeight)
        insertButton.frame = NSRect(x: dismissButton.frame.maxX + 8, y: pad, width: buttonWidth, height: Metrics.buttonHeight)
    }

    func refreshTheme() {
        layer?.shadowColor = Theme.warning.withAlphaComponent(0.14).cgColor
        iconView.contentTintColor = Theme.warning
        titleLabel.textColor = Theme.textPrimary
        explanationLabel.textColor = Theme.textSecondary
        commandCaptionLabel.textColor = Theme.textMuted
        commandPlate.layer?.backgroundColor = Theme.chromePanel.withAlphaComponent(0.92).cgColor
        commandPlate.layer?.borderColor = Theme.warning.withAlphaComponent(0.18).cgColor
        commandLabel.textColor = Theme.warning
        refreshButtonTheme(insertButton, fillColor: Theme.warning.withAlphaComponent(0.22), textColor: Theme.warning)
        refreshButtonTheme(dismissButton, fillColor: Theme.overlay, textColor: Theme.textSecondary)
    }

    private func configureButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.target = self
        button.action = action
        button.isBordered = false
        button.bezelStyle = .rounded
        button.font = BellithFont.ui(12, weight: .medium)
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.masksToBounds = true
    }

    private func refreshButtonTheme(_ button: NSButton, fillColor: NSColor, textColor: NSColor) {
        button.layer?.backgroundColor = fillColor.cgColor
        button.contentTintColor = textColor
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: BellithFont.ui(12, weight: .medium),
        ]
        button.attributedTitle = NSAttributedString(string: button.title, attributes: attributes)
    }

    private func textHeight(for attributedString: NSAttributedString, width: CGFloat) -> CGFloat {
        let rect = attributedString.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return max(18, ceil(rect.height))
    }

    @objc private func handleInsertFix() {
        onInsertFix?()
    }

    @objc private func handleDismiss() {
        onDismiss?()
    }
}
