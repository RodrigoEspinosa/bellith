import AppKit
import QuartzCore

/// Mono-font key cap matching the PR Popover v2 design's `<kbd>` footer keys.
/// Used wherever the chrome surfaces a hint like `↑↓`, `⏎`, `esc`, `⌘K`.
final class KbdView: NSView {
    private let label = NSTextField(labelWithString: "")

    var text: String = "" {
        didSet {
            label.stringValue = text
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    init(text: String = "") {
        super.init(frame: .zero)
        self.text = text
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.masksToBounds = false

        label.font = BellithFont.mono(10, weight: .regular)
        label.alignment = .center
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.stringValue = text
        addSubview(label)

        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let textWidth = ceil(label.attributedStringValue.size().width)
        return NSSize(width: max(14, textWidth + 10), height: 16)
    }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 4, dy: 0)
    }

    func refreshTheme() {
        let isLight = Theme.colors.isLight
        layer?.backgroundColor = (isLight
            ? NSColor.white.withAlphaComponent(0.45)
            : NSColor(white: 1, alpha: 0.06)).cgColor
        layer?.borderColor = Theme.chromeHairline.withAlphaComponent(isLight ? 0.7 : 0.55).cgColor
        // Inset bottom shadow line — design has `box-shadow: inset 0 -1px 0 oklch(0.15);`
        // CALayer can't natively render inset shadows, so we approximate with a
        // sublayer at the bottom edge.
        ensureBottomInset()
        label.textColor = Theme.textSecondary
    }

    private static let bottomInsetKey = "kbd.bottomInset"

    private func ensureBottomInset() {
        guard let layer = layer else { return }
        let insetLayer = layer.sublayers?.first(where: { $0.name == Self.bottomInsetKey }) ?? CALayer()
        insetLayer.name = Self.bottomInsetKey
        insetLayer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        insetLayer.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        if insetLayer.superlayer == nil { layer.addSublayer(insetLayer) }
    }
}

/// Horizontal key + label pair: `[↑↓] navigate`. Matches `.pop-foot .kg`.
final class KbdHintView: NSView {
    private let kbd = KbdView()
    private let label = NSTextField(labelWithString: "")
    private let gap: CGFloat = 5

    init(key: String, hint: String) {
        super.init(frame: .zero)
        wantsLayer = true
        kbd.text = key
        addSubview(kbd)

        label.stringValue = hint
        label.font = BellithFont.mono(10.5, weight: .regular)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 1
        addSubview(label)

        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let kbdSize = kbd.intrinsicContentSize
        let labelWidth = ceil(label.attributedStringValue.size().width)
        return NSSize(width: kbdSize.width + gap + labelWidth, height: 16)
    }

    override func layout() {
        super.layout()
        let kbdSize = kbd.intrinsicContentSize
        kbd.frame = NSRect(
            x: 0,
            y: floor((bounds.height - kbdSize.height) / 2),
            width: kbdSize.width,
            height: kbdSize.height
        )
        label.frame = NSRect(
            x: kbdSize.width + gap,
            y: floor((bounds.height - 14) / 2),
            width: max(0, bounds.width - kbdSize.width - gap),
            height: 14
        )
    }

    func refreshTheme() {
        kbd.refreshTheme()
        label.textColor = Theme.textTertiary
    }
}
