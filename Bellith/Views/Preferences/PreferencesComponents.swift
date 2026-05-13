import AppKit

// MARK: - Layout Constants

enum PreferencesLayout {
    typealias DS = BellithDesignSystem

    static let hPad: CGFloat = DS.Settings.horizontalPadding
    static let rowH: CGFloat = DS.Size.rowHeight
    static let sectionGap: CGFloat = DS.Settings.sectionGap
    static let rowGap: CGFloat = DS.Settings.rowGap
    static let cardPad: CGFloat = DS.Settings.cardPadding
    static let cardRadius: CGFloat = DS.Radius.card
    static let controlGap: CGFloat = DS.Settings.controlGap
    static let toggleW: CGFloat = DS.Size.toggleWidth
    static let toggleH: CGFloat = DS.Size.toggleHeight

    static func trailingToggleX(cardWidth: CGFloat) -> CGFloat {
        DS.Settings.trailingControlX(cardWidth: cardWidth, controlWidth: toggleW)
    }

    static func trailingToggleFrame(cardWidth: CGFloat, rowY: CGFloat) -> NSRect {
        DS.Settings.trailingControlFrame(
            cardWidth: cardWidth,
            rowY: rowY,
            controlWidth: toggleW,
            controlHeight: toggleH
        )
    }

    static func labelWidth(toTrailingToggleIn cardWidth: CGFloat, from x: CGFloat = cardPad, gap: CGFloat = controlGap) -> CGFloat {
        DS.Settings.labelWidth(cardWidth: cardWidth, from: x, trailingControlWidth: toggleW, gap: gap)
    }
}

// MARK: - Card Container (grouped section)

final class SettingsCard: NSView {
    private let titleLabel: NSTextField?
    private let subtitleLabel: NSTextField?

