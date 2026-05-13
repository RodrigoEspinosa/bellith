import AppKit

// MARK: - Accent Palette Grid

final class AccentPaletteGridView: NSView {
    override var isFlipped: Bool { true }

    private let settings: BellithSettings
    private let themeManager: ThemeManager
    private let onApply: () -> Void
    private var cells: [AccentPaletteCell] = []

    private let columns = 3
    private let spacing: CGFloat = 12
    private let cellHeight: CGFloat = 104

    init(settings: BellithSettings, themeManager: ThemeManager = .shared, onApply: @escaping () -> Void) {
        self.settings = settings
        self.themeManager = themeManager
        self.onApply = onApply
        super.init(frame: .zero)
        rebuild()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        for cell in cells {
            cell.isSelected = cell.palette.id == settings.appearancePaletteID
        }
        needsLayout = true
    }

    func requiredHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return cellHeight }
        let rows = ceil(CGFloat(max(AppearancePalette.all.count, 1)) / CGFloat(columns))
        return rows * cellHeight + max(0, rows - 1) * spacing
    }

    private func rebuild() {
        cells.forEach { $0.removeFromSuperview() }
        cells.removeAll()

        for palette in AppearancePalette.all {
            let cell = AccentPaletteCell(palette: palette)
            cell.isSelected = palette.id == settings.appearancePaletteID
            cell.onSelect = { [weak self] selectedPalette in
                self?.applyPaletteSelection(selectedPalette)
            }
            addSubview(cell)
            cells.append(cell)
        }
        refresh()
    }

    private func applyPaletteSelection(_ palette: AppearancePalette) {
        settings.appearancePaletteID = palette.id
        themeManager.apply(settings.resolvedTheme)
        refresh()
        onApply()
    }

    override func layout() {
        super.layout()

        let cellWidth = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        for (index, cell) in cells.enumerated() {
            let column = index % columns
            let row = index / columns
            cell.frame = NSRect(
                x: CGFloat(column) * (cellWidth + spacing),
                y: CGFloat(row) * (cellHeight + spacing),
                width: cellWidth,
                height: cellHeight
            )
        }
    }
}

final class AccentPaletteCell: NSView {
    let palette: AppearancePalette
    var isSelected: Bool = false {
        didSet {
            updateAccessibilityValue()
            needsDisplay = true
        }
    }
    var onSelect: ((AppearancePalette) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private let nameLabel: NSTextField
    private let metaLabel = NSTextField(labelWithString: "ACCENT")
    private let statusText = "ACTIVE"

    override var acceptsFirstResponder: Bool { true }

    private var isFocused: Bool {
        window?.firstResponder as AnyObject? === self
    }

    init(palette: AppearancePalette) {
        self.palette = palette
        self.nameLabel = NSTextField(labelWithString: palette.displayName)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        toolTip = palette.name

        setAccessibilityRole(.button)
        setAccessibilityLabel("\(palette.name) accent color")

        metaLabel.font = BellithFont.mono(10, weight: .regular)
        metaLabel.textColor = Theme.textSecondary
        addSubview(metaLabel)

        nameLabel.font = BellithFont.mono(10.5, weight: .regular)
        nameLabel.textColor = Theme.textPrimary
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        updateAccessibilityValue()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        metaLabel.frame = NSRect(x: 12, y: bounds.height - 22, width: 80, height: 12)
        nameLabel.frame = NSRect(x: 12, y: 9, width: bounds.width - 24, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        let isDark = BellithSettings.shared.resolvedIsDark
        let preview = ThemeColors.appearance(palette: palette, isDark: isDark)
        let boundsPath = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        preview.base.setFill()
        boundsPath.fill()

        let inset: CGFloat = 12
        let topBar = NSRect(x: inset, y: bounds.height - 38, width: bounds.width - inset * 2, height: 12)
        preview.overlay.setFill()
        NSBezierPath(roundedRect: topBar, xRadius: 6, yRadius: 6).fill()

        palette.accent.withAlphaComponent(isDark ? 0.95 : 0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: inset, y: 48, width: bounds.width - inset * 2, height: 8), xRadius: 4, yRadius: 4).fill()

        palette.secondaryAccent.withAlphaComponent(isDark ? 0.95 : 0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: inset, y: 33, width: bounds.width * 0.58, height: 8), xRadius: 4, yRadius: 4).fill()

        preview.textSecondary.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: NSRect(x: inset, y: 64, width: bounds.width * 0.44, height: 7), xRadius: 3.5, yRadius: 3.5).fill()

        let borderColor: NSColor
        let borderWidth: CGFloat
        if isSelected {
            borderColor = preview.accent
            borderWidth = 1.5
        } else if isFocused {
            borderColor = Theme.focusRing
            borderWidth = 1.5
        } else if isHovered {
            borderColor = preview.textPrimary.withAlphaComponent(0.24)
            borderWidth = 1
        } else {
            borderColor = preview.border.withAlphaComponent(min(1, preview.border.alphaComponent * 1.6))
            borderWidth = 0.75
        }
        borderColor.setStroke()
        let borderPath = NSBezierPath(
            roundedRect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
            xRadius: 12,
            yRadius: 12
        )
        borderPath.lineWidth = borderWidth
        borderPath.stroke()

        if isSelected {
            let chipRect = NSRect(x: bounds.width - 70, y: bounds.height - 24, width: 58, height: 16)
            borderColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: chipRect, xRadius: 8, yRadius: 8).fill()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: BellithFont.mono(8.5, weight: .medium),
                .foregroundColor: preview.textPrimary,
            ]
            let text = statusText as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(
                at: NSPoint(x: chipRect.midX - textSize.width / 2, y: chipRect.midY - textSize.height / 2 - 0.5),
                withAttributes: attrs
            )
        }
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onSelect?(palette)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36:
            onSelect?(palette)
        default:
            super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    private func updateAccessibilityValue() {
        setAccessibilityValue(isSelected ? "Active accent color" : "Not active")
    }
}
