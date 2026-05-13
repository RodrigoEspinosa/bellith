import AppKit

// MARK: - Appearance Pane

final class AppearancePane: NSView {
    private let settings: BellithSettings
    private let themeManager: ThemeManager
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let paneTitleLabel = NSTextField(labelWithString: "Appearance")
    private let paneSubtitleLabel = NSTextField(labelWithString: "Color, noise, and transparency.")
    private let themeSurface: AppearanceTuningSurface
    private var colorWheel: AppearanceColorWheel!
    private var noiseBar: AppearanceValueBar!
    private var transparencyBar: AppearanceValueBar!
    private var previewAccentColor: NSColor
    private var previewNoiseIntensity: Double
    private var previewBackgroundOpacity: Double

    init(
        frame frameRect: NSRect = .zero,
        settings: BellithSettings = .shared,
        themeManager: ThemeManager = .shared
    ) {
        self.settings = settings
        self.themeManager = themeManager
        self.themeSurface = AppearanceTuningSurface(settings: settings)
        self.previewAccentColor = settings.appearanceAccentColor
        self.previewNoiseIntensity = settings.noiseIntensity
        self.previewBackgroundOpacity = max(settings.backgroundOpacity, 0.45)
        super.init(frame: frameRect)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        addSubview(scroll)

        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.frame.cgColor
        scroll.documentView = content

        paneTitleLabel.font = BellithFont.ui(22, weight: .semibold)
        paneTitleLabel.textColor = Theme.textDisplay
        content.addSubview(paneTitleLabel)

        paneSubtitleLabel.font = BellithFont.ui(13, weight: .regular)
        paneSubtitleLabel.textColor = Theme.textSecondary
        content.addSubview(paneSubtitleLabel)

        colorWheel = AppearanceColorWheel(color: previewAccentColor, onPreview: { [weak self] color in
            guard let self else { return }
            self.previewAccentColor = color
            self.themeSurface.setPreview(
                accentColor: color,
                backgroundOpacity: self.previewBackgroundOpacity,
                noiseIntensity: self.previewNoiseIntensity
            )
        }, onCommit: { [weak self] color in
            guard let self else { return }
            self.previewAccentColor = color
            self.settings.appearanceAccentColor = color
            self.themeManager.apply(self.settings.resolvedTheme)
            self.refresh()
        })

        noiseBar = AppearanceValueBar(
            title: "Noise",
            value: settings.noiseIntensity,
            style: .noise,
            onPreview: { [weak self] value in
                guard let self else { return }
                self.previewNoiseIntensity = value
                self.themeSurface.setPreview(
                    accentColor: self.previewAccentColor,
                    backgroundOpacity: self.previewBackgroundOpacity,
                    noiseIntensity: value
                )
            },
            onCommit: { [weak self] value in
                guard let self else { return }
                self.previewNoiseIntensity = value
                self.settings.noiseIntensity = value
                self.refreshValues()
            }
        )

        transparencyBar = AppearanceValueBar(
            title: "Transparency",
            value: 1.0 - settings.backgroundOpacity,
            style: .transparency,
            onPreview: { [weak self] value in
                guard let self else { return }
                let opacity = 1.0 - value
                self.previewBackgroundOpacity = opacity
                self.themeSurface.setPreview(
                    accentColor: self.previewAccentColor,
                    backgroundOpacity: opacity,
                    noiseIntensity: self.previewNoiseIntensity
                )
            },
            onCommit: { [weak self] value in
                guard let self else { return }
                self.previewBackgroundOpacity = 1.0 - value
                self.settings.backgroundOpacity = self.previewBackgroundOpacity
                self.refreshValues()
            }
        )

        content.addSubview(themeSurface)
        themeSurface.addSubview(colorWheel)
        themeSurface.addSubview(noiseBar)
        themeSurface.addSubview(transparencyBar)

        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        previewAccentColor = settings.appearanceAccentColor
        previewNoiseIntensity = settings.noiseIntensity
        previewBackgroundOpacity = max(settings.backgroundOpacity, 0.45)
        if settings.backgroundOpacity < 0.45 {
            settings.backgroundOpacity = 0.45
        }
        content.layer?.backgroundColor = Theme.frame.cgColor
        paneTitleLabel.textColor = Theme.textDisplay
        paneSubtitleLabel.textColor = Theme.textSecondary
        themeSurface.setPreview(
            accentColor: previewAccentColor,
            backgroundOpacity: previewBackgroundOpacity,
            noiseIntensity: previewNoiseIntensity
        )
        colorWheel.setColor(previewAccentColor)
        refreshValues()
        needsLayout = true
    }

