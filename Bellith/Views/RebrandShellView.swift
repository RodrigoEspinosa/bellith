import AppKit

/// Top-level rebrand shell. Wraps an existing (chromeless) `TerminalContainerView`
/// so all existing terminal features keep working, but renders new chrome built
/// from the PR Popover v2 design tokens. AppDelegate decides whether to use
/// this or the legacy chrome based on `BellithSettings.useRebrandShell`.
final class RebrandShellView: NSView {
    let container: TerminalContainerView
    private let outerStroke = CALayer()
    private let railDivider = CALayer()
    private let bodyTopShadow = CAGradientLayer()
    private let topHighlight = CAGradientLayer()
    private let titleBar = RebrandTitleBar()
    private let rail = RebrandWorkspaceRail()
    private let body = RebrandBodyView()
    private let statusBar = RebrandStatusBar()

    init(container: TerminalContainerView) {
        self.container = container
        super.init(frame: .zero)
        wantsLayer = true
        // Window-level rounded card chrome. The legacy `contentBackdropLayer`
        // is hidden when embedded, so the shell paints its own rounded fill.
        layer?.backgroundColor = RebrandTokens.Color.windowBg.cgColor
        layer?.cornerRadius = RebrandTokens.Layout.windowCornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = RebrandTokens.Color.line.cgColor
        layer?.masksToBounds = true
        layer?.addSublayer(outerStroke)
        layer?.addSublayer(railDivider)
        layer?.addSublayer(bodyTopShadow)
        layer?.addSublayer(topHighlight)

        addSubview(titleBar)
        addSubview(rail)
        addSubview(body)
        addSubview(statusBar)

        // The legacy container lives inside the new body, with its own chrome
        // suppressed — the rebrand views own the visible look.
        container.embedInRebrandShell = true
        body.embed(container)
        body.onSplitRight = { [weak container] in
            container?.splitPane(direction: .vertical)
        }
        body.onSplitDown = { [weak container] in
            container?.splitPane(direction: .horizontal)
        }
        applyMaterialSettings()

        rail.onSelect = { [weak container] id in
            guard let container else { return }
            if let summary = container.embeddedTabSummaries.first(where: { $0.id == id }) {
                container.selectTab(summary.sourceIndex)
            }
        }
        rail.onAdd = { [weak container] in
            container?.createTab()
        }

        container.onEmbeddedStateChanged = { [weak self] in
            self?.refreshFromContainer()
        }
        refreshFromContainer()
    }

    private func refreshFromContainer() {
        let summaries = container.embeddedTabSummaries
        let selectedSourceIdx = container.embeddedSelectedTabIndex
        let active = summaries.first(where: { $0.sourceIndex == selectedSourceIdx })

        let activeTitle = active?.title.trimmingCharacters(in: .whitespaces)
        let workspaceName = (activeTitle?.isEmpty == false) ? activeTitle! : "session"
        titleBar.workspaceName = workspaceName
        titleBar.paneCount = active?.paneCount ?? 0
        titleBar.muxLabel = container.embeddedStatusSummary?.muxName
        titleBar.workspaceTint = (activeTitle?.isEmpty == false)
            ? RebrandWorkspaceTint.accent(for: activeTitle!)
            : RebrandTokens.Color.fg2
        rail.workspaces = summaries.enumerated().map { idx, s in
            RebrandWorkspaceRail.Workspace(
                id: s.id,
                title: s.title,
                paneCount: s.paneCount,
                hotkeyDigit: idx < 9 ? idx + 1 : nil
            )
        }
        rail.selectedID = active?.id
        statusBar.configure(container.embeddedStatusSummary)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func applyMaterialSettings() {
        layer?.backgroundColor = RebrandTokens.Color.windowBg.cgColor
        body.applyMaterialOpacity()
    }

    // MARK: Layout
    override func layout() {
        super.layout()
        let L = RebrandTokens.Layout.self
        let h = bounds.height
        let w = bounds.width

        titleBar.frame = NSRect(x: 0, y: h - L.titleBarHeight, width: w, height: L.titleBarHeight)
        rail.frame = NSRect(x: 0, y: 0, width: L.railWidth, height: h - L.titleBarHeight)
        let bodyX = L.railWidth
        let bodyW = max(0, w - bodyX)
        let bodyH = max(0, h - L.titleBarHeight - L.statusBarHeight)
        body.frame = NSRect(x: bodyX, y: L.statusBarHeight, width: bodyW, height: bodyH)
        statusBar.frame = NSRect(x: bodyX, y: 0, width: bodyW, height: L.statusBarHeight)

        outerStroke.frame = bounds.insetBy(dx: 0.5, dy: 0.5)
        outerStroke.cornerRadius = max(0, L.windowCornerRadius - 0.5)
        outerStroke.cornerCurve = .continuous
        outerStroke.borderWidth = 1
        outerStroke.borderColor = NSColor.white.withAlphaComponent(0.045).cgColor
        outerStroke.backgroundColor = NSColor.clear.cgColor

        railDivider.frame = NSRect(x: L.railWidth - 1, y: 0, width: 1, height: h - L.titleBarHeight)
        railDivider.backgroundColor = RebrandTokens.Color.lineSoft.cgColor

        bodyTopShadow.frame = NSRect(x: bodyX, y: h - L.titleBarHeight - 10, width: bodyW, height: 10)
        bodyTopShadow.colors = [
            NSColor.black.withAlphaComponent(0.10).cgColor,
            NSColor.clear.cgColor,
        ]
        bodyTopShadow.startPoint = CGPoint(x: 0.5, y: 1)
        bodyTopShadow.endPoint = CGPoint(x: 0.5, y: 0)

        topHighlight.frame = NSRect(x: 1, y: h - 22, width: max(0, w - 2), height: 21)
        topHighlight.colors = [
            NSColor.white.withAlphaComponent(0.05).cgColor,
            NSColor.clear.cgColor,
        ]
        topHighlight.startPoint = CGPoint(x: 0.5, y: 1)
        topHighlight.endPoint = CGPoint(x: 0.5, y: 0)
    }
}

/// Body container — currently just hosts the legacy `TerminalContainerView`
/// (with its own chrome suppressed) inside the design's `--bg` field. As we
/// migrate features, this view will own pane card layout directly.
final class RebrandBodyView: NSView {
    private let paneDock = RebrandPaneDock()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = RebrandTokens.Color.windowBg.cgColor
        paneDock.onSplitRight = { [weak self] in self?.onSplitRight?() }
        paneDock.onSplitDown = { [weak self] in self?.onSplitDown?() }
        addSubview(paneDock)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private weak var hostedContainer: NSView?
    var onSplitRight: (() -> Void)?
    var onSplitDown: (() -> Void)?

