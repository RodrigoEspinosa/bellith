import AppKit
import QuartzCore

/// Custom window with Zen-inspired minimal chrome.
/// Traffic lights auto-hide after a delay and reappear on hover.
final class TerminalWindow: NSWindow {
    private var trafficLightTrackingArea: NSTrackingArea?
    private var trafficLightHideTimer: Timer?
    private var trafficLightsVisible = true
    private let accentLine = CALayer()

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: backingStoreType,
            defer: flag
        )
        configure()
    }

    private var themeObserver: NSObjectProtocol?

    private func configure() {
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true

        applyThemeBackground()
        isOpaque = true
        hasShadow = true

        appearance = NSAppearance(named: .darkAqua)

        // Clear titlebar backgrounds
        if let titlebarContainer = standardWindowButton(.closeButton)?.superview?.superview {
            titlebarContainer.wantsLayer = true
            titlebarContainer.layer?.backgroundColor = .clear

            if let buttonsSuperview = standardWindowButton(.closeButton)?.superview {
                buttonsSuperview.wantsLayer = true
                buttonsSuperview.layer?.backgroundColor = .clear
            }
        }

        // Start the auto-hide timer
        scheduleTrafficLightHide()

        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.applyThemeBackground() }
    }

    private func applyThemeBackground() {
        backgroundColor = Theme.colors.frame
    }

    deinit {
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
    }

    // MARK: - Accent Glow Line

    func setupAccentLine() {
        // Intentionally empty — Zen-style chrome has no accent line
    }

    // MARK: - Traffic Light Auto-Hide

    private func scheduleTrafficLightHide() {
        trafficLightHideTimer?.invalidate()
        trafficLightHideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.hideTrafficLights()
        }
    }

    private func hideTrafficLights() {
        guard trafficLightsVisible else { return }
        trafficLightsVisible = false

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animMedium
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                standardWindowButton(type)?.animator().alphaValue = 0
            }
        }
    }

    func showTrafficLights() {
        guard !trafficLightsVisible else {
            scheduleTrafficLightHide()
            return
        }
        trafficLightsVisible = true

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                standardWindowButton(type)?.animator().alphaValue = 1
            }
        }

        scheduleTrafficLightHide()
    }

    // MARK: - Layout

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        positionTrafficLights()
        setupAccentLine()
        setupTrafficLightTracking()
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        positionTrafficLights()
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag)
        positionTrafficLights()
    }

    private func positionTrafficLights() {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let xStart: CGFloat = 16
        let spacing: CGFloat = 20
        let yFromTop: CGFloat = 8

        for (i, type) in buttons.enumerated() {
            guard let button = standardWindowButton(type) else { continue }
            guard let superview = button.superview else { continue }

            button.setFrameOrigin(NSPoint(
                x: xStart + CGFloat(i) * spacing,
                y: superview.bounds.height - button.frame.height - yFromTop
            ))
        }
    }

    // MARK: - Traffic Light Hover Tracking

    private func setupTrafficLightTracking() {
        guard let contentView else { return }

        if let existing = trafficLightTrackingArea {
            contentView.removeTrackingArea(existing)
        }

        // Tracking area covers the top-left corner where traffic lights live
        let trackingRect = NSRect(x: 0, y: contentView.bounds.height - 40, width: 100, height: 40)
        let area = NSTrackingArea(
            rect: trackingRect,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: ["zone": "trafficLights"]
        )
        contentView.addTrackingArea(area)
        trafficLightTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if let info = event.trackingArea?.userInfo as? [String: String],
           info["zone"] == "trafficLights" {
            showTrafficLights()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let info = event.trackingArea?.userInfo as? [String: String],
           info["zone"] == "trafficLights" {
            scheduleTrafficLightHide()
        }
    }
}