    private func refreshValues() {
        noiseBar.setValue(previewNoiseIntensity)
        transparencyBar.setValue(1.0 - previewBackgroundOpacity)
        noiseBar.refresh()
        transparencyBar.refresh()
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let width = bounds.width
        let availableWidth = max(320, width - PreferencesLayout.hPad * 2)
        let cardWidth = min(availableWidth, 660)
        let contentX = PreferencesLayout.hPad + max(0, (availableWidth - cardWidth) / 2)
        var y: CGFloat = PreferencesLayout.hPad

        paneTitleLabel.frame = NSRect(x: contentX, y: y, width: cardWidth, height: 28)
        paneSubtitleLabel.frame = NSRect(x: contentX, y: y + 32, width: cardWidth, height: 18)
        y += 76

        let surfaceHeight = max(430, min(520, bounds.height - y - PreferencesLayout.hPad))
        themeSurface.frame = NSRect(x: contentX, y: y, width: cardWidth, height: surfaceHeight)

        let wheelSide = min(cardWidth - 120, surfaceHeight - 220, 256)
        colorWheel.frame = NSRect(
            x: (cardWidth - wheelSide) / 2,
            y: 44,
            width: wheelSide,
            height: wheelSide
        )

        let barWidth = min(cardWidth - 96, 460)
        let barX = (cardWidth - barWidth) / 2
        transparencyBar.frame = NSRect(x: barX, y: surfaceHeight - 138, width: barWidth, height: 46)
        noiseBar.frame = NSRect(x: barX, y: surfaceHeight - 80, width: barWidth, height: 46)

        y += surfaceHeight + PreferencesLayout.hPad
        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, bounds.height))
    }
}

extension AppearancePane: PreferencesPaneRefreshable {
    func refreshPreferencesPane() { refresh() }
}

// MARK: - Zen-Inspired Surface

private final class AppearanceTuningSurface: NSView {
    private let settings: BellithSettings
    private var accentColor: NSColor
    private var backgroundOpacity: Double
    private var noiseIntensity: Double
    private var cachedBackdrop: NSImage?
    private var cachedBackdropKey: BackdropKey?

    override var isFlipped: Bool { true }

