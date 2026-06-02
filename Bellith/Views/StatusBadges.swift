import AppKit
import QuartzCore

/// "ZOOMED" pill shown when a single pane is temporarily maximized within a tab.
final class ZoomBadge: NSView {
    private let label = NSTextField(labelWithString: "ZOOMED")
    private let iconView = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 0.5

        iconView.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Zoomed")
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        addSubview(label)

        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 8, y: (h - 10) / 2, width: 10, height: 10)
        label.frame = NSRect(x: 22, y: (h - 12) / 2, width: bounds.width - 28, height: 12)
    }

    func refreshTheme() {
        layer?.backgroundColor = Theme.accent.withAlphaComponent(0.15).cgColor
        layer?.borderColor = Theme.accent.withAlphaComponent(0.3).cgColor
        iconView.contentTintColor = Theme.accent
        label.textColor = Theme.accent
    }
}

/// "BROADCAST" pill with a pulsing dot, shown while broadcast-input mode mirrors
/// keystrokes across all visible panes in the focused tab.
final class BroadcastBadge: NSView {
    private let label = NSTextField(labelWithString: "BROADCAST")
    private let dotView = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.borderWidth = 0.5

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3
        addSubview(dotView)

        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        addSubview(label)

        startPulse()
        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        dotView.frame = NSRect(x: 10, y: (h - 6) / 2, width: 6, height: 6)
        label.frame = NSRect(x: 22, y: (h - 12) / 2, width: bounds.width - 30, height: 12)
    }

    private func startPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotView.layer?.add(pulse, forKey: "pulse")
    }

    func refreshTheme() {
        layer?.backgroundColor = Theme.warning.withAlphaComponent(0.15).cgColor
        layer?.borderColor = Theme.warning.withAlphaComponent(0.3).cgColor
        dotView.layer?.backgroundColor = Theme.warning.cgColor
        label.textColor = Theme.warning
    }
}
