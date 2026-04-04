import AppKit
import QuartzCore

/// Custom window with Zen-inspired minimal chrome.
/// Traffic lights auto-hide after a delay and reappear on hover.
final class TerminalWindow: NSWindow {
    private var trafficLightTrackingArea: NSTrackingArea?
    private var trafficLightHideTimer: Timer?
    private var trafficLightsVisible = true

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

    // MARK: - Traffic Light Auto-Hide

    private func scheduleTrafficLightHide() {
        trafficLightHideTimer?.invalidate()
        trafficLightHideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.hideTrafficLights()
        }
    }

    private var shouldAutoHideTrafficLights: Bool {
        BellithSettings.shared.trafficLightAutoHide
    }

    private var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func hideTrafficLights() {
        guard trafficLightsVisible, shouldAutoHideTrafficLights else { return }
        trafficLightsVisible = false

        if shouldReduceMotion {
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                standardWindowButton(type)?.alphaValue = 0
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Theme.animMedium
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                    standardWindowButton(type)?.animator().alphaValue = 0
                }
            }
        }
    }

    func showTrafficLights() {
        guard !trafficLightsVisible else {
            if shouldAutoHideTrafficLights { scheduleTrafficLightHide() }
            return
        }
        trafficLightsVisible = true

        if shouldReduceMotion {
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                standardWindowButton(type)?.alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Theme.animFast
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                    standardWindowButton(type)?.animator().alphaValue = 1
                }
            }
        }

        if shouldAutoHideTrafficLights { scheduleTrafficLightHide() }
    }

    // MARK: - Layout

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        setupTrafficLightTracking()
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag)
        setupTrafficLightTracking()
    }

    // MARK: - Traffic Light Hover Tracking

    private func setupTrafficLightTracking() {
        guard let contentView else { return }

        if let existing = trafficLightTrackingArea {
            contentView.removeTrackingArea(existing)
        }

        let trackingRect = NSRect(x: 0, y: contentView.bounds.height - 50, width: 100, height: 50)
        let area = NSTrackingArea(
            rect: trackingRect,
            options: [.mouseEnteredAndExited, .activeAlways],
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
