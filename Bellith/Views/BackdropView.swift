import AppKit

/// Root window content view that hosts a terminal container and provides a
/// translucent material behind the *frame* (sidebar, title bar, padding) when
/// `backgroundOpacity < 1`. The terminal content surface itself always renders
/// fully opaque so text stays legible regardless of frame translucency.
final class BackdropView: NSVisualEffectView {
    let container: TerminalContainerView
    private let frameTintLayer = CALayer()
    private let tintLayer = CALayer()

    init(container: TerminalContainerView) {
        self.container = container
        super.init(frame: .zero)
        blendingMode = .behindWindow
        state = .active
        material = .hudWindow
        wantsLayer = true
        layer?.masksToBounds = true

        frameTintLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(frameTintLayer)

        tintLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(tintLayer)

        container.autoresizingMask = [.width, .height]
        addSubview(container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        container.frame = bounds
        frameTintLayer.frame = bounds
        tintLayer.frame = bounds
    }

    /// Update the material and tint for the given profile. Called whenever
    /// settings or the active profile change.
    func apply(settings: BellithSettings, screen: NSScreen?) {
        let opacity = min(max(settings.backgroundOpacity, 0.0), 1.0)
        let translucency = 1.0 - opacity
        let wantsTranslucent = translucency > 0

        // When the profile is fully opaque we hide the material so Ghostty's
        // own background fills the window without any blur cost.
        isHidden = !wantsTranslucent
        material = Self.material(forFrameTranslucency: translucency)

        // Tint the frame (areas around the opaque terminal surface — sidebar,
        // title bar, padding) with the theme frame color at the requested
        // opacity. This lets the slider blend between solid frame and glass
        // without touching the terminal content, which always renders opaque.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if wantsTranslucent {
            frameTintLayer.backgroundColor = Theme.colors.frame
                .withAlphaComponent(CGFloat(opacity))
                .cgColor
            frameTintLayer.isHidden = false
        } else {
            frameTintLayer.isHidden = true
        }
        CATransaction.commit()

        if settings.wallpaperTint, wantsTranslucent {
            let accent = WallpaperTint.shared.accent(for: screen ?? NSScreen.main)
            let blended = Self.blend(base: Theme.colors.frame, tint: accent, amount: 0.3)
            tintLayer.backgroundColor = blended.withAlphaComponent(0.55).cgColor
            tintLayer.isHidden = false
        } else {
            tintLayer.isHidden = true
        }

        // Keep the BackdropView's own cornerRadius synced with whatever the
        // container wants for its chrome, so the window silhouette stays
        // consistent between opaque and translucent modes.
        if let radius = container.layer?.cornerRadius {
            layer?.cornerRadius = radius
        }
    }

    /// Curated material progression along the unified translucency slider.
    /// Each band was picked so every slider position yields a materially
    /// coherent frame — no flickering thresholds at off positions.
    private static func material(forFrameTranslucency value: Double) -> NSVisualEffectView.Material {
        switch value {
        case ..<0.2: return .hudWindow
        case ..<0.45: return .sidebar
        case ..<0.7: return .menu
        default: return .fullScreenUI
        }
    }

    private static func blend(base: NSColor, tint: NSColor, amount: CGFloat) -> NSColor {
        guard let a = base.usingColorSpace(.sRGB),
              let b = tint.usingColorSpace(.sRGB) else { return base }
        let inv = 1 - amount
        return NSColor(
            srgbRed: a.redComponent * inv + b.redComponent * amount,
            green: a.greenComponent * inv + b.greenComponent * amount,
            blue: a.blueComponent * inv + b.blueComponent * amount,
            alpha: a.alphaComponent
        )
    }
}