    func embed(_ container: NSView) {
        hostedContainer?.removeFromSuperview()
        hostedContainer = container
        addSubview(container)
        needsLayout = true
    }

    func applyMaterialOpacity() {
        layer?.backgroundColor = RebrandTokens.Color.windowBg.cgColor
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = RebrandTokens.Layout.bodyPaddingHorizontal
        let topPad: CGFloat = RebrandTokens.Layout.bodyPaddingTop
        hostedContainer?.frame = NSRect(
            x: pad,
            y: 0,
            width: max(0, bounds.width - pad * 2),
            height: max(0, bounds.height - topPad)
        )
        paneDock.frame = NSRect(x: pad + 18, y: 18, width: 132, height: 44)
    }
}

private final class RebrandPaneDock: NSView {
    private let backgroundLayer = CALayer()
    private let splitRight = RebrandPaneDockButton(symbolName: "rectangle.split.2x1", fallback: "▮▮")
    private let splitDown = RebrandPaneDockButton(symbolName: "rectangle.split.1x2", fallback: "▰")
    private let pulse = RebrandPaneDockButton(symbolName: "waveform.path.ecg", fallback: "~")
    private let branch = RebrandPaneDockButton(symbolName: "point.3.connected.trianglepath.dotted", fallback: "◎")

    var onSplitRight: (() -> Void)?
    var onSplitDown: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(backgroundLayer)

        splitRight.toolTip = "Split Right  ⌘D"
        splitDown.toolTip = "Split Down  ⇧⌘D"
        splitRight.onClick = { [weak self] in self?.onSplitRight?() }
        splitDown.onClick = { [weak self] in self?.onSplitDown?() }
        pulse.isEnabled = false
        branch.isEnabled = false
        addSubview(splitRight)
        addSubview(splitDown)
        addSubview(pulse)
        addSubview(branch)
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
        let buttonSize: CGFloat = 30
        let y = floor((bounds.height - buttonSize) / 2)
        splitRight.frame = NSRect(x: 8, y: y, width: buttonSize, height: buttonSize)
        splitDown.frame = NSRect(x: 40, y: y, width: buttonSize, height: buttonSize)
        pulse.frame = NSRect(x: 72, y: y, width: buttonSize, height: buttonSize)
        branch.frame = NSRect(x: 104, y: y, width: buttonSize, height: buttonSize)
    }

    private func applyTheme() {
        backgroundLayer.cornerRadius = 12
        backgroundLayer.cornerCurve = .continuous
        backgroundLayer.backgroundColor = RebrandTokens.Color.paneBg.withAlphaComponent(0.98).cgColor
        backgroundLayer.borderWidth = 1
        backgroundLayer.borderColor = RebrandTokens.Color.line.cgColor
        splitRight.applyTheme()
        splitDown.applyTheme()
        pulse.applyTheme()
        branch.applyTheme()
    }
}

private final class RebrandPaneDockButton: NSView {
    private let backgroundLayer = CALayer()
    private let imageView = NSImageView()
    private let fallbackLabel = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var isHovered = false { didSet { applyTheme() } }
    var isEnabled = true { didSet { applyTheme() } }
    var onClick: (() -> Void)?

    init(symbolName: String, fallback: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(backgroundLayer)

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyDown
            addSubview(imageView)
        } else {
            fallbackLabel.stringValue = fallback
            fallbackLabel.font = RebrandTokens.Typography.mono(11, weight: .medium)
            fallbackLabel.alignment = .center
            fallbackLabel.isEditable = false
            fallbackLabel.isBezeled = false
            fallbackLabel.drawsBackground = false
            addSubview(fallbackLabel)
        }
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseUp(with event: NSEvent) {
        if isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
        imageView.frame = bounds.insetBy(dx: 7, dy: 7)
        fallbackLabel.frame = bounds
    }

    func applyTheme() {
        let fill: NSColor
        let tint: NSColor
        if !isEnabled {
            fill = NSColor.clear
            tint = RebrandTokens.Color.fg4.withAlphaComponent(0.55)
        } else if isHovered {
            fill = RebrandTokens.Color.hoverOverlay
            tint = RebrandTokens.Color.fg
        } else {
            fill = NSColor.clear
            tint = RebrandTokens.Color.fg3
        }
        backgroundLayer.cornerRadius = 8
        backgroundLayer.cornerCurve = .continuous
        backgroundLayer.backgroundColor = fill.cgColor
        imageView.contentTintColor = tint
        fallbackLabel.textColor = tint
    }
}
