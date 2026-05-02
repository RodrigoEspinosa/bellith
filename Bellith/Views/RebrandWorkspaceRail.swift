import AppKit
import QuartzCore

/// Vertical workspace rail that mirrors the design's `.ws-rail`:
/// 64px wide column, 40×40 letter-glyph cards stacked from the top, and a
/// `+` add tile + tools cluster pinned to the bottom. Each card carries a
/// pane-count badge and uses the workspace's own hue when active.
final class RebrandWorkspaceRail: NSView {
    private let rightHairline = CALayer()
    private var cards: [RebrandWorkspaceCard] = []
    private let addTile = RebrandAddTile()

    var workspaces: [Workspace] = [] {
        didSet { rebuildCards() }
    }
    var selectedID: UUID? {
        didSet { applySelection() }
    }
    var onSelect: ((UUID) -> Void)?
    var onAdd: (() -> Void)?

    struct Workspace {
        let id: UUID
        let title: String
        let paneCount: Int
        let hotkeyDigit: Int?
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = RebrandTokens.Color.windowBg.cgColor
        layer?.addSublayer(rightHairline)

        addTile.onClick = { [weak self] in self?.onAdd?() }
        addSubview(addTile)

        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func rebuildCards() {
        cards.forEach { $0.removeFromSuperview() }
        cards.removeAll()
        for ws in workspaces {
            let card = RebrandWorkspaceCard(workspace: ws)
            card.onClick = { [weak self] in self?.onSelect?(ws.id) }
            cards.append(card)
            addSubview(card)
        }
        applySelection()
        needsLayout = true
    }

    private func applySelection() {
        for card in cards {
            card.isSelected = (card.workspaceID == selectedID)
        }
    }

    override func layout() {
        super.layout()
        let L = RebrandTokens.Layout.self
        rightHairline.frame = NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)

        let cardX = floor((bounds.width - L.railCardSize) / 2)
        let topY = bounds.height - L.railTopInset
        var y = topY
        for card in cards {
            let frame = NSRect(x: cardX, y: y - L.railCardSize, width: L.railCardSize, height: L.railCardSize)
            card.frame = frame
            y -= L.railCardSize + L.railCardSpacing
        }

        let addH: CGFloat = 34
        addTile.frame = NSRect(x: cardX, y: L.railBottomInset, width: L.railCardSize, height: addH)
    }

    func applyTheme() {
        layer?.backgroundColor = RebrandTokens.Color.windowBg.cgColor
        rightHairline.backgroundColor = RebrandTokens.Color.lineSoft.cgColor
        cards.forEach { $0.applyTheme() }
        addTile.applyTheme()
    }
}

/// 40×40 workspace card. Idle is bare, hover is a soft fill, active gets a
/// hue-tinted bg + hue-tinted border + a 3px accent strip flush with the
/// rail's left edge.
final class RebrandWorkspaceCard: NSView {
    let workspaceID: UUID
    private let title: String
    private let glyphLabel = NSTextField(labelWithString: "")
    private let badgeLayer = CALayer()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let accentStrip = CALayer()

    private var hue: CGFloat { RebrandWorkspaceTint.hue(for: title) }
    private var accent: NSColor { RebrandWorkspaceTint.accent(for: title) }
    private var tracking: NSTrackingArea?
    private var isHovered = false { didSet { applyTheme() } }
    var isSelected = false { didSet { applyTheme() } }
    var onClick: (() -> Void)?

