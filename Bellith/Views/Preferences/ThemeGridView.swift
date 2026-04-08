import AppKit

// MARK: - Theme Grid

final class ThemeGridView: NSView {
    private let settings: BellithSettings
    private let themeManager: ThemeManager
    private let onApply: () -> Void
    private var cells: [ThemeCell] = []
    private let darkLabel = SectionLabel("DARK")
    private let lightLabel = SectionLabel("LIGHT")

    private let columns = 3
    private let spacing: CGFloat = 10
    private let cellHeight: CGFloat = 78
    private let sectionLabelHeight: CGFloat = 24

    init(settings: BellithSettings, themeManager: ThemeManager = .shared, onApply: @escaping () -> Void) {
        self.settings = settings
        self.themeManager = themeManager
        self.onApply = onApply
        super.init(frame: .zero)
        addSubview(darkLabel)
        addSubview(lightLabel)
        rebuild()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private var darkThemes: [ThemeColors] { ThemeColors.allThemes.filter { !$0.isLight } }
    private var lightThemes: [ThemeColors] { ThemeColors.allThemes.filter { $0.isLight } }

    func refresh() {
        if cells.count != ThemeColors.allThemes.count {
            rebuild()
        }
        for cell in cells {
            if cell.theme.isLight {
                cell.isSelected = cell.theme.name == settings.lightThemeName
            } else {
                cell.isSelected = cell.theme.name == settings.darkThemeName
            }
            cell.needsDisplay = true
        }
    }

    func requiredHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return cellHeight }
        let darkRows = ceil(CGFloat(max(darkThemes.count, 1)) / CGFloat(columns))
        let lightRows = ceil(CGFloat(max(lightThemes.count, 1)) / CGFloat(columns))
        let darkGridH = darkRows * cellHeight + max(0, darkRows - 1) * spacing
        let lightGridH = lightRows * cellHeight + max(0, lightRows - 1) * spacing
        return sectionLabelHeight + darkGridH + sectionLabelHeight + spacing + lightGridH
    }

    private func rebuild() {
        cells.forEach { $0.removeFromSuperview() }
        cells.removeAll()

        for theme in ThemeColors.allThemes {
            let selected: Bool
            if theme.isLight {
                selected = theme.name == settings.lightThemeName
            } else {
                selected = theme.name == settings.darkThemeName
            }
            let cell = ThemeCell(theme: theme, isSelected: selected)
            cell.onSelect = { [weak self] t in
                guard let self else { return }
                if t.isLight {
                    self.settings.lightThemeName = t.name
                } else {
                    self.settings.darkThemeName = t.name
                }
                // Apply immediately if it matches the current system appearance
                if t.isLight == !self.settings.systemIsDark || t.isLight == self.settings.systemIsDark {
                    let resolved = self.settings.resolvedTheme
                    self.themeManager.apply(resolved)
                }
                self.refresh()
                self.onApply()
            }
            addSubview(cell)
            cells.append(cell)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let cellW = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let darkList = darkThemes
        let lightList = lightThemes

        var y: CGFloat = 0

        // Dark section label
        darkLabel.frame = NSRect(x: 0, y: y, width: bounds.width, height: sectionLabelHeight)
        darkLabel.textColor = Theme.textSecondary
        y += sectionLabelHeight

        // Dark theme cells
        let darkCells = cells.filter { !$0.theme.isLight }
        for (i, cell) in darkCells.enumerated() {
            let col = i % columns
            let row = i / columns
            cell.frame = NSRect(
                x: CGFloat(col) * (cellW + spacing),
                y: y + CGFloat(row) * (cellHeight + spacing),
                width: cellW,
                height: cellHeight
            )
        }
        let darkRows = ceil(CGFloat(max(darkList.count, 1)) / CGFloat(columns))
        y += darkRows * cellHeight + max(0, darkRows - 1) * spacing + spacing

        // Light section label
        lightLabel.frame = NSRect(x: 0, y: y, width: bounds.width, height: sectionLabelHeight)
        lightLabel.textColor = Theme.textSecondary
        y += sectionLabelHeight

        // Light theme cells
        let lightCells = cells.filter { $0.theme.isLight }
        for (i, cell) in lightCells.enumerated() {
            let col = i % columns
            let row = i / columns
            cell.frame = NSRect(
                x: CGFloat(col) * (cellW + spacing),
                y: y + CGFloat(row) * (cellHeight + spacing),
                width: cellW,
                height: cellHeight
            )
        }
    }
}

