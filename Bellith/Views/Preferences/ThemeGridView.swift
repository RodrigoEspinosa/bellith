import AppKit

private enum ThemeLibraryMode {
    case dark
    case light

    init(segmentIndex: Int) {
        self = segmentIndex == 0 ? .dark : .light
    }

    var segmentIndex: Int {
        switch self {
        case .dark: 0
        case .light: 1
        }
    }

    var showsLightThemes: Bool {
        self == .light
    }

    var hint: String {
        switch self {
        case .dark: "USED WHEN BELLITH IS IN DARK MODE"
        case .light: "USED WHEN BELLITH IS IN LIGHT MODE"
        }
    }
}

// MARK: - Theme Grid

final class ThemeGridView: NSView {
    override var isFlipped: Bool { true }

    private let settings: BellithSettings
    private let themeManager: ThemeManager
    private let onApply: () -> Void
    private var cells: [ThemeCell] = []

    private lazy var modeSegment = PrefSegment(
        labels: ["Dark", "Light"],
        selected: currentMode.segmentIndex
    ) { [weak self] index in
        self?.setMode(ThemeLibraryMode(segmentIndex: index))
    }
    private let modeHintLabel = SectionLabel("")

    private var currentMode: ThemeLibraryMode

    private let columns = 3
    private let spacing: CGFloat = 12
    private let cellHeight: CGFloat = 110
    private let segmentHeight: CGFloat = 32
    private let hintHeight: CGFloat = 16

    init(settings: BellithSettings, themeManager: ThemeManager = .shared, onApply: @escaping () -> Void) {
        self.settings = settings
        self.themeManager = themeManager
        self.onApply = onApply
        currentMode = settings.resolvedIsDark ? .dark : .light
        super.init(frame: .zero)
        addSubview(modeSegment)
        addSubview(modeHintLabel)
        rebuild()
        updateModeUI()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private var visibleThemes: [ThemeColors] {
        ThemeColors.allThemes.filter { $0.isLight == currentMode.showsLightThemes }
    }

    func refresh() {
        if cells.count != ThemeColors.allThemes.count {
            rebuild()
        }
        updateModeUI()
        for cell in cells {
            let isVisible = cell.theme.isLight == currentMode.showsLightThemes
            cell.isHidden = !isVisible
            cell.isSelected = cell.theme.name == selectedThemeName(for: cell.theme)
        }
        needsLayout = true
    }

    func requiredHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return cellHeight + segmentHeight + hintHeight }
        let rows = ceil(CGFloat(max(visibleThemes.count, 1)) / CGFloat(columns))
        let gridHeight = rows * cellHeight + max(0, rows - 1) * spacing
        return segmentHeight + 8 + hintHeight + 10 + gridHeight
    }

    private func rebuild() {
        cells.forEach { $0.removeFromSuperview() }
        cells.removeAll()

        for theme in ThemeColors.allThemes {
            let cell = ThemeCell(theme: theme)
            cell.isSelected = theme.name == selectedThemeName(for: theme)
            cell.onSelect = { [weak self] selectedTheme in
                self?.applyThemeSelection(selectedTheme)
            }
            addSubview(cell)
            cells.append(cell)
        }
        refresh()
    }

    private func applyThemeSelection(_ theme: ThemeColors) {
        if theme.isLight {
            settings.lightThemeName = theme.name
        } else {
            settings.darkThemeName = theme.name
        }

        if theme.isLight == !settings.resolvedIsDark {
            themeManager.apply(settings.resolvedTheme)
        }

        refresh()
        onApply()
    }

    private func selectedThemeName(for theme: ThemeColors) -> String {
        theme.isLight ? settings.lightThemeName : settings.darkThemeName
    }

    private func setMode(_ mode: ThemeLibraryMode) {
        guard currentMode != mode else { return }
        currentMode = mode
        refresh()
    }

    private func updateModeUI() {
        modeSegment.setSelected(currentMode.segmentIndex)
        modeHintLabel.stringValue = currentMode.hint
        modeHintLabel.textColor = Theme.textSecondary
    }

    override func layout() {
        super.layout()

        modeSegment.frame = NSRect(x: 0, y: 0, width: 168, height: segmentHeight)
        modeHintLabel.frame = NSRect(x: 0, y: modeSegment.frame.maxY + 8, width: bounds.width, height: hintHeight)

        let visibleCells = cells.filter { $0.theme.isLight == currentMode.showsLightThemes }
        let cellWidth = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let gridY = modeHintLabel.frame.maxY + 10

        for cell in cells {
            cell.isHidden = cell.theme.isLight != currentMode.showsLightThemes
        }

        for (index, cell) in visibleCells.enumerated() {
            let column = index % columns
            let row = index / columns
            cell.frame = NSRect(
                x: CGFloat(column) * (cellWidth + spacing),
                y: gridY + CGFloat(row) * (cellHeight + spacing),
                width: cellWidth,
                height: cellHeight
            )
        }
    }
}