    init(workspace: RebrandWorkspaceRail.Workspace) {
        self.workspaceID = workspace.id
        self.title = workspace.title
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.masksToBounds = false

        accentStrip.cornerRadius = 1.5
        layer?.addSublayer(accentStrip)

        glyphLabel.stringValue = Self.glyph(from: title)
        glyphLabel.font = RebrandTokens.Typography.mono(13.5, weight: .semibold)
        glyphLabel.alignment = .center
        glyphLabel.isEditable = false
        glyphLabel.isBezeled = false
        glyphLabel.drawsBackground = false
        addSubview(glyphLabel)

        badgeLayer.cornerRadius = 6
        badgeLayer.borderWidth = 1
        layer?.addSublayer(badgeLayer)

        if workspace.paneCount > 1 {
            badgeLabel.stringValue = "\(workspace.paneCount)"
        }
        badgeLabel.font = RebrandTokens.Typography.mono(8.5, weight: .semibold)
        badgeLabel.alignment = .center
        badgeLabel.isEditable = false
        badgeLabel.isBezeled = false
        badgeLabel.drawsBackground = false
        addSubview(badgeLabel)

        toolTip = workspace.hotkeyDigit.map { "\(workspace.title)  ⌘\($0)" } ?? workspace.title
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func glyph(from title: String) -> String {
        guard let first = title.unicodeScalars.first(where: {
            $0.properties.isAlphabetic || ("0"..."9").contains(Character($0))
        }) else { return "•" }
        return String(first).uppercased()
    }

    override func updateTrackingAreas() {
        if let t = tracking { removeTrackingArea(t) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    override func layout() {
        super.layout()
        glyphLabel.frame = NSRect(
            x: 0,
            y: floor((bounds.height - 18) / 2),
            width: bounds.width,
            height: 18
        )
        let hasBadge = !badgeLabel.stringValue.isEmpty
        if hasBadge {
            let attrs: [NSAttributedString.Key: Any] = [.font: badgeLabel.font ?? RebrandTokens.Typography.mono(8.5)]
            let w = max(14, ceil((badgeLabel.stringValue as NSString).size(withAttributes: attrs).width) + 8)
            let h: CGFloat = 13
            let x = bounds.width - w + 2
            let y: CGFloat = -2
            badgeLayer.frame = NSRect(x: x, y: y, width: w, height: h)
            badgeLabel.frame = NSRect(x: x, y: y, width: w, height: h)
            badgeLayer.opacity = 1
        } else {
            badgeLayer.opacity = 0
        }
        // Accent strip is intentionally slim: enough to orient without making
        // the rail feel like a launcher dock.
        accentStrip.frame = NSRect(x: -12, y: 9, width: 3, height: max(0, bounds.height - 18))
    }

    func applyTheme() {
        let bg: CGColor
        let border: CGColor
        let glyph: NSColor
        let strip: CGColor
        let badgeFill: CGColor
        let badgeBorder: CGColor
        let badgeText: NSColor

        if isSelected {
            bg = accent.withAlphaComponent(0.14).cgColor
            border = accent.withAlphaComponent(0.48).cgColor
            glyph = accent
            strip = accent.cgColor
            badgeFill = RebrandTokens.Color.windowBg.cgColor
            badgeBorder = accent.withAlphaComponent(0.7).cgColor
            badgeText = accent
            layer?.shadowColor = accent.withAlphaComponent(0.28).cgColor
            layer?.shadowOpacity = 0.26
            layer?.shadowRadius = 8
            layer?.shadowOffset = CGSize(width: 0, height: -1)
        } else if isHovered {
            bg = RebrandTokens.Color.hoverOverlay.withAlphaComponent(0.72).cgColor
            border = RebrandTokens.Color.lineSoft.cgColor
            glyph = RebrandTokens.Color.fg
            strip = NSColor.clear.cgColor
            badgeFill = RebrandTokens.Color.windowBg.cgColor
            badgeBorder = RebrandTokens.Color.line.cgColor
            badgeText = RebrandTokens.Color.fg2
            layer?.shadowOpacity = 0
        } else {
            bg = NSColor.clear.cgColor
            border = NSColor.clear.cgColor
            glyph = RebrandTokens.Color.fg2
            strip = NSColor.clear.cgColor
            badgeFill = RebrandTokens.Color.windowBg.cgColor
            badgeBorder = RebrandTokens.Color.line.cgColor
            badgeText = RebrandTokens.Color.fg4
            layer?.shadowOpacity = 0
        }
        layer?.backgroundColor = bg
        layer?.borderColor = border
        glyphLabel.textColor = glyph
        accentStrip.backgroundColor = strip
        badgeLayer.backgroundColor = badgeFill
        badgeLayer.borderColor = badgeBorder
        badgeLabel.textColor = badgeText
    }
}

/// `+` add tile pinned to the bottom of the rail.
final class RebrandAddTile: NSView {
    private let dashedBorder = CAShapeLayer()
    private let plusIcon = NSImageView()
    private var tracking: NSTrackingArea?
    private var isHovered = false { didSet { applyTheme() } }
    var onClick: (() -> Void)?

    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(dashedBorder)

        plusIcon.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New workspace")
        plusIcon.imageScaling = .scaleProportionallyDown
        addSubview(plusIcon)

        toolTip = "New workspace"
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        if let t = tracking { removeTrackingArea(t) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(a)
        tracking = a
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func layout() {
        super.layout()
        dashedBorder.frame = bounds
        let path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: 7, cornerHeight: 7, transform: nil
        )
        dashedBorder.path = path
        plusIcon.frame = NSRect(
            x: floor((bounds.width - 14) / 2),
            y: floor((bounds.height - 14) / 2),
            width: 14, height: 14
        )
    }

    func applyTheme() {
        dashedBorder.fillColor = NSColor.clear.cgColor
        dashedBorder.lineWidth = 1
        dashedBorder.lineDashPattern = [4, 4]
        dashedBorder.strokeColor = (isHovered
            ? RebrandTokens.Color.lineStrong
            : RebrandTokens.Color.line).cgColor
        plusIcon.contentTintColor = isHovered ? RebrandTokens.Color.fg : RebrandTokens.Color.fg4
    }
}

/// Hue derivation for the rebrand chrome — kept separate from the legacy
/// `WorkspaceTint` so the rebrand can evolve its palette independently.
enum RebrandWorkspaceTint {
    private static let palette: [CGFloat] = [30, 200, 150, 280, 330, 100, 240, 0]

    static func hue(for title: String) -> CGFloat {
        guard !title.isEmpty else { return 200 }
        var h: UInt64 = 5381
        for byte in title.utf8 { h = h &* 33 &+ UInt64(byte) }
        return palette[Int(h % UInt64(palette.count))]
    }

    static func accent(for title: String) -> NSColor {
        NSColor(deviceHue: hue(for: title) / 360, saturation: 0.55, brightness: 0.82, alpha: 1)
    }
}
