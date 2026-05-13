import AppKit
import QuartzCore

/// Hashes a workspace name to a stable hue for the PR Popover v2 chrome.
/// Single source of truth — referenced by the sidebar rail (active tile) and
/// the pane container (focused pid pill, focus border) so the active
/// workspace's identity color flows through the whole app.
enum WorkspaceTint {
    private static let palette: [CGFloat] = [30, 200, 150, 280, 330, 100, 240, 0]

    static func hue(for title: String) -> CGFloat {
        guard !title.isEmpty else { return 200 }
        var hash: UInt64 = 5381
        for byte in title.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return palette[Int(hash % UInt64(palette.count))]
    }

    /// Accent color for borders, glow, and tinted chips. Saturation is held
    /// down so workspace identity reads as a "tasteful tint" rather than a
    /// loud highlight — the design's `oklch(0.78 0.14 var(--ws-hue))` is
    /// already on the muted end of the gamut.
    static func accent(for title: String) -> NSColor {
        NSColor(deviceHue: hue(for: title) / 360, saturation: 0.55, brightness: 0.82, alpha: 1)
    }
}

/// Wraps a terminal surface with a 24px header row matching the PR Popover v2 design:
/// `[0:N]  zsh  ~/code/foo                                ●`
final class PaneContainerView: NSView {
    let surface: NSView
    private let header = PaneHeaderView()
    private let inactiveOverlay = PaneInactiveOverlayView()
    private let borderOverlay = PaneBorderOverlayView()
    private var showsCardChrome: Bool = false

    init(surface: NSView) {
        self.surface = surface
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        addSubview(header)
        addSubview(surface)
        addSubview(inactiveOverlay)
        addSubview(borderOverlay)
        applyCardChrome()
        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // For single panes the header row is hidden — title bar + status bar
        // already surface the process/cwd, so duplicating it as a band over the
        // terminal just steals space.
        let headerHeight = showsCardChrome ? PaneHeaderView.height : 0
        header.isHidden = !showsCardChrome
        header.frame = NSRect(
            x: 0,
            y: bounds.height - headerHeight,
            width: bounds.width,
            height: headerHeight
        )
        surface.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(0, bounds.height - headerHeight)
        )
        inactiveOverlay.frame = bounds
        borderOverlay.frame = bounds
    }

    func configure(
        paneIndex: String,
        title: String,
        cwd: String?,
        isFocused: Bool,
        isRunning: Bool,
        workspaceTint: NSColor,
        showsCardChrome: Bool
    ) {
        header.configure(
            paneIndex: paneIndex,
            title: title,
            cwd: cwd,
            isFocused: isFocused,
            isRunning: isRunning,
            workspaceTint: workspaceTint
        )
        if self.showsCardChrome != showsCardChrome {
            self.showsCardChrome = showsCardChrome
            applyCardChrome()
            needsLayout = true
        }
        if showsCardChrome {
            inactiveOverlay.setVisible(!isFocused)
            borderOverlay.configure(
                strokeColor: isFocused
                ? workspaceTint.withAlphaComponent(0.45)
                : RebrandTokens.Color.lineSoft.withAlphaComponent(0.65),
                lineWidth: isFocused ? 1.5 : 1,
                inset: isFocused ? 2 : 1.5
            )
            layer?.shadowOpacity = 0
        } else {
            inactiveOverlay.setVisible(false)
            borderOverlay.configure(strokeColor: .clear, lineWidth: 0)
            layer?.shadowOpacity = 0
        }
    }

    /// Draw a per-pane card hairline + 8px corner only when there are multiple
    /// panes — single panes lean on the outer window chrome for their card
    /// look so we don't double up rounded layers.
    private func applyCardChrome() {
        if showsCardChrome {
            layer?.cornerRadius = RebrandTokens.Layout.paneCornerRadius
            layer?.masksToBounds = true
            layer?.borderWidth = 0
        } else {
            layer?.cornerRadius = 0
            layer?.masksToBounds = false
            layer?.borderWidth = 0
        }
        borderOverlay.isHidden = !showsCardChrome
        inactiveOverlay.isHidden = !showsCardChrome
        borderOverlay.configure(
            strokeColor: showsCardChrome ? RebrandTokens.Color.lineSoft.withAlphaComponent(0.65) : .clear,
            lineWidth: showsCardChrome ? 1 : 0,
            inset: showsCardChrome ? 1.5 : 0
        )
    }

    func refreshTheme() {
        header.refreshTheme()
        applyCardChrome()
    }
}

