import AppKit
import QuartzCore

// MARK: - Sidebar Tab Row

final class SidebarTabRow: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onDragMoved: ((NSEvent) -> Void)?
    var onDragEnded: ((NSEvent) -> Void)?
    var onRightClick: ((NSPoint) -> Void)?
    private var isDragging = false
    private var mouseDownLocation: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }

    private let selectionIndicator = CALayer()
    private let glyphLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let badgeContainer = CALayer()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let title: String
    private let isSelected: Bool
    private let kind: TerminalContainerView.TabKind
    private let smartPanelRegistry: SmartPanelRegistry
    private var isHovered = false
    private var hotkeyDigit: Int?
    private var paneCount: Int = 1
    private weak var hoverTipView: WorkspaceTipView?
    private var hoverTipShowWorkItem: DispatchWorkItem?

    private var isSmartTab: Bool {
        if case .smart = kind { return true }
        return false
    }

    /// PR Popover v2 hue per workspace, derived deterministically from the title.
    /// Returns a hue value usable for tinted gradient.
    private var workspaceHue: CGFloat { WorkspaceTint.hue(for: title) }

    init(
        title: String,
        isSelected: Bool,
        kind: TerminalContainerView.TabKind,
        smartPanelRegistry: SmartPanelRegistry
    ) {
        self.title = title
        self.isSelected = isSelected
        self.kind = kind
        self.smartPanelRegistry = smartPanelRegistry
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.masksToBounds = false

        setAccessibilityRole(.button)
        setAccessibilityLabel("Tab: \(title)")
        setAccessibilityValue(isSelected ? "selected" : "")
        toolTip = title

        selectionIndicator.cornerRadius = 1.5
        selectionIndicator.cornerCurve = .continuous
        layer?.addSublayer(selectionIndicator)

        glyphLabel.font = BellithFont.mono(15, weight: .semibold)
        glyphLabel.alignment = .center
        glyphLabel.isEditable = false
        glyphLabel.isBezeled = false
        glyphLabel.drawsBackground = false
        glyphLabel.maximumNumberOfLines = 1
        addSubview(glyphLabel)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.isHidden = true
        addSubview(iconView)

        if case .smart(let pluginID) = kind,
           let plugin = smartPanelRegistry.plugin(for: pluginID) {
            iconView.image = NSImage(systemSymbolName: plugin.iconName, accessibilityDescription: nil)
            iconView.isHidden = false
            glyphLabel.stringValue = ""
        } else {
            glyphLabel.stringValue = Self.makeGlyph(from: title)
        }

        badgeContainer.cornerRadius = 6
        badgeContainer.cornerCurve = .continuous
        badgeContainer.borderWidth = 1
        layer?.addSublayer(badgeContainer)

        badgeLabel.font = BellithFont.mono(8.5, weight: .semibold)
        badgeLabel.alignment = .center
        badgeLabel.isEditable = false
        badgeLabel.isBezeled = false
        badgeLabel.drawsBackground = false
        badgeLabel.stringValue = ""
        badgeLabel.maximumNumberOfLines = 1
        addSubview(badgeLabel)

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let bounds = self.bounds

        // 3px accent strip flush with the rail's left edge. Card is centered in
        // the 56px rail (so card.x ≈ 9), so x = -9 puts the strip at rail.x = 0.
        selectionIndicator.frame = NSRect(x: -9, y: 8, width: 3, height: max(0, bounds.height - 16))

        let glyphSize = NSSize(width: bounds.width, height: 18)
        glyphLabel.frame = NSRect(
            x: 0,
            y: floor((bounds.height - glyphSize.height) / 2),
            width: glyphSize.width,
            height: glyphSize.height
        )

        let iconSize: CGFloat = 16
        iconView.frame = NSRect(
            x: floor((bounds.width - iconSize) / 2),
            y: floor((bounds.height - iconSize) / 2),
            width: iconSize,
            height: iconSize
        )

        // Pane-count badge anchored to bottom-right.
        let badgeText = badgeLabel.stringValue
        let badgeIntrinsic = badgeLabel.intrinsicContentSize
        let badgeW = badgeText.isEmpty ? 0 : max(14, ceil(badgeIntrinsic.width) + 8)
        let badgeH: CGFloat = 13
        let badgeX = bounds.width - badgeW + 2
        let badgeY: CGFloat = -2
        badgeContainer.frame = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
        badgeLabel.frame = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
    }

    func setPaneCount(_ count: Int) {
        paneCount = count
        if count <= 1 {
            badgeLabel.stringValue = ""
        } else {
            badgeLabel.stringValue = "\(count)"
        }
        updateAppearance()
        needsLayout = true
    }

    func setHotkeyDigit(_ digit: Int?) {
        hotkeyDigit = digit
        // System tooltip kept as a fallback (e.g. for VoiceOver) — the rich
        // floating tip view replaces it visually on hover.
        if let digit, (1...9).contains(digit) {
            toolTip = "\(title)  ⌘\(digit)"
        } else {
            toolTip = title
        }
    }

    private static func makeGlyph(from title: String) -> String {
        guard let first = title.unicodeScalars.first(where: { $0.properties.isAlphabetic || ("0"..."9").contains(Character($0)) }) else {
            return "•"
        }
        return String(first).uppercased()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        scheduleShowHoverTip()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        hideHoverTip()
    }

    private func scheduleShowHoverTip() {
        hoverTipShowWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showHoverTip() }
        hoverTipShowWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func showHoverTip() {
        guard isHovered, hoverTipView == nil, let window = window else { return }

        let tip = WorkspaceTipView(
            title: title,
            hotkeyDigit: hotkeyDigit,
            paneCount: paneCount,
            tint: WorkspaceTint.accent(for: title)
        )
        tip.alphaValue = 0
        window.contentView?.addSubview(tip)

        // Position the tip just to the right of the card, vertically centered.
        let cardOriginInWindow = convert(bounds, to: window.contentView)
        let tipSize = tip.intrinsicContentSize
        let tipX = cardOriginInWindow.maxX + 10
        let tipY = cardOriginInWindow.midY - tipSize.height / 2
        tip.frame = NSRect(x: tipX, y: tipY, width: tipSize.width, height: tipSize.height)

        hoverTipView = tip
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            tip.animator().alphaValue = 1
        }
    }

    private func hideHoverTip() {
        hoverTipShowWorkItem?.cancel()
        hoverTipShowWorkItem = nil
        guard let tip = hoverTipView else { return }
        hoverTipView = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            tip.animator().alphaValue = 0
        } completionHandler: {
            tip.removeFromSuperview()
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let loc = event.locationInWindow
        if !isDragging && hypot(loc.x - start.x, loc.y - start.y) > 4 {
            isDragging = true
        }
        if isDragging { onDragMoved?(event) }
    }

    override func mouseUp(with event: NSEvent) {
        let shouldSelect = !isDragging
        if isDragging { onDragEnded?(event) }
        isDragging = false
        mouseDownLocation = nil
        // Fire selection after drag handling so refreshTabUI doesn't rebuild the row mid-interaction.
        if shouldSelect { onSelect?() }
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick?(event.locationInWindow) }
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }

    private func updateAppearance() {
        let hue = workspaceHue
        let backgroundColor: CGColor
        let borderColor: CGColor
        let glyphColor: NSColor
        let iconColor: NSColor
        let indicatorColor: CGColor
        let badgeFillColor: CGColor
        let badgeBorderColor: CGColor
        let badgeTextColor: NSColor
        let shadowOpacity: Float

        let isLight = Theme.colors.isLight
        // Tinted bg pulled toward the surface gray so the active card glows
        // gently rather than screaming. The saturated accent is reserved for
        // the strip, border, glyph, and badge.
        let huedTint = NSColor(deviceHue: hue / 360, saturation: 0.30, brightness: isLight ? 0.92 : 0.62, alpha: 1)
        let huedAccent = WorkspaceTint.accent(for: title)

        if isSelected {
            backgroundColor = huedTint.withAlphaComponent(isLight ? 0.16 : 0.20).cgColor
            borderColor = huedAccent.withAlphaComponent(0.55).cgColor
            glyphColor = huedAccent
            iconColor = huedAccent
            indicatorColor = huedAccent.cgColor
            badgeFillColor = (isLight ? NSColor.white : Theme.frame).cgColor
            badgeBorderColor = huedAccent.withAlphaComponent(0.7).cgColor
            badgeTextColor = huedAccent
            shadowOpacity = 0.35
        } else if isHovered {
            backgroundColor = Theme.chromeElevated.withAlphaComponent(isLight ? 0.55 : 0.55).cgColor
            borderColor = Theme.chromeHairline.withAlphaComponent(0.4).cgColor
            glyphColor = Theme.textPrimary
            iconColor = Theme.textPrimary
            indicatorColor = NSColor.clear.cgColor
            badgeFillColor = Theme.frame.cgColor
            badgeBorderColor = Theme.chromeHairline.cgColor
            badgeTextColor = Theme.textSecondary
            shadowOpacity = 0
        } else {
            backgroundColor = NSColor.clear.cgColor
            borderColor = NSColor.clear.cgColor
            glyphColor = Theme.textSecondary
            iconColor = Theme.textSecondary
            indicatorColor = NSColor.clear.cgColor
            badgeFillColor = Theme.frame.cgColor
            badgeBorderColor = Theme.chromeHairline.cgColor
            badgeTextColor = Theme.textTertiary
            shadowOpacity = 0
        }

        layer?.shadowColor = huedAccent.withAlphaComponent(0.4).cgColor
        layer?.shadowOpacity = shadowOpacity
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            self.layer?.backgroundColor = backgroundColor
            self.layer?.borderColor = borderColor
            self.selectionIndicator.backgroundColor = indicatorColor
            self.glyphLabel.animator().textColor = glyphColor
            self.iconView.animator().contentTintColor = iconColor
            self.badgeContainer.backgroundColor = badgeFillColor
            self.badgeContainer.borderColor = badgeBorderColor
            self.badgeContainer.opacity = self.badgeLabel.stringValue.isEmpty ? 0 : 1
            self.badgeLabel.animator().textColor = badgeTextColor
        }
    }
}

