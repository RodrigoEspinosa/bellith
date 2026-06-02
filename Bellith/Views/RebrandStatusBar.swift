import AppKit
import QuartzCore

/// Compact status bar for the rebrand shell. Mirrors the reference's shape,
/// but uses live session projection from `TerminalContainerView` instead of
/// placeholder text.
final class RebrandStatusBar: NSView {
    private let topLine = CALayer()
    private let modePill = RebrandPillLabel(text: "NORMAL", emphasized: true)
    private let muxPill = RebrandPillLabel(text: "ZELLIJ")
    private let muxInfo = NSTextField(labelWithString: "")
    private let centerInfo = NSTextField(labelWithString: "")
    private let trailing = NSTextField(labelWithString: "")

    private static let segmentSeparator = "  │  "

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = RebrandTokens.Color.statusBarBg.cgColor
        layer?.addSublayer(topLine)

        addSubview(modePill)
        addSubview(muxPill)

        configureLabel(muxInfo, color: RebrandTokens.Color.fg3)
        addSubview(muxInfo)

        configureLabel(centerInfo, color: RebrandTokens.Color.fg4)
        centerInfo.alignment = .center
        addSubview(centerInfo)

        trailing.attributedStringValue = Self.trailingAttributed(parts: [
            .hint(Self.paletteHint()),
            .hint(Self.newTabHint()),
        ])
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
            muxPill.isHidden = true
            muxInfo.attributedStringValue = NSAttributedString()
            centerInfo.attributedStringValue = NSAttributedString()
            trailing.attributedStringValue = Self.trailingAttributed(parts: [
                .hint(Self.paletteHint()),
                .hint(Self.newTabHint()),
            ])
            needsLayout = true
            return
        }

        let mode = summary.isBroadcasting ? "BROADCAST" : "NORMAL"
        modePill.text = mode
        muxPill.text = summary.muxName?.uppercased() ?? ""
        muxPill.isHidden = summary.muxName == nil

        let paneText = summary.paneCount > 1
            ? "pane \(summary.focusedPaneIndex)/\(summary.paneCount)"
            : "pane 1/1"

        var segments: [Segment] = []
        // Lead with cwd at full brightness — it's the part that actually
        // changes session-to-session, so it earns the strongest weight.
        if let cwd = summary.cwdDisplay { segments.append(.primary(cwd)) }
        segments.append(.secondary(paneText))
        if let branch = summary.gitBranch { segments.append(.secondary(branch)) }
        muxInfo.attributedStringValue = Self.segmentsAttributed(segments)

        var centerSegments: [Segment] = []
        if let process = summary.processDisplay { centerSegments.append(.secondary(process)) }
        centerInfo.attributedStringValue = Self.segmentsAttributed(centerSegments)

        var trailingSegments: [Segment] = []
        if summary.paneCount > 1 { trailingSegments.append(.hint("⌃a prefix")) }
        trailingSegments.append(.hint(Self.paletteHint()))
        trailingSegments.append(.hint(Self.newTabHint()))
        trailing.attributedStringValue = Self.trailingAttributed(parts: trailingSegments)
        needsLayout = true
    }

    private enum Segment {
        case primary(String)
        case secondary(String)
        case hint(String)
    }

    private static func segmentsAttributed(_ segments: [Segment]) -> NSAttributedString {
        guard !segments.isEmpty else { return NSAttributedString() }
        let result = NSMutableAttributedString()
        for (idx, segment) in segments.enumerated() {
            if idx > 0 { result.append(separatorAttributed()) }
            result.append(attributed(for: segment))
        }
        return result
    }

    private static func trailingAttributed(parts: [Segment]) -> NSAttributedString {
        segmentsAttributed(parts)
    }

    private static func attributed(for segment: Segment) -> NSAttributedString {
        let font = RebrandTokens.Typography.mono(11, weight: .regular)
        switch segment {
        case let .primary(text):
            return NSAttributedString(string: text, attributes: [
                .font: RebrandTokens.Typography.mono(11, weight: .medium),
                .foregroundColor: RebrandTokens.Color.fg2,
            ])
        case let .secondary(text):
            return NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: RebrandTokens.Color.fg3,
            ])
        case let .hint(text):
            return NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: RebrandTokens.Color.fg3,
            ])
        }
    }

    private static func separatorAttributed() -> NSAttributedString {
        // Pipe is more visible than `·` at 11pt mono on dark, and dimmer than
        // body text so it reads as a divider rather than another token.
        NSAttributedString(string: segmentSeparator, attributes: [
            .font: RebrandTokens.Typography.mono(11, weight: .regular),
            .foregroundColor: RebrandTokens.Color.fg4.withAlphaComponent(0.6),
        ])
    }

    private static func paletteHint() -> String {
        let shortcut = BellithSettings.shared.shortcutSummary(for: "commandPalette") ?? "⇧⌘P"
        return "\(shortcut) palette"
    }

    private static func newTabHint() -> String {
        let shortcut = BellithSettings.shared.shortcutSummary(for: "newTab") ?? "⌘T"
        return "\(shortcut) new tab"
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

        let muxPillSize = muxPill.isHidden ? .zero : muxPill.intrinsicContentSize
        if !muxPill.isHidden {
            muxPill.frame = NSRect(
                x: modePill.frame.maxX + 8,
                y: floor((bounds.height - muxPillSize.height) / 2),
                width: muxPillSize.width,
                height: muxPillSize.height
            )
        }

        let trailW = ceil(trailing.attributedStringValue.size().width) + 4
        trailing.frame = NSRect(
            x: bounds.width - padX - trailW,
            y: floor((bounds.height - 14) / 2),
            width: trailW,
            height: 14
        )

        let muxX = (muxPill.isHidden ? modePill.frame.maxX : muxPill.frame.maxX) + 10
        let muxMeasuredW = muxInfo.attributedStringValue.length == 0
            ? 0
            : ceil(muxInfo.attributedStringValue.size().width) + 4
        let muxAvailableW = max(0, trailing.frame.minX - muxX - 12)
        muxInfo.frame = NSRect(
            x: muxX,
            y: floor((bounds.height - 14) / 2),
            width: min(muxMeasuredW, muxAvailableW),
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
        muxPill.applyTheme()
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