private final class SectionLabel: NSTextField {
    init(_ title: String) {
        super.init(frame: .zero)
        stringValue = title
        font = BellithFont.mono(9, weight: .regular)
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
    var isSelected: Bool = false {
        didSet {
            updateAccessibilityValue()
            needsDisplay = true
        }
    }
    var onSelect: ((ThemeColors) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private let nameLabel: NSTextField
    private let metaLabel = NSTextField(labelWithString: "THEME")
    private let statusText = "DEFAULT"

    override var acceptsFirstResponder: Bool { true }

    private var isFocused: Bool {
        window?.firstResponder as AnyObject? === self
    }

    init(theme: ThemeColors) {
        self.theme = theme
        self.nameLabel = NSTextField(labelWithString: theme.name.uppercased())
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        toolTip = theme.name

        setAccessibilityRole(.button)
        setAccessibilityLabel("\(theme.name) theme")

        metaLabel.font = BellithFont.mono(10, weight: .regular)
        metaLabel.textColor = theme.textSecondary
        addSubview(metaLabel)

        nameLabel.font = BellithFont.mono(10.5, weight: .regular)
        nameLabel.textColor = theme.textPrimary
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        updateAccessibilityValue()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        metaLabel.frame = NSRect(x: 12, y: bounds.height - 22, width: 80, height: 12)
        nameLabel.frame = NSRect(x: 12, y: 8, width: bounds.width - 24, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        let boundsPath = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        theme.base.setFill()
        boundsPath.fill()

        let inset: CGFloat = 12
        let topBar = NSRect(x: inset, y: bounds.height - 40, width: bounds.width - inset * 2, height: 12)
        theme.overlay.setFill()
        NSBezierPath(roundedRect: topBar, xRadius: 6, yRadius: 6).fill()

        theme.textSecondary.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: NSRect(x: inset, y: 68, width: bounds.width * 0.46, height: 7), xRadius: 3.5, yRadius: 3.5).fill()
        NSBezierPath(roundedRect: NSRect(x: inset, y: 54, width: bounds.width * 0.66, height: 7), xRadius: 3.5, yRadius: 3.5).fill()

        theme.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: inset, y: 38, width: bounds.width - inset * 2, height: 8), xRadius: 4, yRadius: 4).fill()

        let gap: CGFloat = 3
        let segments = 9
        let segmentWidth = (bounds.width - inset * 2 - CGFloat(segments - 1) * gap) / CGFloat(segments)
        for index in 0..<segments {
            let rect = NSRect(x: inset + CGFloat(index) * (segmentWidth + gap), y: 24, width: segmentWidth, height: 6)
            let fill = index < 6 ? theme.textPrimary : theme.border
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }

        let borderColor: NSColor
        let borderWidth: CGFloat
        if isSelected {
            borderColor = theme.isLight ? NSColor(white: 0.12, alpha: 0.42) : NSColor(white: 1.0, alpha: 0.88)
            borderWidth = 1.5
        } else if isFocused {
            borderColor = Theme.focusRing
            borderWidth = 1.5
        } else if isHovered {
            borderColor = theme.textPrimary.withAlphaComponent(0.24)
            borderWidth = 1
        } else {
            borderColor = theme.border.withAlphaComponent(min(1, theme.border.alphaComponent * 1.4))
            borderWidth = 0.75
        }
        borderColor.setStroke()
        let borderPath = NSBezierPath(
            roundedRect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
            xRadius: 14,
            yRadius: 14
        )
        borderPath.lineWidth = borderWidth
        borderPath.stroke()

        if isSelected {
            let chipRect = NSRect(x: bounds.width - 78, y: bounds.height - 24, width: 66, height: 16)
            borderColor.withAlphaComponent(theme.isLight ? 0.12 : 0.18).setFill()
            NSBezierPath(roundedRect: chipRect, xRadius: 8, yRadius: 8).fill()

            borderColor.withAlphaComponent(theme.isLight ? 0.18 : 0.28).setStroke()
            let chipBorder = NSBezierPath(roundedRect: chipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            chipBorder.lineWidth = 1
            chipBorder.stroke()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: BellithFont.mono(8.5, weight: .medium),
                .foregroundColor: theme.isLight ? theme.textPrimary : NSColor.white,
            ]
            let text = statusText as NSString
            let textSize = text.size(withAttributes: attrs)
            let textOrigin = NSPoint(
                x: chipRect.midX - textSize.width / 2,
                y: chipRect.midY - textSize.height / 2 - 0.5
            )
            text.draw(at: textOrigin, withAttributes: attrs)
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
        onSelect?(theme)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36:
            onSelect?(theme)
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
        setAccessibilityValue(isSelected ? "Default theme" : "Not default")
    }
}