// MARK: - Sidebar Tool Row

final class SidebarToolRow: NSView {
    var onSelect: (() -> Void)?
    private let plugin: SmartPanelPlugin
    private let iconView = NSImageView()
    private let tooltipText: String
    private var isHovered = false
    private var isActive = false

    init(plugin: SmartPanelPlugin, isActive: Bool = false) {
        self.plugin = plugin
        self.tooltipText = "\(plugin.title)\n\(plugin.commandDescription)"
        self.isActive = isActive
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        iconView.image = NSImage(systemSymbolName: plugin.iconName, accessibilityDescription: plugin.title)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.toolTip = tooltipText
        addSubview(iconView)

        setAccessibilityRole(.button)
        setAccessibilityLabel(plugin.title)
        setAccessibilityHelp(plugin.commandDescription)
        toolTip = tooltipText

        applyStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        applyStyle()
    }

    private func applyStyle() {
        let backgroundColor: NSColor
        let borderColor: NSColor
        let iconColor: NSColor

        if isActive {
            backgroundColor = Theme.textPrimary.withAlphaComponent(Theme.colors.isLight ? 0.08 : 0.14)
            borderColor = Theme.textPrimary.withAlphaComponent(Theme.colors.isLight ? 0.12 : 0.18)
            iconColor = Theme.accent
            layer?.shadowOpacity = 0
        } else if isHovered {
            backgroundColor = Theme.hoverOverlay
            borderColor = Theme.borderSubtle
            iconColor = Theme.textPrimary
            layer?.shadowOpacity = 0
        } else {
            backgroundColor = NSColor.clear
            borderColor = NSColor.clear
            iconColor = Theme.textPrimary.withAlphaComponent(Theme.colors.isLight ? 0.68 : 0.72)
            layer?.shadowOpacity = 0
        }

        iconView.contentTintColor = iconColor
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderColor = borderColor.cgColor
    }