    init(title: String? = nil, subtitle: String? = nil) {
        if let title {
            titleLabel = NSTextField(labelWithString: title.uppercased())
            titleLabel!.font = BellithDesignSystem.Typography.sectionTitle()
            titleLabel!.textColor = BellithDesignSystem.Color.textSecondary
        } else { titleLabel = nil }
        if let subtitle {
            subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel!.font = BellithDesignSystem.Typography.caption()
            subtitleLabel!.textColor = Theme.textTertiary
        } else { subtitleLabel = nil }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = BellithDesignSystem.Radius.card
        layer?.borderWidth = 0.5
        layer?.borderColor = BellithDesignSystem.Color.strokeStrong.cgColor
        layer?.backgroundColor = BellithDesignSystem.Color.cardBackground.cgColor
        if let t = titleLabel { addSubview(t) }
        if let s = subtitleLabel { addSubview(s) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    var headerHeight: CGFloat {
        if titleLabel != nil && subtitleLabel != nil { return 50 }
        if titleLabel != nil { return 38 }
        return 0
    }

    func refresh() {
        layer?.borderColor = BellithDesignSystem.Color.strokeStrong.cgColor
        layer?.backgroundColor = BellithDesignSystem.Color.cardBackground.cgColor
        titleLabel?.textColor = BellithDesignSystem.Color.textSecondary
        subtitleLabel?.textColor = Theme.textTertiary
    }

    override func layout() {
        super.layout()
        if let t = titleLabel {
            let y: CGFloat = subtitleLabel != nil ? bounds.height - 28 : bounds.height - 30
            t.frame = NSRect(x: BellithDesignSystem.Settings.cardPadding, y: y, width: bounds.width - BellithDesignSystem.Settings.cardPadding * 2, height: 16)
        }
        if let s = subtitleLabel {
            s.frame = NSRect(x: BellithDesignSystem.Settings.cardPadding, y: bounds.height - 44, width: bounds.width - BellithDesignSystem.Settings.cardPadding * 2, height: 14)
        }
    }

    override func draw(_ dirtyRect: NSRect) {}
}

// MARK: - Shortcut Badge (click to record)

final class ShortcutBadge: NSView {
    var onNewShortcut: ((KeyShortcut?) -> Void)?
    private var shortcut: KeyShortcut?
    private var isRecording = false
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private let recordingLabel = NSTextField(labelWithString: "")
    private let emptyLabel = "Unassigned"

    override var mouseDownCanMoveWindow: Bool { false }

    init(shortcut: KeyShortcut?) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        wantsLayer = true

        recordingLabel.font = BellithFont.mono(11, weight: .regular)
        recordingLabel.textColor = Theme.accent
        recordingLabel.alignment = .center
        recordingLabel.isEditable = false
        recordingLabel.isBezeled = false
        recordingLabel.drawsBackground = false
        recordingLabel.isHidden = true
        addSubview(recordingLabel)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        recordingLabel.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        if isRecording {
            Theme.accent.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
            Theme.accent.withAlphaComponent(0.3).setStroke()
            let bp = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            bp.lineWidth = 1.5
            bp.setLineDash([4, 3], count: 2, phase: 0)
            bp.stroke()
            return
        }

        guard let shortcut else {
            let rect = bounds.insetBy(dx: 0, dy: 3)
            let fill = isHovered ? Theme.chromeElevated : Theme.frame.withAlphaComponent(0.9)
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()

            Theme.border.setStroke()
            let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            borderPath.lineWidth = 0.5
            borderPath.stroke()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: BellithFont.mono(11, weight: .regular),
                .foregroundColor: Theme.textMuted,
            ]
            let size = (emptyLabel as NSString).size(withAttributes: attrs)
            let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
            (emptyLabel as NSString).draw(at: origin, withAttributes: attrs)
            return
        }

        let keys = shortcut.keycapStrings
        let font = BellithFont.mono(11, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.textSecondary]

        let capH: CGFloat = 22
        let capPad: CGFloat = 7
        let capGap: CGFloat = 3
        let capR: CGFloat = 5

        var totalW: CGFloat = 0
        var widths: [CGFloat] = []
        for key in keys {
            let size = (key as NSString).size(withAttributes: attrs)
            let w = max(22, size.width + capPad * 2)
            widths.append(w)
            totalW += w
        }
        totalW += CGFloat(max(0, keys.count - 1)) * capGap

        var x = bounds.width - totalW
        let y = (bounds.height - capH) / 2

        for (i, key) in keys.enumerated() {
            let w = widths[i]
            let capRect = NSRect(x: x, y: y, width: w, height: capH)

            let capBg = isHovered ? Theme.chromeElevated : Theme.frame.withAlphaComponent(0.95)
            capBg.setFill()
            NSBezierPath(roundedRect: capRect, xRadius: capR, yRadius: capR).fill()

            Theme.border.setStroke()
            let borderPath = NSBezierPath(roundedRect: capRect.insetBy(dx: 0.5, dy: 0.5), xRadius: capR, yRadius: capR)
            borderPath.lineWidth = 0.5
            borderPath.stroke()

            let shadowRect = NSRect(x: capRect.minX + 2, y: capRect.maxY - 1, width: capRect.width - 4, height: 1)
            NSColor(white: 0, alpha: 0.15).setFill()
            NSBezierPath(roundedRect: shadowRect, xRadius: 0.5, yRadius: 0.5).fill()

            let textSize = (key as NSString).size(withAttributes: attrs)
            let textX = capRect.midX - textSize.width / 2
            let textY = capRect.midY - textSize.height / 2
            (key as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

            x += w + capGap
        }
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        recordingLabel.stringValue = "Press shortcut\u{2026}"
        recordingLabel.isHidden = false
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { cancelRecording(); return }
        if event.keyCode == 51 || event.keyCode == 117 {
            shortcut = nil
            isRecording = false
            recordingLabel.isHidden = true
            needsDisplay = true
            onNewShortcut?(nil)
            return
        }
        if let newShortcut = KeyShortcut.from(event: event) {
            shortcut = newShortcut
            isRecording = false
            recordingLabel.isHidden = true
            needsDisplay = true
            onNewShortcut?(newShortcut)
        }
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { cancelRecording() }
        return super.resignFirstResponder()
    }

    private func cancelRecording() {
        isRecording = false
        recordingLabel.isHidden = true
        needsDisplay = true
    }

    func setShortcut(_ newShortcut: KeyShortcut?) {
        shortcut = newShortcut
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
}

// MARK: - Shared Components

// Card row label (used inside cards)
final class CardRowLabel: NSTextField {
    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text.uppercased()
        font = BellithDesignSystem.Typography.rowLabel()
        textColor = BellithDesignSystem.Color.textSecondary
        isEditable = false; isBezeled = false; drawsBackground = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

// Small inline label
final class SmallLabel: NSTextField {
    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text.uppercased()
        font = BellithFont.mono(10, weight: .regular)
        textColor = Theme.textTertiary
        isEditable = false; isBezeled = false; drawsBackground = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

// Footer note
final class FooterNote: NSTextField {
    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text
        font = BellithFont.mono(10, weight: .regular)
        textColor = Theme.textTertiary
        isEditable = false; isBezeled = false; drawsBackground = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

// Value badge (centered number)
final class ValueBadge: NSTextField {
    init() {
        super.init(frame: .zero)
        font = BellithDesignSystem.Typography.value()
        textColor = BellithDesignSystem.Color.text
        alignment = .center
        isEditable = false; isBezeled = false; drawsBackground = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Custom Segmented Control

final class PrefSegment: NSView {
    private var selected: Int
    private let onChange: (Int) -> Void
    private var buttons: [NSButton] = []

    override var acceptsFirstResponder: Bool { true }

    private var selectedFillColor: NSColor {
        if Theme.colors.isLight {
            return NSColor(white: 0.94, alpha: 1.0)
        }
        return Theme.chromeElevated
    }

    private var selectedTextColor: NSColor {
        Theme.textPrimary
    }

    init(labels: [String], selected: Int, onChange: @escaping (Int) -> Void) {
        self.selected = selected
        self.onChange = onChange
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = Theme.frame.cgColor
        layer?.borderColor = Theme.chromeHairline.cgColor
        layer?.borderWidth = 0.5

        for (i, title) in labels.enumerated() {
            let btn = NSButton(title: title.uppercased(), target: self, action: #selector(tapped(_:)))
            btn.tag = i
            btn.isBordered = false
            btn.font = BellithFont.mono(11, weight: .regular)
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            addSubview(btn)
            buttons.append(btn)
        }
        updateAppearance()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let count = CGFloat(buttons.count)
        let inset: CGFloat = 3
        let btnW = (bounds.width - inset * 2) / count
        for (i, btn) in buttons.enumerated() {
            btn.frame = NSRect(x: inset + CGFloat(i) * btnW, y: inset, width: btnW, height: bounds.height - inset * 2)
        }
    }

    @objc private func tapped(_ sender: NSButton) {
        selected = sender.tag
        updateAppearance()
        onChange(selected)
    }

    func setSelected(_ newValue: Int) {
        selected = newValue
        updateAppearance()
    }

    func refreshAppearance() {
        updateAppearance()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            setSelected(max(0, selected - 1))
            onChange(selected)
        case 124:
            setSelected(min(buttons.count - 1, selected + 1))
            onChange(selected)
        case 49, 36:
            onChange(selected)
        default:
            super.keyDown(with: event)
        }
    }

    private func updateAppearance() {
        layer?.backgroundColor = Theme.frame.cgColor
        layer?.borderColor = Theme.chromeHairline.cgColor

        for (i, btn) in buttons.enumerated() {
            if i == selected {
                btn.contentTintColor = selectedTextColor
                btn.layer?.backgroundColor = selectedFillColor.cgColor
                btn.layer?.borderWidth = Theme.colors.isLight ? 0.5 : 0
                btn.layer?.borderColor = Theme.border.cgColor
            } else {
                btn.contentTintColor = Theme.textSecondary
                btn.layer?.backgroundColor = .clear
                btn.layer?.borderWidth = 0
                btn.layer?.borderColor = NSColor.clear.cgColor
            }
        }
    }
}

// MARK: - Custom Toggle

final class PrefToggle: NSView {
    private var isOn: Bool
    private let onChange: (Bool) -> Void
    private let trackLayer = CALayer()

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    private let knobLayer = CALayer()
    private let knobShadowLayer = CALayer()

    private let trackW: CGFloat = BellithDesignSystem.Size.toggleWidth
    private let trackH: CGFloat = BellithDesignSystem.Size.toggleHeight
    private let knobD: CGFloat = 18
    private let knobInset: CGFloat = 3

    init(isOn: Bool, onChange: @escaping (Bool) -> Void) {
        self.isOn = isOn
        self.onChange = onChange
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        // Track
        trackLayer.cornerRadius = trackH / 2
        trackLayer.borderWidth = isOn ? 0 : 0.5
        trackLayer.borderColor = BellithDesignSystem.Color.stroke.cgColor
        layer?.addSublayer(trackLayer)

        // Knob shadow
        knobShadowLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(knobShadowLayer)

        // Knob
        knobLayer.backgroundColor = BellithDesignSystem.Color.windowBackground.cgColor
        layer?.addSublayer(knobLayer)

        updateLayers(animated: false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let trackY = (bounds.height - trackH) / 2
        trackLayer.frame = NSRect(x: 0, y: trackY, width: trackW, height: trackH)
        updateKnobPosition(animated: false)
    }

    private func updateLayers(animated: Bool) {
        trackLayer.borderColor = BellithDesignSystem.Color.stroke.cgColor
        knobLayer.backgroundColor = BellithDesignSystem.Color.windowBackground.cgColor

        let color: NSColor
        if isOn {
            color = BellithDesignSystem.Color.toggleOn
        } else {
            color = BellithDesignSystem.Color.toggleOff
        }

        if animated {
            let colorAnim = CABasicAnimation(keyPath: "backgroundColor")
            colorAnim.fromValue = trackLayer.backgroundColor
            colorAnim.toValue = color.cgColor
            colorAnim.duration = 0.18
            colorAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            trackLayer.add(colorAnim, forKey: "backgroundColor")

            let borderAnim = CABasicAnimation(keyPath: "borderWidth")
            borderAnim.fromValue = trackLayer.borderWidth
            borderAnim.toValue = isOn ? 0 : 0.5
            borderAnim.duration = 0.18
            borderAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            trackLayer.add(borderAnim, forKey: "borderWidth")
        }

        trackLayer.backgroundColor = color.cgColor
        trackLayer.borderWidth = isOn ? 0 : 0.5

        updateKnobPosition(animated: animated)
    }

    private func updateKnobPosition(animated: Bool) {
        let trackY = (bounds.height - trackH) / 2
        let knobX: CGFloat = isOn ? trackW - knobD - knobInset : knobInset
        let knobY = trackY + (trackH - knobD) / 2
        let knobFrame = NSRect(x: knobX, y: knobY, width: knobD, height: knobD)
        let shadowFrame = NSRect(x: knobX, y: knobY - 1, width: knobD, height: knobD)

        if animated {
            let posAnim = CABasicAnimation(keyPath: "position")
            posAnim.fromValue = NSValue(point: NSPoint(x: knobLayer.frame.midX, y: knobLayer.frame.midY))
            posAnim.toValue = NSValue(point: NSPoint(x: knobFrame.midX, y: knobFrame.midY))
            posAnim.duration = 0.18
            posAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            knobLayer.add(posAnim, forKey: "position")
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knobLayer.frame = knobFrame
        knobLayer.cornerRadius = knobD / 2
        knobShadowLayer.frame = shadowFrame
        knobShadowLayer.cornerRadius = knobD / 2
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        toggle()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36:
            toggle()
        default:
            super.keyDown(with: event)
        }
    }

    func setOn(_ newValue: Bool, animated: Bool = false) {
        isOn = newValue
        updateLayers(animated: animated)
    }

    func refreshAppearance() {
        updateLayers(animated: false)
    }

    private func toggle() {
        isOn.toggle()
        onChange(isOn)
        updateLayers(animated: true)
    }
}

// MARK: - Custom Opacity Track

final class OpacityTrackView: NSView {
    private var value: Double
    private let minValue: Double
    private let onChange: (Double) -> Void
    private let percentLabel: NSTextField

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(value: Double, minValue: Double = 0.3, onChange: @escaping (Double) -> Void) {
        self.value = value
        self.minValue = minValue
        self.onChange = onChange
        self.percentLabel = NSTextField(labelWithString: "\(Int(value * 100))%")
        super.init(frame: .zero)
        wantsLayer = true
        percentLabel.font = BellithFont.mono(10, weight: .regular)
        percentLabel.textColor = Theme.textSecondary
        percentLabel.alignment = .right
        addSubview(percentLabel)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        percentLabel.frame = NSRect(x: bounds.width - 38, y: (bounds.height - 14) / 2, width: 38, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackW = bounds.width - 52
        let segments = max(10, Int(trackW / 14))
        let gap: CGFloat = 2
        let segmentW = max(6, (trackW - CGFloat(segments - 1) * gap) / CGFloat(segments))
        let trackH: CGFloat = 10
        let trackY = (bounds.height - trackH) / 2
        let filledCount = Int(round(CGFloat(value) * CGFloat(segments)))

        for index in 0..<segments {
            let rect = NSRect(x: CGFloat(index) * (segmentW + gap), y: trackY, width: segmentW, height: trackH)
            let color = index < filledCount ? Theme.textDisplay : Theme.border
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }

        let markerX = min(trackW - 1, max(0, (segmentW + gap) * CGFloat(filledCount) - gap / 2))
        Theme.textSecondary.withAlphaComponent(0.55).setFill()
        NSBezierPath(rect: NSRect(x: markerX, y: trackY - 4, width: 1, height: trackH + 8)).fill()
    }

    override func mouseDown(with event: NSEvent) { updateValue(from: event) }
    override func mouseDragged(with event: NSEvent) { updateValue(from: event) }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            setValue(value - 0.05)
            onChange(value)
        case 124:
            setValue(value + 0.05)
            onChange(value)
        default:
            super.keyDown(with: event)
        }
    }

    func setValue(_ newValue: Double) {
        value = min(1.0, max(minValue, newValue))
        percentLabel.stringValue = "\(Int(value * 100))%"
        needsDisplay = true
    }

    private func updateValue(from event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let trackW = bounds.width - 52
        setValue(Double(loc.x / trackW))
        onChange(value)
    }
}

// MARK: - Text Field

final class PrefTextField: NSView {
    private let field: NSTextField
    private let onChange: (String) -> Void

    init(text: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        self.field = NSTextField(string: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = BellithDesignSystem.Radius.controlLarge
        layer?.backgroundColor = BellithDesignSystem.Color.controlBackground.cgColor
        layer?.borderColor = BellithDesignSystem.Color.stroke.cgColor
        layer?.borderWidth = 0.5

        field.font = BellithDesignSystem.Typography.field()
        field.textColor = BellithDesignSystem.Color.text
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.target = self
        field.action = #selector(edited)
        addSubview(field)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        field.frame = bounds.insetBy(dx: 10, dy: 4)
    }

    @objc private func edited() { onChange(field.stringValue) }

    func updateText(_ text: String) {
        layer?.backgroundColor = BellithDesignSystem.Color.controlBackground.cgColor
        layer?.borderColor = BellithDesignSystem.Color.stroke.cgColor
        field.textColor = BellithDesignSystem.Color.text
        field.stringValue = text
    }
}

// MARK: - Mini Number Field

final class MiniNumberField: NSView {
    private let field: NSTextField
    private let range: ClosedRange<Int>
    private let onChange: (Int) -> Void

    init(value: Int, range: ClosedRange<Int>, onChange: @escaping (Int) -> Void) {
        self.range = range
        self.onChange = onChange
        self.field = NSTextField(string: "\(value)")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = BellithDesignSystem.Radius.control
        layer?.backgroundColor = BellithDesignSystem.Color.controlBackground.cgColor
        layer?.borderColor = BellithDesignSystem.Color.stroke.cgColor
        layer?.borderWidth = 0.5

        field.font = BellithDesignSystem.Typography.numericField()
        field.textColor = BellithDesignSystem.Color.text
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.alignment = .center
        field.target = self
        field.action = #selector(edited)
        addSubview(field)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        field.frame = bounds.insetBy(dx: 4, dy: 4)
    }

    @objc private func edited() {
        let val = max(range.lowerBound, min(range.upperBound, Int(field.stringValue) ?? range.lowerBound))
        field.stringValue = "\(val)"
        onChange(val)
    }

    func setValue(_ value: Int) {
        layer?.backgroundColor = BellithDesignSystem.Color.controlBackground.cgColor
        layer?.borderColor = BellithDesignSystem.Color.stroke.cgColor
        field.textColor = BellithDesignSystem.Color.text
        field.stringValue = "\(max(range.lowerBound, min(range.upperBound, value)))"
    }
}

// MARK: - Step Button

final class StepButton: NSView {
    private let action: () -> Void
    private let symbol: NSImage?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(symbol name: String, action: @escaping () -> Void) {
        self.action = action
        self.symbol = NSImage(systemSymbolName: name, accessibilityDescription: name)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = BellithDesignSystem.Radius.control
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        (isHovered ? BellithDesignSystem.Color.controlBackgroundHover : BellithDesignSystem.Color.controlBackground).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: BellithDesignSystem.Radius.control, yRadius: BellithDesignSystem.Radius.control).fill()
        BellithDesignSystem.Color.stroke.setStroke()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: BellithDesignSystem.Radius.control,
            yRadius: BellithDesignSystem.Radius.control
        ).stroke()

        if let img = symbol {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            let tinted = img.withSymbolConfiguration(config)
            let s: CGFloat = 14
            tinted?.draw(in: NSRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s),
                         from: .zero, operation: .sourceOver, fraction: isHovered ? 0.9 : 0.5)
        }
    }

    override func mouseDown(with event: NSEvent) { action() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36:
            action()
        default:
            super.keyDown(with: event)
        }
    }
    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
}

// MARK: - Link Button

final class LinkButton: NSView {
    var onClick: (() -> Void)?
    private let label: NSTextField
    private let arrow: NSImageView
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(title: String) {
        label = NSTextField(labelWithString: title.uppercased())
        arrow = NSImageView()
        super.init(frame: .zero)

        label.font = BellithFont.mono(11, weight: .regular)
        label.textColor = Theme.textSecondary
        addSubview(label)

        arrow.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)
        arrow.contentTintColor = Theme.textTertiary
        arrow.imageScaling = .scaleProportionallyDown
        addSubview(arrow)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: 0, width: bounds.width - 20, height: bounds.height)
        arrow.frame = NSRect(x: bounds.width - 16, y: (bounds.height - 12) / 2, width: 12, height: 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            Theme.textSecondary.withAlphaComponent(0.3).setFill()
            let underline = NSRect(x: 0, y: 0, width: label.attributedStringValue.size().width, height: 1)
            underline.fill()
        }
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36:
            onClick?()
        default:
            super.keyDown(with: event)
        }
    }
    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        label.textColor = Theme.textPrimary
        arrow.contentTintColor = Theme.textSecondary
        NSCursor.pointingHand.push()
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        label.textColor = Theme.textSecondary
        arrow.contentTintColor = Theme.textTertiary
        NSCursor.pop()
        needsDisplay = true
    }
}