    init(settings: BellithSettings) {
        self.settings = settings
        self.accentColor = settings.appearanceAccentColor
        self.backgroundOpacity = settings.backgroundOpacity
        self.noiseIntensity = settings.noiseIntensity
        super.init(frame: .zero)
        canDrawConcurrently = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func setPreview(accentColor: NSColor, backgroundOpacity: Double, noiseIntensity: Double) {
        let oldBackdropKey = backdropKey
        self.accentColor = accentColor
        self.backgroundOpacity = backgroundOpacity
        self.noiseIntensity = noiseIntensity
        if oldBackdropKey != backdropKey {
            cachedBackdrop = nil
            cachedBackdropKey = nil
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        drawBackdrop(in: rect)

        let noise = min(max(noiseIntensity, 0.0), 1.0)
        drawNoise(in: rect, intensity: noise)
        drawOutline(in: rect)
    }

    private var backdropKey: BackdropKey {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return BackdropKey(
            width: Int((bounds.width * scale).rounded()),
            height: Int((bounds.height * scale).rounded()),
            scale: Int((scale * 100).rounded()),
            isLight: Theme.colors.isLight,
            chrome: Theme.chrome.bellithRGBAKey,
            hairline: Theme.chromeHairline.bellithRGBAKey,
            text: Theme.textPrimary.bellithRGBAKey,
            accent: accentColor.bellithRGBAKey,
            surfaceAlphaPercent: Int((surfaceAlpha * 1000).rounded())
        )
    }

    private var surfaceAlpha: CGFloat {
        let transparency = CGFloat(1.0 - min(max(backgroundOpacity, 0.0), 1.0))
        return max(0.18, 0.96 - transparency * 0.62)
    }

    private func drawBackdrop(in rect: NSRect) {
        let key = backdropKey
        if cachedBackdropKey != key || cachedBackdrop == nil {
            cachedBackdrop = makeBackdropImage(key: key, rect: rect)
            cachedBackdropKey = key
        }
        cachedBackdrop?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func makeBackdropImage(key: BackdropKey, rect: NSRect) -> NSImage {
        let image = NSImage(size: rect.size)
        image.lockFocus()

        let surfacePath = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        Theme.chrome.withAlphaComponent(CGFloat(key.surfaceAlphaPercent) / 1000).setFill()
        surfacePath.fill()

        accentColor.withAlphaComponent(Theme.colors.isLight ? 0.06 : 0.08).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.midX - 150, y: rect.minY + 26, width: 300, height: 120)).fill()

        let dotColor = Theme.textPrimary.withAlphaComponent(Theme.colors.isLight ? 0.045 : 0.075)
        dotColor.setFill()
        let inset = rect.insetBy(dx: 28, dy: 28)
        let spacing: CGFloat = 14
        var dotY = inset.minY
        while dotY <= inset.maxY {
            var dotX = inset.minX
            while dotX <= inset.maxX {
                NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: 1.6, height: 1.6)).fill()
                dotX += spacing
            }
            dotY += spacing
        }
        image.unlockFocus()
        return image
    }

    private func drawOutline(in rect: NSRect) {
        Theme.chromeHairline.withAlphaComponent(Theme.colors.isLight ? 0.55 : 0.72).setStroke()
        let outline = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        outline.lineWidth = 1
        outline.stroke()
    }

    private func drawNoise(in rect: NSRect, intensity: Double) {
        guard intensity > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).addClip()

        let count = Int((520 + rect.width * rect.height / 900) * intensity)
        let alpha = CGFloat(0.035 + intensity * 0.12)
        let seed = 13_337
        for index in 0..<count {
            let x = rect.minX + CGFloat((index * 73 + seed) % 997) / 997 * rect.width
            let y = rect.minY + CGFloat((index * 151 + seed / 3) % 991) / 991 * rect.height
            let color = index.isMultiple(of: 2)
                ? NSColor.white.withAlphaComponent(alpha)
                : NSColor.black.withAlphaComponent(alpha)
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.2, height: 1.2)).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private struct BackdropKey: Equatable {
        let width: Int
        let height: Int
        let scale: Int
        let isLight: Bool
        let chrome: String
        let hairline: String
        let text: String
        let accent: String
        let surfaceAlphaPercent: Int
    }
}

// MARK: - Color Wheel