    override func layout() {
        super.layout()
        let iconSize = min(bounds.width, bounds.height) - 14
        iconView.frame = NSRect(
            x: (bounds.width - iconSize) / 2,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            self.applyStyle()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            self.applyStyle()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }
}

// MARK: - Noise Overlay

final class SidebarNoiseView: NSView {
    private var cachedSize: CGSize = .zero
    private var cachedIsLight = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        refreshTheme()
    }

    func refreshTheme() {
        let size = bounds.size
        let isLight = Theme.colors.isLight
        guard size.width > 0, size.height > 0 else { return }
        guard size != cachedSize || isLight != cachedIsLight || layer?.contents == nil else { return }

        cachedSize = size
        cachedIsLight = isLight
        layer?.contents = makeNoiseImage(tileSize: NSSize(width: 72, height: 72), isLight: isLight)
        layer?.contentsCenter = CGRect(x: 0.49, y: 0.49, width: 0.02, height: 0.02)
        layer?.contentsGravity = .resizeAspectFill
        layer?.opacity = isLight ? 0.055 : 0.08
    }

    private func makeNoiseImage(tileSize: NSSize, isLight: Bool) -> CGImage? {
        let width = max(1, Int(tileSize.width))
        let height = max(1, Int(tileSize.height))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let base = isLight ? 0.0 : 1.0
        let majorCount = 320
        let minorCount = 110

        for _ in 0..<majorCount {
            let x = CGFloat(Int.random(in: 0..<width))
            let y = CGFloat(Int.random(in: 0..<height))
            let alpha = CGFloat.random(in: isLight ? 0.006...0.016 : 0.008...0.02)
            context.setFillColor(NSColor(white: base, alpha: alpha).cgColor)
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }

        for _ in 0..<minorCount {
            let x = CGFloat(Int.random(in: 0..<width))
            let y = CGFloat(Int.random(in: 0..<height))
            let alpha = CGFloat.random(in: isLight ? 0.002...0.008 : 0.003...0.01)
            context.setFillColor(Theme.accent.withAlphaComponent(alpha).cgColor)
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }

        return context.makeImage()
    }
}