private final class PaneInactiveOverlayView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = RebrandTokens.Color.windowBg.withAlphaComponent(0.18).cgColor
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setVisible(_ visible: Bool) {
        alphaValue = visible ? 1 : 0
    }
}

/// Draws the pane hairline above the terminal/header subviews.
///
/// A `CALayer.borderWidth` on `PaneContainerView` is too easy for child view
/// layers to visually cover at the top/right edges. Drawing an inset stroke in
/// a topmost overlay keeps every edge visible while the parent still clips the
/// terminal contents to the rounded pane shape.
private final class PaneBorderOverlayView: NSView {
    private var strokeColor: NSColor = .clear
    private var lineWidth: CGFloat = 0
    private var inset: CGFloat = 0.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(strokeColor: NSColor, lineWidth: CGFloat, inset: CGFloat? = nil) {
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.inset = inset ?? max(0.5, lineWidth / 2)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard lineWidth > 0, strokeColor.alphaComponent > 0 else { return }

        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: max(0, RebrandTokens.Layout.paneCornerRadius - inset),
            yRadius: max(0, RebrandTokens.Layout.paneCornerRadius - inset)
        )
        path.lineWidth = lineWidth
        strokeColor.setStroke()
        path.stroke()
    }
}

/// 24px header row above each pane with a pid pill, title, cwd, and status dot.
final class PaneHeaderView: NSView {
    static let height: CGFloat = RebrandTokens.Layout.paneHeaderHeight

    private let backgroundLayer = CALayer()
    private let bottomLineLayer = CALayer()
    private let pidPill = PillLabel()
    private let titleLabel = NSTextField(labelWithString: "")
    private let cwdLabel = NSTextField(labelWithString: "")
    private let statusDot = CALayer()

    private var isFocused = false
    private var isRunning = false
    private var workspaceTint: NSColor = Theme.accent

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(bottomLineLayer)
        layer?.addSublayer(statusDot)

        addSubview(pidPill)

        titleLabel.font = BellithFont.mono(11, weight: .medium)
        titleLabel.isEditable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        cwdLabel.font = BellithFont.mono(11, weight: .regular)
        cwdLabel.isEditable = false
        cwdLabel.isBezeled = false
        cwdLabel.drawsBackground = false
        cwdLabel.maximumNumberOfLines = 1
        cwdLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(cwdLabel)

        statusDot.cornerRadius = 3.5
        statusDot.cornerCurve = .continuous

        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(
        paneIndex: String,
        title: String,
        cwd: String?,
        isFocused: Bool,
        isRunning: Bool,
        workspaceTint: NSColor
    ) {
        pidPill.text = paneIndex
        titleLabel.stringValue = title
        cwdLabel.stringValue = Self.normalizeCwd(cwd)
        self.isFocused = isFocused
        self.isRunning = isRunning
        self.workspaceTint = workspaceTint
        refreshTheme()
        needsLayout = true
    }

    private static func normalizeCwd(_ cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "" }
        let home = NSHomeDirectory()
        if cwd.hasPrefix(home) {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
        bottomLineLayer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)

        let pad: CGFloat = 10
        let gap: CGFloat = 8
        let h = bounds.height

        // Status dot, anchored right.
        let dotSize: CGFloat = 7
        statusDot.frame = NSRect(
            x: bounds.width - pad - dotSize,
            y: floor((h - dotSize) / 2),
            width: dotSize,
            height: dotSize
        )
        let rightAvailable = statusDot.frame.minX - 8

        let pidSize = pidPill.intrinsicContentSize
        let pidWidth = max(30, ceil(pidSize.width))
        pidPill.frame = NSRect(
            x: pad,
            y: floor((h - 15) / 2),
            width: pidWidth,
            height: 15
        )