private final class AppearanceColorWheel: NSView {
    private let onPreview: (NSColor) -> Void
    private let onCommit: (NSColor) -> Void
    private var selectedColor: NSColor
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private static var ringCache: [Int: NSImage] = [:]

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(color: NSColor, onPreview: @escaping (NSColor) -> Void, onCommit: @escaping (NSColor) -> Void) {
        self.selectedColor = color
        self.onPreview = onPreview
        self.onCommit = onCommit
        super.init(frame: .zero)
        setAccessibilityRole(.colorWell)
        setAccessibilityLabel("Accent color wheel")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func setColor(_ color: NSColor) {
        selectedColor = color
        setAccessibilityValue(color.bellithAccessibleHexRGB)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = side * 0.41

        drawColorWheel(side: side, center: center, radius: radius)

        let knobPoint = point(for: selectedColor, center: center, radius: radius)
        drawKnob(at: knobPoint, color: selectedColor, selected: true)
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        applySelection(from: event)
    }

    override func mouseDragged(with event: NSEvent) {
        applySelection(from: event)
    }

    override func mouseUp(with event: NSEvent) {
        applySelection(from: event)
        onCommit(selectedColor)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 126:
            setColor(color(rotatingHueBy: -0.02))
            onCommit(selectedColor)
        case 124, 125, 49, 36:
            setColor(color(rotatingHueBy: 0.02))
            onCommit(selectedColor)
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

    private func applySelection(from event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.41
        selectedColor = Self.color(for: location, center: center, radius: radius)
        setAccessibilityValue(selectedColor.bellithAccessibleHexRGB)
        needsDisplay = true
        onPreview(selectedColor)
    }

    private func drawColorWheel(side: CGFloat, center: NSPoint, radius: CGFloat) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelSide = max(1, Int((side * scale).rounded()))
        let image = Self.ringCache[pixelSide] ?? Self.makeColorWheelImage(pixelSide: pixelSide)
        Self.ringCache[pixelSide] = image

        let imageRect = NSRect(
            x: center.x - side / 2,
            y: center.y - side / 2,
            width: side,
            height: side
        )
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)

        Theme.textDisplay.withAlphaComponent(0.16).setStroke()
        let outer = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        outer.lineWidth = 1
        outer.stroke()
    }

    private static func makeColorWheelImage(pixelSide: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSide,
            pixelsHigh: pixelSide,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelSide * 4,
            bitsPerPixel: 32
        )
        guard let rep, let data = rep.bitmapData else {
            return NSImage(size: NSSize(width: pixelSide, height: pixelSide))
        }

        let center = CGFloat(pixelSide - 1) / 2
        let radius = CGFloat(pixelSide) * 0.41

        for y in 0..<pixelSide {
            for x in 0..<pixelSide {
                let dx = CGFloat(x) - center
                let dy = CGFloat(y) - center
                let distance = sqrt(dx * dx + dy * dy)
                guard distance <= radius else { continue }

                let hue = normalizedHue(x: dx, y: dy)
                let saturation = min(1, distance / radius)
                let rgb = rgbFromHSB(hue: hue, saturation: saturation, brightness: 0.95)
                let alpha = edgeAlpha(distance: distance, radius: radius)
                let offset = (y * pixelSide + x) * 4
                data[offset] = UInt8(rgb.red * 255)
                data[offset + 1] = UInt8(rgb.green * 255)
                data[offset + 2] = UInt8(rgb.blue * 255)
                data[offset + 3] = UInt8(alpha * 236)
            }
        }

        let image = NSImage(size: NSSize(width: pixelSide, height: pixelSide))
        image.addRepresentation(rep)
        return image
    }

    private func drawKnob(at point: NSPoint, color: NSColor, selected: Bool) {
        let knobRadius: CGFloat = selected ? 18 : 12
        let rect = NSRect(x: point.x - knobRadius, y: point.y - knobRadius, width: knobRadius * 2, height: knobRadius * 2)

        NSColor.black.withAlphaComponent(selected ? 0.16 : 0.10).setFill()
        NSBezierPath(ovalIn: rect.offsetBy(dx: 0, dy: 1.5)).fill()

        NSColor.white.withAlphaComponent(selected ? 0.98 : 0.92).setFill()
        NSBezierPath(ovalIn: rect).fill()

        color.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: selected ? 5 : 4, dy: selected ? 5 : 4)).fill()
    }

    private static func normalizedHue(x: CGFloat, y: CGFloat) -> CGFloat {
        let angle = atan2(y, x)
        let normalized = angle < 0 ? angle + .pi * 2 : angle
        return normalized / (.pi * 2)
    }

    private static func edgeAlpha(distance: CGFloat, radius: CGFloat) -> CGFloat {
        let feather: CGFloat = 1.6
        return min(1, max(0, (radius - distance) / feather))
    }

    private static func rgbFromHSB(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let h = hue * 6
        let sector = floor(h)
        let fraction = h - sector
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))

        switch Int(sector) % 6 {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        default: return (brightness, p, q)
        }
    }

    private func point(for color: NSColor, center: NSPoint, radius: CGFloat) -> NSPoint {
        let angle = color.bellithHue * .pi * 2
        let distance = radius * color.bellithSaturation
        return NSPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
    }

    private func hue(for point: NSPoint, center: NSPoint) -> CGFloat {
        let angle = atan2(point.y - center.y, point.x - center.x)
        let normalized = angle < 0 ? angle + .pi * 2 : angle
        return normalized / (.pi * 2)
    }

    private func color(rotatingHueBy delta: CGFloat) -> NSColor {
        let hue = (selectedColor.bellithHue + delta + 1).truncatingRemainder(dividingBy: 1)
        return Self.color(forHue: hue, saturation: selectedColor.bellithSaturation)
    }

    private static func color(for point: NSPoint, center: NSPoint, radius: CGFloat) -> NSColor {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return color(
            forHue: normalizedHue(x: dx, y: dy),
            saturation: min(1, sqrt(dx * dx + dy * dy) / radius)
        )
    }

    private static func color(forHue hue: CGFloat, saturation: CGFloat) -> NSColor {
        NSColor(calibratedHue: hue, saturation: min(1, max(0, saturation)), brightness: 0.95, alpha: 1)
    }
}

