import AppKit
import QuartzCore

/// Compact status bar for the rebrand shell. Mirrors the reference's shape,
/// but uses live session projection from `TerminalContainerView` instead of
/// placeholder text.
final class RebrandStatusBar: NSView {
    private let topLine = CALayer()
    private let modePill = RebrandPillLabel(text: "NORMAL", emphasized: true)
    private let muxInfo = NSTextField(labelWithString: "")
    private let centerInfo = NSTextField(labelWithString: "")
    private let trailing = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = RebrandTokens.Color.statusBarBg.cgColor
        layer?.addSublayer(topLine)

        addSubview(modePill)

        muxInfo.stringValue = ""
        configureLabel(muxInfo, color: RebrandTokens.Color.fg3)
        addSubview(muxInfo)

        centerInfo.stringValue = ""
        configureLabel(centerInfo, color: RebrandTokens.Color.fg4)
        centerInfo.alignment = .center
        addSubview(centerInfo)

        trailing.stringValue = "⌘K palette"
        configureLabel(trailing, color: RebrandTokens.Color.fg3)
        trailing.alignment = .right
        addSubview(trailing)

        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func configureLabel(_ field: NSTextField, color: NSColor) {
        field.font = RebrandTokens.Typography.mono(11, weight: .regular)
        field.textColor = color
        field.isEditable = false
        field.isBezeled = false
        field.drawsBackground = false
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
    }

    func configure(_ summary: TerminalContainerView.EmbeddedStatusSummary?) {
        guard let summary else {
            muxInfo.stringValue = ""
            centerInfo.stringValue = ""
            trailing.stringValue = "⌘K palette"
            needsLayout = true
            return
        }

        let mode = summary.isBroadcasting ? "BROADCAST" : "NORMAL"
        modePill.text = mode

        let paneText = summary.paneCount > 1
            ? "pane \(summary.focusedPaneIndex)/\(summary.paneCount)"
            : "pane 1/1"
        muxInfo.stringValue = [summary.muxName, paneText].compactMap { $0 }.joined(separator: "  ")

        var centerParts: [String] = []
        if let cwd = summary.cwdDisplay { centerParts.append(cwd) }
        if let branch = summary.gitBranch { centerParts.append(branch) }
        if let process = summary.processDisplay { centerParts.append(process) }
        centerInfo.stringValue = centerParts.joined(separator: "  ·  ")

        var trailingParts: [String] = []
        if summary.paneCount > 1 { trailingParts.append("⌃a prefix") }
        trailingParts.append("⌘K palette")
        trailing.stringValue = trailingParts.joined(separator: "  ·  ")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        topLine.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)

        let padX: CGFloat = 12
        let pillSize = modePill.intrinsicContentSize
        modePill.frame = NSRect(
            x: padX,
            y: floor((bounds.height - pillSize.height) / 2),
            width: pillSize.width,
            height: pillSize.height
        )

        let muxX = modePill.frame.maxX + 10
        let muxAttrs: [NSAttributedString.Key: Any] = [.font: muxInfo.font ?? RebrandTokens.Typography.mono(11)]
        let muxW = muxInfo.stringValue.isEmpty ? 0 : ceil((muxInfo.stringValue as NSString).size(withAttributes: muxAttrs).width)
        muxInfo.frame = NSRect(
            x: muxX,
            y: floor((bounds.height - 14) / 2),
            width: muxW == 0 ? 0 : muxW + 4,
            height: 14
        )

        let trailAttrs: [NSAttributedString.Key: Any] = [.font: trailing.font ?? RebrandTokens.Typography.mono(11)]
        let trailW = ceil((trailing.stringValue as NSString).size(withAttributes: trailAttrs).width) + 4
        trailing.frame = NSRect(
            x: bounds.width - padX - trailW,
            y: floor((bounds.height - 14) / 2),
            width: trailW,
            height: 14
        )

        let centerLeft = muxInfo.frame.maxX + 12
        let centerRight = trailing.frame.minX - 12
        centerInfo.frame = NSRect(
            x: centerLeft,
            y: floor((bounds.height - 14) / 2),
            width: max(0, centerRight - centerLeft),
            height: 14
        )
    }

    func applyTheme() {
        layer?.backgroundColor = RebrandTokens.Color.statusBarBg.cgColor
        topLine.backgroundColor = RebrandTokens.Color.line.cgColor
        modePill.applyTheme()
        muxInfo.textColor = RebrandTokens.Color.fg3
        centerInfo.textColor = RebrandTokens.Color.fg4
        trailing.textColor = RebrandTokens.Color.fg3
    }
}

/// Small pill rendering a status bar mode (`NORMAL`, `INSERT`, …) or a mux tag.
final class RebrandPillLabel: NSView {
    private let label = NSTextField(labelWithString: "")
    private let emphasized: Bool

    var text: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    init(text: String, emphasized: Bool = false) {
        self.emphasized = emphasized
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.cornerCurve = .continuous

        label.stringValue = text
        label.font = RebrandTokens.Typography.mono(10, weight: emphasized ? .semibold : .regular)
        label.alignment = .center
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        addSubview(label)

        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: label.font ?? RebrandTokens.Typography.mono(10)]
        let w = ceil((label.stringValue as NSString).size(withAttributes: attrs).width)
        return NSSize(width: w + 12, height: 18)
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: floor((bounds.height - 14) / 2), width: bounds.width, height: 14)
    }

    func applyTheme() {
        layer?.backgroundColor = (emphasized
            ? RebrandTokens.Color.lineSoft
            : RebrandTokens.Color.hoverOverlay).cgColor
        label.textColor = RebrandTokens.Color.fg2
    }
}
