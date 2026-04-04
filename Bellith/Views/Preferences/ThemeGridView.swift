import AppKit

// MARK: - Theme Grid

final class ThemeGridView: NSView {
    private let settings: BellithSettings
    private let onApply: () -> Void
    private var cells: [ThemeCell] = []

    init(settings: BellithSettings, onApply: @escaping () -> Void) {
        self.settings = settings
        self.onApply = onApply
        super.init(frame: .zero)
        for theme in ThemeColors.allThemes {
            let cell = ThemeCell(theme: theme, isSelected: theme.name == settings.themeName)
            cell.onSelect = { [weak self] t in
                guard let self else { return }
                self.settings.themeName = t.name
                ThemeManager.shared.apply(t)
                self.refresh()
                self.onApply()
            }
            addSubview(cell)
            cells.append(cell)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        for c in cells { c.isSelected = c.theme.name == settings.themeName; c.needsDisplay = true }
    }

    override func layout() {
        super.layout()
        let cols = 3
        let spacing: CGFloat = 8
        let cellW = (bounds.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let cellH: CGFloat = 54
        for (i, cell) in cells.enumerated() {
            let col = i % cols
            let row = i / cols
            cell.frame = NSRect(
                x: CGFloat(col) * (cellW + spacing),
                y: bounds.height - CGFloat(row + 1) * (cellH + spacing) + spacing,
                width: cellW, height: cellH)
        }
    }
}

final class ThemeCell: NSView {
    let theme: ThemeColors
    var isSelected: Bool
    var onSelect: ((ThemeColors) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private let nameLabel: NSTextField

    init(theme: ThemeColors, isSelected: Bool) {
        self.theme = theme
        self.isSelected = isSelected
        self.nameLabel = NSTextField(labelWithString: theme.name)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        toolTip = theme.name
        nameLabel.font = .systemFont(ofSize: 9.5, weight: .medium)
        nameLabel.textColor = theme.textSecondary
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        nameLabel.frame = NSRect(x: 4, y: 3, width: bounds.width - 8, height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        theme.base.setFill()
        NSBezierPath(roundedRect: b, xRadius: 8, yRadius: 8).fill()

        // Mini terminal preview
        let barInset: CGFloat = 10
        theme.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: barInset, y: 20, width: b.width - barInset * 2, height: 5),
                     xRadius: 2.5, yRadius: 2.5).fill()

        // Dots representing window controls
        let dotR: CGFloat = 2.5
        let dotGap: CGFloat = 7
        let totalDotsW = 3 * (dotR * 2) + 2 * dotGap
        let startX = (b.width - totalDotsW) / 2
        for (i, c) in [theme.textPrimary, theme.textSecondary, theme.textMuted].enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: startX + CGFloat(i) * (dotR * 2 + dotGap), y: b.height - 13, width: dotR * 2, height: dotR * 2)).fill()
        }

        // Selection / hover border
        if isSelected {
            theme.accent.withAlphaComponent(0.8).setStroke()
            let bp = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            bp.lineWidth = 2
            bp.stroke()

            // Checkmark indicator
            let checkSize: CGFloat = 14
            let checkRect = NSRect(x: b.width - checkSize - 4, y: b.height - checkSize - 4, width: checkSize, height: checkSize)
            theme.accent.setFill()
            NSBezierPath(ovalIn: checkRect).fill()
            let checkmark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "selected")
            let config = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
            let tinted = checkmark?.withSymbolConfiguration(config)
            tinted?.draw(in: checkRect.insetBy(dx: 3, dy: 3), from: .zero, operation: .sourceOver, fraction: 1.0)
        } else if isHovered {
            NSColor(white: 1, alpha: 0.15).setStroke()
            let bp = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            bp.lineWidth = 1
            bp.stroke()
        } else {
            NSColor(white: 1, alpha: 0.04).setStroke()
            let bp = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            bp.lineWidth = 0.5
            bp.stroke()
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
}
