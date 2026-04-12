import AppKit

/// Root window content view that hosts a terminal container and provides a
/// translucent material behind it. Used so profiles with
/// `backgroundOpacity < 1` have a visible backdrop instead of the raw desktop
/// when Ghostty composites its alpha pixels.
final class BackdropView: NSVisualEffectView {
    let container: TerminalContainerView
    private let tintLayer = CALayer()

    init(container: TerminalContainerView) {
        self.container = container
        super.init(frame: .zero)
        blendingMode = .behindWindow
        state = .active
        material = .hudWindow
        wantsLayer = true
        layer?.masksToBounds = true

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
        tintLayer.frame = bounds
    }

    /// Update the material and tint for the given profile. Called whenever
    /// settings or the active profile change.
    func apply(profile: TerminalProfile, fallback: BellithSettings, screen: NSScreen?) {
        let opacity = profile.effectiveBackgroundOpacity(fallback: fallback)
        let blur = profile.effectiveBlurIntensity()
        let wantsTranslucent = opacity < 1.0 || blur > 0

        // When the profile is fully opaque we hide the material so Ghostty's
        // own background fills the window without any blur cost.
        isHidden = !wantsTranslucent
        material = Self.material(forBlurIntensity: blur)

        if profile.effectiveWallpaperTint(), wantsTranslucent {
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

    private static func material(forBlurIntensity intensity: Double) -> NSVisualEffectView.Material {
        switch intensity {
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
