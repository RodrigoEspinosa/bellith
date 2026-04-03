import AppKit

/// Reusable frosted glass blur view for overlay panels.
final class BlurView: NSVisualEffectView {
    init(material: NSVisualEffectView.Material = .sidebar, radius: CGFloat = Theme.radiusPanel) {
        super.init(frame: .zero)
        self.material = material
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
