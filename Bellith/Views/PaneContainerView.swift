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
    private var showsCardChrome: Bool = false

    init(surface: NSView) {
        self.surface = surface
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        addSubview(header)
        addSubview(surface)
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
    }

    /// Draw a per-pane card hairline + 8px corner only when there are multiple
    /// panes — single panes lean on the outer window chrome for their card
    /// look so we don't double up rounded layers.
    private func applyCardChrome() {
        if showsCardChrome {
            layer?.cornerRadius = 8
            layer?.masksToBounds = true
            layer?.borderWidth = 1
        } else {
            layer?.cornerRadius = 0
            layer?.masksToBounds = false
            layer?.borderWidth = 0
        }
        layer?.borderColor = showsCardChrome
            ? RebrandTokens.Color.lineSoft.cgColor
            : NSColor.clear.cgColor
    }

    func refreshTheme() {
        header.refreshTheme()
        applyCardChrome()
    }
}

/// 24px header row above each pane with a pid pill, title, cwd, and status dot.
final class PaneHeaderView: NSView {
    static let height: CGFloat = 24

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

        statusDot.cornerRadius = 2.5
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
        let dotSize: CGFloat = 5
        statusDot.frame = NSRect(
            x: bounds.width - pad - dotSize,
            y: floor((h - dotSize) / 2),
            width: dotSize,
            height: dotSize
        )
        let rightAvailable = statusDot.frame.minX - 8

        let pidSize = pidPill.intrinsicContentSize
        let pidWidth = max(28, ceil(pidSize.width))
        pidPill.frame = NSRect(
            x: pad,
            y: floor((h - 14) / 2),
            width: pidWidth,
            height: 14
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
            y: floor((h - 14) / 2),
            width: titleWidth,
            height: 14
        )

        let cwdX = titleLabel.frame.maxX + gap
        let cwdMaxWidth = max(0, rightAvailable - cwdX)
        cwdLabel.frame = NSRect(
            x: cwdX,
            y: floor((h - 14) / 2),
            width: cwdMaxWidth,
            height: 14
        )
    }

    func refreshTheme() {
        let isLight = Theme.colors.isLight
        let idleBg: NSColor = RebrandTokens.Color.paneHeaderBg
        let focusedBg = RebrandTokens.Color.paneHeaderBgFocused
        backgroundLayer.backgroundColor = (isFocused ? focusedBg : idleBg).cgColor
        bottomLineLayer.backgroundColor = (isFocused
            ? RebrandTokens.Color.lineStrong.withAlphaComponent(isLight ? 0.38 : 0.42)
            : RebrandTokens.Color.lineSoft.withAlphaComponent(isLight ? 0.50 : 0.55)
        ).cgColor

        titleLabel.textColor = isFocused ? RebrandTokens.Color.fg : RebrandTokens.Color.fg2
        cwdLabel.textColor = RebrandTokens.Color.fg4

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
            backgroundLayer.backgroundColor = RebrandTokens.Color.windowBg.withAlphaComponent(0.92).cgColor
            textField.textColor = RebrandTokens.Color.fg3
        }
    }
}
