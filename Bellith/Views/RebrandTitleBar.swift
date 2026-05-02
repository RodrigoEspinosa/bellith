import AppKit
import QuartzCore

/// Title bar for the rebrand shell. Mirrors the design's `.titlebar`:
/// - 36px tall with a subtle top→bottom gradient and a bottom hairline
/// - Centered title `<bold shell> — <accent workspace>` plus a bordered
///   pane-count chip (`zellij · 3 panes` style) when relevant
/// - Traffic-light gutter at the leading edge (system renders the dots)
final class RebrandTitleBar: NSView {
    private let bgGradient = CAGradientLayer()
    private let bottomLine = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let panePill = RebrandPaneCountPill()

    private let leadingTrafficLightInset: CGFloat = 92

    var workspaceName: String = "session" {
        didSet { rebuildTitle() }
    }
    var workspaceTint: NSColor = RebrandTokens.Color.fg2 {
        didSet { rebuildTitle() }
    }
    var paneCount: Int = 1 {
        didSet { rebuildTitle() }
    }
    var muxLabel: String? {
        didSet { rebuildTitle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(bgGradient)
        layer?.addSublayer(bottomLine)

        titleLabel.font = RebrandTokens.Typography.mono(12.5, weight: .medium)
        titleLabel.alignment = .left
        titleLabel.isEditable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        panePill.isHidden = true
        addSubview(panePill)

        rebuildTitle()
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        bgGradient.frame = bounds
        bottomLine.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)

        // Center-group: title label + pane pill. Measure each segment via
        // NSString.size(withAttributes:) — `attributedStringValue.size()`
        // returns 0 before AppKit has cached the run, which collapses the
        // title to nothing on first paint.
        let titleString = titleLabel.attributedStringValue.string
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleLabel.font ?? RebrandTokens.Typography.mono(12, weight: .medium)]
        let titleW = ceil((titleString as NSString).size(withAttributes: titleAttrs).width)
        let pillSize = panePill.isHidden ? .zero : panePill.intrinsicContentSize
        let pillGap: CGFloat = panePill.isHidden ? 0 : 8
        let groupW = titleW + pillGap + pillSize.width
        var groupX = floor((bounds.width - groupW) / 2)
        let leftLimit = leadingTrafficLightInset + 6
        if groupX < leftLimit { groupX = leftLimit }
        if groupX + groupW > bounds.width - 12 { groupX = max(leftLimit, bounds.width - 12 - groupW) }

        titleLabel.frame = NSRect(
            x: groupX,
            y: floor((bounds.height - 18) / 2),
            width: titleW + 2,
            height: 18
        )
        if !panePill.isHidden {
            panePill.frame = NSRect(
                x: titleLabel.frame.maxX + pillGap,
                y: floor((bounds.height - pillSize.height) / 2),
                width: pillSize.width,
                height: pillSize.height
            )
        }
    }

    func applyTheme() {
        // Dark/light gradient — `linear-gradient(to bottom, oklch(0.22), oklch(0.18))`.
        let top = RebrandTokens.Color.titleBarBg.withAlphaComponent(1)
        let bot = RebrandTokens.Color.windowBg.withAlphaComponent(0.96)
        bgGradient.colors = [top.cgColor, bot.cgColor]
        bgGradient.startPoint = CGPoint(x: 0.5, y: 1)
        bgGradient.endPoint = CGPoint(x: 0.5, y: 0)
        bottomLine.backgroundColor = RebrandTokens.Color.line.cgColor
        rebuildTitle()
        panePill.applyTheme()
    }

    private func rebuildTitle() {
        let primaryFont = RebrandTokens.Typography.mono(12.5, weight: .medium)
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: "zsh",
            attributes: [.font: primaryFont, .foregroundColor: RebrandTokens.Color.fg2]
        ))
        result.append(NSAttributedString(
            string: " — ",
            attributes: [.font: primaryFont, .foregroundColor: RebrandTokens.Color.fg4]
        ))
        result.append(NSAttributedString(
            string: workspaceName,
            attributes: [.font: primaryFont, .foregroundColor: workspaceTint]
        ))
        titleLabel.attributedStringValue = result
        titleLabel.sizeToFit()

        if let muxLabel, paneCount > 0 {
            panePill.text = "\(muxLabel) · \(paneCount) pane\(paneCount == 1 ? "" : "s")"
            panePill.isHidden = false
        } else if paneCount > 1 {
            panePill.text = "\(paneCount) panes"
            panePill.isHidden = false
        } else {
            panePill.isHidden = true
        }
        needsLayout = true
    }
}

/// Bordered chip rendering the active tab's pane/mux info. Mirrors the
/// design's `.title .mux` chip — small mono font, hairline border, 3px corner.
final class RebrandPaneCountPill: NSView {
    private let label = NSTextField(labelWithString: "")

    var text: String = "" {
        didSet {
            label.stringValue = text
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        label.font = RebrandTokens.Typography.mono(10.5, weight: .regular)
        label.alignment = .center
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 1
        addSubview(label)
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: label.font ?? RebrandTokens.Typography.mono(10.5)]
        let textW = ceil((label.stringValue as NSString).size(withAttributes: attrs).width)
        return NSSize(width: textW + 12, height: 16)
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(
            x: 0,
            y: floor((bounds.height - 14) / 2),
            width: bounds.width,
            height: 14
        )
    }

    func applyTheme() {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = RebrandTokens.Color.lineStrong.cgColor
        label.textColor = RebrandTokens.Color.fg4
    }
}
