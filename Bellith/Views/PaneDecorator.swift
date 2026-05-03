import AppKit
import QuartzCore

/// Visual state of a single pane's focus indicator.
enum PaneDecorationState {
    case hidden
    case inactive
    case active(tint: NSColor)
    case broadcast
}

/// Renders the focus border + glow on a pane leaf view.
///
/// Pulled out of `TerminalContainerView` so the host doesn't have to own the
/// CALayer plumbing for what is, ultimately, a presentation concern.
enum PaneDecorator {
    private enum Layer {
        static let border = "paneBorder"
        static let glow = "paneGlow"
        // Border sits flush with the pane card (PaneContainerView paints
        // its own card hairline at the same edge). The hairline is replaced
        // by the active border's color here when the pane is focused.
        static let inset: CGFloat = 0
        static let cornerRadius: CGFloat = 8
    }

    static func apply(to leaf: NSView, state: PaneDecorationState) {
        leaf.wantsLayer = true
        leaf.layer?.borderColor = nil
        leaf.layer?.borderWidth = 0
        leaf.layer?.cornerRadius = 0
        leaf.layer?.masksToBounds = false

        guard let layer = leaf.layer else { return }
        let frame = leaf.bounds.insetBy(dx: Layer.inset, dy: Layer.inset)
        let borderLayer = decorationLayer(named: Layer.border, on: layer, frame: frame)
        let glowLayer = decorationLayer(named: Layer.glow, on: layer, frame: frame)

        borderLayer.cornerRadius = Layer.cornerRadius
        borderLayer.cornerCurve = .continuous
        borderLayer.backgroundColor = NSColor.clear.cgColor
        borderLayer.masksToBounds = false
        glowLayer.cornerRadius = Layer.cornerRadius
        glowLayer.cornerCurve = .continuous
        glowLayer.backgroundColor = NSColor.clear.cgColor
        glowLayer.borderWidth = 0

        switch state {
        case .hidden:
            borderLayer.opacity = 0
            glowLayer.opacity = 0
            glowLayer.shadowOpacity = 0

        case .inactive:
            borderLayer.opacity = 1
            borderLayer.borderWidth = 1
            borderLayer.borderColor = Theme.chromeHairline
                .withAlphaComponent(Theme.colors.isLight ? 0.32 : 0.24)
                .cgColor
            glowLayer.opacity = 0
            glowLayer.shadowOpacity = 0

        case .active(let tint):
            borderLayer.opacity = 1
            borderLayer.borderWidth = 1.5
            borderLayer.borderColor = tint.withAlphaComponent(0.34).cgColor
            glowLayer.opacity = 1
            glowLayer.shadowColor = tint.withAlphaComponent(0.12).cgColor
            glowLayer.shadowOpacity = 0.7
            glowLayer.shadowRadius = 10
            glowLayer.shadowOffset = .zero

        case .broadcast:
            // Broadcast keeps the global accent — it's a destructive/global mode
            // that shouldn't be tinted by workspace identity.
            borderLayer.opacity = 1
            borderLayer.borderWidth = 1.5
            borderLayer.borderColor = Theme.accent.withAlphaComponent(0.52).cgColor
            glowLayer.opacity = 1
            glowLayer.shadowColor = Theme.accent.withAlphaComponent(0.12).cgColor
            glowLayer.shadowOpacity = 1
            glowLayer.shadowRadius = 8
            glowLayer.shadowOffset = .zero
        }
    }

    private static func decorationLayer(named name: String, on parent: CALayer, frame: CGRect) -> CALayer {
        if let existing = parent.sublayers?.first(where: { $0.name == name }) {
            existing.frame = frame
            return existing
        }

        let layer = CALayer()
        layer.name = name
        layer.frame = frame
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        parent.addSublayer(layer)
        return layer
    }
}
