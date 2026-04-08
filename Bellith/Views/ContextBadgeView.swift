import AppKit

final class ContextBadgeView: NSView {
    enum Tone {
        case neutral
        case success
        case warning
        case destructive
    }

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    var text: String = "" {
        didSet {
            label.stringValue = text
            isHidden = text.isEmpty
            needsLayout = true
        }
    }

    var iconName: String? {
        didSet {
            if let iconName {
                iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
                iconView.isHidden = false
            } else {
                iconView.image = nil
                iconView.isHidden = true
            }
            needsLayout = true
        }
    }

    var tone: Tone = .neutral {
        didSet { refreshTheme() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5

        label.font = BellithFont.mono(10, weight: .regular)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 1
        addSubview(label)

        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let iconWidth: CGFloat = iconView.isHidden ? 0 : 12
        let gap: CGFloat = iconView.isHidden ? 0 : 5
        let textWidth = label.attributedStringValue.size().width
        return NSSize(width: ceil(textWidth + iconWidth + gap + 18), height: 20)
    }

    override func layout() {
        super.layout()
        let iconWidth: CGFloat = iconView.isHidden ? 0 : 12
        let iconGap: CGFloat = iconView.isHidden ? 0 : 5
        let iconY = floor((bounds.height - 12) / 2)
        iconView.frame = NSRect(x: 8, y: iconY, width: iconWidth, height: 12)
        label.frame = NSRect(
            x: 8 + iconWidth + iconGap,
            y: floor((bounds.height - 12) / 2),
            width: bounds.width - 16 - iconWidth - iconGap,
            height: 12
        )
    }

    func refreshTheme() {
        let palette: (background: NSColor, border: NSColor, foreground: NSColor)
        switch tone {
        case .neutral:
            palette = (
                Theme.surface.withAlphaComponent(0.55),
                Theme.border,
                Theme.textSecondary
            )
        case .success:
            palette = (
                Theme.success.withAlphaComponent(0.14),
                Theme.success.withAlphaComponent(0.35),
                Theme.success
            )
        case .warning:
            palette = (
                Theme.warning.withAlphaComponent(0.14),
                Theme.warning.withAlphaComponent(0.35),
                Theme.warning
            )
        case .destructive:
            palette = (
                Theme.destructive.withAlphaComponent(0.16),
                Theme.destructive.withAlphaComponent(0.38),
                Theme.destructive
            )
        }

        layer?.backgroundColor = palette.background.cgColor
        layer?.borderColor = palette.border.cgColor
        iconView.contentTintColor = palette.foreground
        label.textColor = palette.foreground
    }
}
