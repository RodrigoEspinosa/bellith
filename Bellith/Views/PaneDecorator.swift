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
        // Must match RebrandTokens.Layout.paneCornerRadius — otherwise the
        // glow's rounded path doesn't sit on top of the card's rounded corners
        // and you get a 2px halo bleed at each corner.
        static let cornerRadius: CGFloat = RebrandTokens.Layout.paneCornerRadius
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
        glowLayer.borderWidth = 0
        glowLayer.masksToBounds = false

        switch state {
        case .hidden:
            borderLayer.opacity = 0
            glowLayer.backgroundColor = NSColor.clear.cgColor
            glowLayer.opacity = 0
            glowLayer.shadowOpacity = 0

        case .inactive:
            // PaneContainerView paints the always-on lineSoft hairline for
            // the card. Drawing a second hairline here would just double-up.
            borderLayer.opacity = 0
            borderLayer.borderWidth = 0
            glowLayer.backgroundColor = NSColor.clear.cgColor
            glowLayer.opacity = 0
            glowLayer.shadowOpacity = 0

        case .active:
            // The reference design indicates focus with a subtle copper
            // hairline on the card itself (drawn by PaneContainerView) — no
            // outer halo. Drop the glow entirely; a loud halo around the
            // focused pane felt out of place against the otherwise quiet
            // chrome.
            borderLayer.opacity = 0
            borderLayer.borderWidth = 0
            glowLayer.backgroundColor = NSColor.clear.cgColor
            glowLayer.opacity = 0
            glowLayer.shadowOpacity = 0

        case .broadcast:
            // Broadcast keeps a faint accent halo so this destructive global
            // mode still reads at a glance — it's louder than focus on
            // purpose.
            borderLayer.opacity = 0
            borderLayer.borderWidth = 0
            glowLayer.backgroundColor = Theme.accent.withAlphaComponent(0.25).cgColor
            glowLayer.opacity = 1
            glowLayer.shadowColor = Theme.accent.withAlphaComponent(0.55).cgColor
            glowLayer.shadowOpacity = 1
            glowLayer.shadowRadius = 10
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
        // Insert at the back so the glow's tint fill is hidden behind the
        // opaque PaneContainerView card; only the outer shadow halo (which
        // extends past the leaf bounds into the divider gap) is visible.
        // Without this the addSublayer default appends to the top, putting
        // the fill on top of the card.
        parent.insertSublayer(layer, at: 0)
        return layer
    }
}