        let titleX = pidPill.frame.maxX + gap
        // (stringValue as NSString).size(withAttributes:) is reliable in
        // layout(); attributedStringValue.size() returns 0 before AppKit has
        // built the cached attributed run, which truncated short titles like
        // "zsh" into "z…".
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleLabel.font ?? BellithFont.mono(11, weight: .medium)]
        let titleIntrinsic = ceil((titleLabel.stringValue as NSString).size(withAttributes: titleAttrs).width) + 8
        let titleWidth = max(26, min(rightAvailable - titleX - 4, titleIntrinsic))
        titleLabel.frame = NSRect(
            x: titleX,
            y: floor((h - 15) / 2),
            width: titleWidth,
            height: 15
        )

        let cwdX = titleLabel.frame.maxX + gap
        let cwdMaxWidth = max(0, rightAvailable - cwdX)
        cwdLabel.frame = NSRect(
            x: cwdX,
            y: floor((h - 15) / 2),
            width: cwdMaxWidth,
            height: 15
        )
    }

    func refreshTheme() {
        backgroundLayer.backgroundColor = NSColor.clear.cgColor
        bottomLineLayer.backgroundColor = NSColor.clear.cgColor

        titleLabel.textColor = isFocused ? RebrandTokens.Color.fg : RebrandTokens.Color.fg2
        titleLabel.font = BellithFont.mono(11, weight: isFocused ? .semibold : .medium)
        cwdLabel.textColor = isFocused ? RebrandTokens.Color.fg3 : RebrandTokens.Color.fg4

        let dotColor: NSColor
        if isRunning {
            dotColor = RebrandTokens.Color.warn
        } else if isFocused {
            dotColor = workspaceTint.withAlphaComponent(0.75)
        } else {
            dotColor = Theme.textTertiary.withAlphaComponent(0.6)
        }
        statusDot.backgroundColor = dotColor.cgColor
        applyDotPulse(isRunning: isRunning)

        pidPill.refreshTheme(isFocused: isFocused, tint: workspaceTint)
    }

    private static let pulseAnimationKey = "pane.statusDot.pulse"

    /// Mirrors the design's `@keyframes pulse` — a slow opacity sine on `.sig.run`.
    private func applyDotPulse(isRunning: Bool) {
        if isRunning {
            guard statusDot.animation(forKey: Self.pulseAnimationKey) == nil else { return }
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0
            anim.toValue = 0.35
            anim.duration = 0.7
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            statusDot.add(anim, forKey: Self.pulseAnimationKey)
        } else {
            statusDot.removeAnimation(forKey: Self.pulseAnimationKey)
            statusDot.opacity = 1
        }
    }
}

/// Small pill rendering the pane index, e.g. `0:1`.
private final class PillLabel: NSView {
    private let textField = NSTextField(labelWithString: "")
    private let backgroundLayer = CALayer()

    var text: String {
        get { textField.stringValue }
        set {
            textField.stringValue = newValue
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(backgroundLayer)
        backgroundLayer.cornerRadius = 3
        backgroundLayer.cornerCurve = .continuous

        textField.font = BellithFont.mono(10, weight: .semibold)
        textField.alignment = .center
        textField.isEditable = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.maximumNumberOfLines = 1
        addSubview(textField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: textField.font ?? BellithFont.mono(10, weight: .semibold)]
        let textWidth = ceil((textField.stringValue as NSString).size(withAttributes: attrs).width)
        return NSSize(width: textWidth + 12, height: 14)
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
        textField.frame = bounds.insetBy(dx: 4, dy: 0)
    }

    func refreshTheme(isFocused: Bool, tint: NSColor = Theme.accent) {
        let isLight = Theme.colors.isLight
        if isFocused {
            backgroundLayer.backgroundColor = tint.withAlphaComponent(isLight ? 0.16 : 0.18).cgColor
            textField.textColor = tint.withAlphaComponent(0.95)
        } else {
            // Header bg now matches paneBg (flush card), so the old windowBg
            // pill fill no longer reads. Use lineSoft as a quiet lift over
            // paneBg — visible enough to anchor the pid, quiet enough to stay
            // out of the way.
            backgroundLayer.backgroundColor = RebrandTokens.Color.lineSoft
                .withAlphaComponent(isLight ? 0.55 : 0.7).cgColor
            textField.textColor = RebrandTokens.Color.fg3
        }
    }
}