// MARK: - Value Bar

private final class AppearanceValueBar: NSView {
    enum Style {
        case noise
        case transparency
    }

    private let title: String
    private var value: Double
    private let style: Style
    private let onPreview: (Double) -> Void
    private let onCommit: (Double) -> Void
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(
        title: String,
        value: Double,
        style: Style,
        onPreview: @escaping (Double) -> Void,
        onCommit: @escaping (Double) -> Void
    ) {
        self.title = title
        self.style = style
        self.value = Self.clamped(value, style: style)
        self.onPreview = onPreview
        self.onCommit = onCommit
        super.init(frame: .zero)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func setValue(_ newValue: Double) {
        value = Self.clamped(newValue, style: style)
        setAccessibilityValue("\(Int((value * 100).rounded())) percent")
        needsDisplay = true
    }

    private static func clamped(_ value: Double, style: Style) -> Double {
        let upperBound = style == .transparency ? 0.55 : 1.0
        return min(upperBound, max(0.0, value))
    }

    func refresh() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: BellithFont.mono(10, weight: .regular),
            .foregroundColor: Theme.textSecondary,
        ]
        (title.uppercased() as NSString).draw(at: NSPoint(x: 0, y: 2), withAttributes: labelAttrs)

        let valueString = "\(Int((value * 100).rounded()))%"
        let valueSize = (valueString as NSString).size(withAttributes: labelAttrs)
        (valueString as NSString).draw(at: NSPoint(x: bounds.width - valueSize.width, y: 2), withAttributes: labelAttrs)

        let track = trackRect
        Theme.frame.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill()

        switch style {
        case .noise:
            drawNoiseWave(in: track)
        case .transparency:
            drawTransparencyFill(in: track)
        }

        Theme.chromeHairline.withAlphaComponent(isHovering ? 0.8 : 0.45).setStroke()
        let border = NSBezierPath(roundedRect: track.insetBy(dx: 0.5, dy: 0.5), xRadius: track.height / 2, yRadius: track.height / 2)
        border.lineWidth = 1
        border.stroke()