// MARK: - Font Picker Button

final class FontPickerButton: NSView {
    var onFontPicked: ((String) -> Void)?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    private let settings: BellithSettings

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(frame frameRect: NSRect = .zero, settings: BellithSettings = .shared) {
        self.settings = settings
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        toolTip = "Choose font\u{2026}"
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        (isHovered ? Theme.chromeElevated : Theme.frame).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        Theme.border.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()

        if bounds.width >= 68 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: BellithFont.mono(10, weight: .regular),
                .foregroundColor: isHovered ? Theme.textPrimary : Theme.textSecondary,
            ]
            let title = "CHOOSE" as NSString
            let size = title.size(withAttributes: attrs)
            let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
            title.draw(at: point, withAttributes: attrs)
        } else if let img = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Choose font") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            let tinted = img.withSymbolConfiguration(config)
            let s: CGFloat = 14
            tinted?.draw(in: NSRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s),
                         from: .zero, operation: .sourceOver, fraction: isHovered ? 0.9 : 0.5)
        }
    }

    override func mouseDown(with event: NSEvent) {
        presentFontPanel()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36:
            presentFontPanel()
        default:
            super.keyDown(with: event)
        }
    }

    private func presentFontPanel() {
        let panel = NSFontPanel.shared
        panel.setPanelFont(NSFont(name: settings.fontFamily, size: CGFloat(settings.fontSize))
                           ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), isMultiple: false)
        panel.makeKeyAndOrderFront(nil)

        // Use a delegate proxy to receive font change
        FontPanelDelegate.shared.onFontChange = { [weak self] font in
            self?.onFontPicked?(font.familyName ?? font.fontName)
        }
        NSFontManager.shared.target = FontPanelDelegate.shared
    }

    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
}

final class FontPanelDelegate: NSObject {
    static let shared = FontPanelDelegate()
    var onFontChange: ((NSFont) -> Void)?

    @objc func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        let font = manager.convert(NSFont.systemFont(ofSize: 13))
        onFontChange?(font)
    }
}

// MARK: - Reset Defaults Button

final class ResetDefaultsButton: NSView {
    var onClick: (() -> Void)?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    private let label: NSTextField

    override var mouseDownCanMoveWindow: Bool { false }

    init(title: String = "Reset to Defaults") {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = Theme.textMuted
        label.alignment = .center
        addSubview(label)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        label.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = isHovered ? Theme.chromeElevated : Theme.chrome.withAlphaComponent(0.88)
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        Theme.border.setStroke()
        let bp = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        bp.lineWidth = 0.5
        bp.stroke()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; label.textColor = Theme.textSecondary; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; label.textColor = Theme.textMuted; needsDisplay = true }
}