// MARK: - Workspace Card Hover Tip

/// Floating tooltip view that mirrors the design's `.tip`: a dark glass pill with
/// the workspace name, an aligned hotkey badge, and a sub-line for pane count.
final class WorkspaceTipView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let hotkeyKbd = KbdView()
    private let subLabel = NSTextField(labelWithString: "")
    private let borderLayer = CALayer()
    private let backgroundLayer = CALayer()
    private let tint: NSColor

    init(title: String, hotkeyDigit: Int?, paneCount: Int, tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)
        wantsLayer = true
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.55).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.masksToBounds = false

        backgroundLayer.cornerRadius = 6
        backgroundLayer.cornerCurve = .continuous
        backgroundLayer.masksToBounds = true
        layer?.addSublayer(backgroundLayer)

        borderLayer.cornerRadius = 6
        borderLayer.cornerCurve = .continuous
        borderLayer.borderWidth = 1
        borderLayer.borderColor = Theme.chromeHairline.withAlphaComponent(0.7).cgColor
        layer?.addSublayer(borderLayer)

        titleLabel.stringValue = title
        titleLabel.font = BellithFont.mono(11.5, weight: .medium)
        titleLabel.textColor = tint
        titleLabel.isEditable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        if let digit = hotkeyDigit, (1...9).contains(digit) {
            hotkeyKbd.text = "⌘\(digit)"
            addSubview(hotkeyKbd)
        }

        let countText = paneCount > 1 ? "\(paneCount) panes" : "1 pane"
        subLabel.stringValue = countText
        subLabel.font = BellithFont.mono(10, weight: .regular)
        subLabel.textColor = Theme.textTertiary
        subLabel.isEditable = false
        subLabel.isBezeled = false
        subLabel.drawsBackground = false
        addSubview(subLabel)

        applyBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func applyBackground() {
        let isLight = Theme.colors.isLight
        backgroundLayer.backgroundColor = (isLight
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor(white: 0.10, alpha: 0.96)).cgColor
    }

    override var intrinsicContentSize: NSSize {
        let titleW = ceil(titleLabel.attributedStringValue.size().width)
        let kbdW = hotkeyKbd.superview != nil ? ceil(hotkeyKbd.intrinsicContentSize.width) + 8 : 0
        let subW = ceil(subLabel.attributedStringValue.size().width)
        let topRow = titleW + kbdW
        let width = max(topRow, subW) + 18
        return NSSize(width: max(120, width), height: 38)
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
        borderLayer.frame = bounds

        let titleSize = titleLabel.attributedStringValue.size()
        titleLabel.frame = NSRect(
            x: 9,
            y: bounds.height - 7 - 14,
            width: ceil(titleSize.width) + 2,
            height: 14
        )
        if hotkeyKbd.superview != nil {
            let kbdSize = hotkeyKbd.intrinsicContentSize
            hotkeyKbd.frame = NSRect(
                x: bounds.width - kbdSize.width - 9,
                y: bounds.height - 6 - kbdSize.height,
                width: kbdSize.width,
                height: kbdSize.height
            )
        }
        subLabel.frame = NSRect(
            x: 9,
            y: 5,
            width: bounds.width - 18,
            height: 12
        )
    }
}