private final class SectionLabel: NSTextField {
    init(_ title: String) {
        super.init(frame: .zero)
        stringValue = title
        font = BellithFont.mono(10, weight: .medium)
        textColor = Theme.textSecondary
        isEditable = false
        isBordered = false
        isSelectable = false
        drawsBackground = false
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

final class ThemeCell: NSView {
    let theme: ThemeColors
    var isSelected: Bool
    var onSelect: ((ThemeColors) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private let nameLabel: NSTextField
    private let metaLabel = NSTextField(labelWithString: "THEME")

    override var acceptsFirstResponder: Bool { true }

    init(theme: ThemeColors, isSelected: Bool) {
        self.theme = theme
        self.isSelected = isSelected
        self.nameLabel = NSTextField(labelWithString: theme.name.uppercased())
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        toolTip = theme.name

        metaLabel.font = BellithFont.mono(10, weight: .regular)
        metaLabel.textColor = theme.textSecondary
        addSubview(metaLabel)

        nameLabel.font = BellithFont.mono(11, weight: .regular)
        nameLabel.textColor = theme.textPrimary
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        metaLabel.frame = NSRect(x: 10, y: bounds.height - 20, width: bounds.width - 20, height: 12)
        nameLabel.frame = NSRect(x: 10, y: 10, width: bounds.width - 20, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        theme.base.setFill()
        NSBezierPath(roundedRect: b, xRadius: 12, yRadius: 12).fill()

        let inset: CGFloat = 10
        let headerRect = NSRect(x: inset, y: b.height - 34, width: b.width - inset * 2, height: 10)
        theme.overlay.setFill()
        NSBezierPath(roundedRect: headerRect, xRadius: 5, yRadius: 5).fill()

        let line1 = NSRect(x: inset, y: 36, width: b.width - inset * 2, height: 6)
        theme.accent.setFill()
        NSBezierPath(roundedRect: line1, xRadius: 3, yRadius: 3).fill()

        let gap: CGFloat = 3
        let segments = 9
        let segmentW = (b.width - inset * 2 - CGFloat(segments - 1) * gap) / CGFloat(segments)
        for idx in 0..<segments {
            let rect = NSRect(x: inset + CGFloat(idx) * (segmentW + gap), y: 24, width: segmentW, height: 6)
            let fill = idx < 6 ? theme.textPrimary : theme.border
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }

        let borderColor: NSColor
        let borderWidth: CGFloat
        if isSelected {
            borderColor = Theme.accent
            borderWidth = 2
        } else if isHovered {
            borderColor = theme.textPrimary.withAlphaComponent(0.28)
            borderWidth = 1
        } else {
            borderColor = theme.border.withAlphaComponent(0.9)
            borderWidth = 0.5
        }
        borderColor.setStroke()
        let bp = NSBezierPath(roundedRect: b.insetBy(dx: borderWidth / 2, dy: borderWidth / 2), xRadius: 12, yRadius: 12)
        bp.lineWidth = borderWidth
        bp.stroke()

        if isSelected {
            let indicatorRect = NSRect(x: b.width - 24, y: 10, width: 14, height: 14)
            Theme.accent.setFill()
            NSBezierPath(ovalIn: indicatorRect).fill()
        }
    }

    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onSelect?(theme) }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36:
            onSelect?(theme)
        default:
            super.keyDown(with: event)
        }
    }
}