        let knobWidth: CGFloat = 26
        let knobHeight: CGFloat = 26
        let knobX = track.minX + CGFloat(value) * track.width - knobWidth / 2
        let knob = NSRect(
            x: min(track.maxX - knobWidth, max(track.minX, knobX)),
            y: track.midY - knobHeight / 2,
            width: knobWidth,
            height: knobHeight
        )
        NSColor.black.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: knob.offsetBy(dx: 0, dy: 1.5), xRadius: knob.width / 2, yRadius: knob.width / 2).fill()

        NSColor.white.withAlphaComponent(0.98).setFill()
        NSBezierPath(roundedRect: knob, xRadius: knob.width / 2, yRadius: knob.width / 2).fill()
        Theme.chromeHairline.withAlphaComponent(0.55).setStroke()
        let knobStroke = NSBezierPath(roundedRect: knob.insetBy(dx: 0.5, dy: 0.5), xRadius: knob.width / 2, yRadius: knob.width / 2)
        knobStroke.lineWidth = 1
        knobStroke.stroke()
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        updateValue(from: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateValue(from: event)
    }

    override func mouseUp(with event: NSEvent) {
        updateValue(from: event)
        onCommit(value)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 125:
            setValue(value - 0.05)
            onPreview(value)
            onCommit(value)
        case 124, 126:
            setValue(value + 0.05)
            onPreview(value)
            onCommit(value)
        default:
            super.keyDown(with: event)
        }
    }

    private var trackRect: NSRect {
        NSRect(x: 0, y: 25, width: bounds.width, height: 9)
    }

    private func updateValue(from event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let track = trackRect
        setValue(Double((location.x - track.minX) / track.width))
        onPreview(value)
    }

    private func drawNoiseWave(in track: NSRect) {
        let activeRect = NSRect(
            x: track.minX,
            y: track.minY,
            width: track.width * CGFloat(value),
            height: track.height
        )
        if activeRect.width > 0 {
            Theme.accent.withAlphaComponent(0.42).setFill()
            NSBezierPath(roundedRect: activeRect, xRadius: track.height / 2, yRadius: track.height / 2).fill()
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).addClip()

        let path = NSBezierPath()
        let amplitude = track.height * (0.08 + CGFloat(value) * 0.22)
        let midY = track.midY
        let steps = 96
        for step in 0...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let x = track.minX + fraction * track.width
            let y = midY + sin(fraction * .pi * 12) * amplitude
            if step == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        Theme.textDisplay.withAlphaComponent(0.42).setStroke()
        path.lineWidth = max(2, track.height * 0.55)
        path.lineCapStyle = .round
        path.stroke()

        Theme.textDisplay.withAlphaComponent(0.13).setFill()
        let dotCount = Int(48 * value)
        for index in 0..<dotCount {
            let x = track.minX + CGFloat((index * 37) % 211) / 211 * track.width
            let y = track.minY + CGFloat((index * 61) % 89) / 89 * track.height
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.4, height: 1.4)).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawTransparencyFill(in track: NSRect) {
        let fillRect = NSRect(x: track.minX, y: track.minY, width: track.width * CGFloat(value), height: track.height)
        guard fillRect.width > 0 else { return }

        let path = NSBezierPath(roundedRect: fillRect, xRadius: track.height / 2, yRadius: track.height / 2)
        Theme.accent.withAlphaComponent(0.78).setFill()
        path.fill()

        Theme.textDisplay.withAlphaComponent(0.14).setFill()
        let spacing: CGFloat = 8
        var x = track.minX + 4
        while x < track.maxX {
            NSBezierPath(ovalIn: NSRect(x: x, y: track.midY - 1.2, width: 2.4, height: 2.4)).fill()
            x += spacing
        }
    }
}

private extension NSColor {
    var bellithAccessibleHexRGB: String {
        let rgb = usingColorSpace(.sRGB) ?? self
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    var bellithRGBAKey: String {
        let rgb = usingColorSpace(.sRGB) ?? self
        return String(
            format: "%.4f-%.4f-%.4f-%.4f",
            Double(rgb.redComponent),
            Double(rgb.greenComponent),
            Double(rgb.blueComponent),
            Double(rgb.alphaComponent)
        )
    }

    var bellithHue: CGFloat {
        let rgb = usingColorSpace(.sRGB) ?? self
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return hue
    }

    var bellithSaturation: CGFloat {
        let rgb = usingColorSpace(.sRGB) ?? self
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return saturation
    }
}

private extension CGFloat {
    func distance(to other: CGFloat) -> CGFloat {
        let direct = abs(self - other)
        return Swift.min(direct, 1 - direct)
    }
}
