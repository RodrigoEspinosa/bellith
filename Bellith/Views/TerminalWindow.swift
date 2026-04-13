import AppKit
import QuartzCore

/// Custom window with Zen-inspired minimal chrome.
/// Traffic lights auto-hide after a delay and reappear on hover.
final class TerminalWindow: NSWindow {
    let tabDragIdentifier = UUID()

    enum TrafficLightDisplayMode {
        case automatic
        case forcedVisible
        case forcedHidden
    }

    private enum Metrics {
        static let autoHideDelay: TimeInterval = 2.0
        static let automaticTrackingOriginX: CGFloat = 0
        static let automaticTrackingWidth: CGFloat = 120
        static let forcedTrackingOriginX: CGFloat = 8
        static let forcedTrackingWidth: CGFloat = 164
        static let automaticOriginX: CGFloat = 14
        static let forcedOriginX: CGFloat = 16
        static let automaticOriginYOffset: CGFloat = -1
        static let forcedOriginYOffset: CGFloat = 2
        static let automaticSpacing: CGFloat = 6
        static let forcedSpacing: CGFloat = 6.5
    }

    private var trafficLightTrackingArea: NSTrackingArea?
    private var trafficLightHideTimer: Timer?
    private var trafficLightsVisible = true
    private var trafficLightDisplayMode: TrafficLightDisplayMode = .automatic
    private let settings: BellithSettings
    private var settingsObserver: NSObjectProtocol?
    private var wallpaperObserver: NSObjectProtocol?

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        self.settings = .shared
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: backingStoreType,
            defer: flag
        )
        configure()
    }

    init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool,
        settings: BellithSettings
    ) {
        self.settings = settings
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
        toolbarStyle = .unifiedCompact

        applyThemeBackground()
        applyThemeAppearance()
        hasShadow = true
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = Theme.radiusWindow + 4
        contentView?.layer?.masksToBounds = true
        applyProfileAppearance()

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
        ) { [weak self] _ in
            self?.applyThemeBackground()
            self?.applyThemeAppearance()
            self?.applyProfileAppearance()
            self?.positionTrafficLights()
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: BellithSettings.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyProfileAppearance()
        }

        wallpaperObserver = NotificationCenter.default.addObserver(
            forName: WallpaperTint.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyProfileAppearance()
        }
    }

    private func applyThemeBackground() {
        contentView?.layer?.borderWidth = 0
        contentView?.layer?.borderColor = NSColor.clear.cgColor
        // The visible frame color is resolved in applyProfileAppearance so
        // translucent profiles can bypass the opaque fill.
    }

    /// Syncs the window chrome to the active profile. Ghostty renders the
    /// terminal background with `background-opacity`, so we just toggle the
    /// window between opaque and clear backing. The `BackdropView` that
    /// wraps the terminal container is always present — it provides the
    /// material that shows through Ghostty's alpha.
    private func applyProfileAppearance() {
        let profile = settings.activeProfile
        let opacity = profile.effectiveBackgroundOpacity(fallback: settings)
        let blur = profile.effectiveBlurIntensity()
        let wantsTranslucent = opacity < 1.0 || blur > 0

        alphaValue = 1.0
        isOpaque = !wantsTranslucent
        backgroundColor = wantsTranslucent ? .clear : Theme.colors.frame

        if let backdrop = contentView as? BackdropView {
            backdrop.apply(profile: profile, fallback: settings, screen: screen)
        }

        invalidateShadow()
    }

    private func applyThemeAppearance() {
        appearance = Theme.overlayAppearance
    }

    deinit {
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let wallpaperObserver { NotificationCenter.default.removeObserver(wallpaperObserver) }
    }

    // MARK: - Traffic Light Auto-Hide

    private func scheduleTrafficLightHide() {
        guard trafficLightDisplayMode == .automatic, shouldAutoHideTrafficLights else { return }
        trafficLightHideTimer?.invalidate()
        trafficLightHideTimer = Timer.scheduledTimer(withTimeInterval: Metrics.autoHideDelay, repeats: false) { [weak self] _ in
            self?.hideTrafficLights()
        }
    }

    private var shouldAutoHideTrafficLights: Bool {
        settings.trafficLightAutoHide
    }

    private var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func setTrafficLightsVisible(_ visible: Bool, animated: Bool) {
        trafficLightsVisible = visible
        let targetAlpha: CGFloat = visible ? 1 : 0

        if !animated || shouldReduceMotion {
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                standardWindowButton(type)?.alphaValue = targetAlpha
            }
            return
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = visible ? Theme.animFast : Theme.animSlow
            ctx.timingFunction = CAMediaTimingFunction(name: visible ? .easeOut : .easeIn)
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                standardWindowButton(type)?.animator().alphaValue = targetAlpha
            }
        }
    }

    private func hideTrafficLights() {
        guard trafficLightDisplayMode == .automatic, trafficLightsVisible, shouldAutoHideTrafficLights else { return }
        setTrafficLightsVisible(false, animated: true)
    }

    func showTrafficLights() {
        guard trafficLightDisplayMode != .forcedHidden else { return }
        guard !trafficLightsVisible else {
            scheduleTrafficLightHide()
            return
        }
        setTrafficLightsVisible(true, animated: true)
        scheduleTrafficLightHide()
    }

    func setTrafficLightDisplayMode(_ mode: TrafficLightDisplayMode) {
        guard trafficLightDisplayMode != mode else { return }
        trafficLightDisplayMode = mode
        trafficLightHideTimer?.invalidate()

        switch mode {
        case .automatic:
            setTrafficLightsVisible(!shouldAutoHideTrafficLights, animated: true)
            scheduleTrafficLightHide()
        case .forcedVisible:
            setTrafficLightsVisible(true, animated: true)
        case .forcedHidden:
            setTrafficLightsVisible(false, animated: true)
        }
    }

    // MARK: - Layout

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        positionTrafficLights()
        setupTrafficLightTracking()
        applyProfileAppearance()
    }

    private var lastTrackingHeight: CGFloat = 0

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag)
        // Only rebuild tracking area when the content height changes (avoids churn during resize)
        let currentHeight = contentView?.bounds.height ?? 0
        if abs(currentHeight - lastTrackingHeight) > 1 {
            lastTrackingHeight = currentHeight
            positionTrafficLights()
            setupTrafficLightTracking()
        }
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        positionTrafficLights()
    }

    // MARK: - Traffic Light Hover Tracking

    private func setupTrafficLightTracking() {
        guard let contentView else { return }

        if let existing = trafficLightTrackingArea {
            contentView.removeTrackingArea(existing)
        }

        let trackingOriginX: CGFloat = trafficLightDisplayMode == .automatic ? Metrics.automaticTrackingOriginX : Metrics.forcedTrackingOriginX
        let trackingWidth: CGFloat = trafficLightDisplayMode == .automatic ? Metrics.automaticTrackingWidth : Metrics.forcedTrackingWidth
        let trackingRect = NSRect(x: trackingOriginX, y: contentView.bounds.height - 64, width: trackingWidth, height: 64)
        let area = NSTrackingArea(
            rect: trackingRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: ["zone": "trafficLights"]
        )
        contentView.addTrackingArea(area)
        trafficLightTrackingArea = area
    }

    private func positionTrafficLights() {
        guard let close = standardWindowButton(.closeButton),
              let mini = standardWindowButton(.miniaturizeButton),
              let zoom = standardWindowButton(.zoomButton),
              let container = close.superview else { return }

        let buttons = [close, mini, zoom]
        let buttonHeight = close.frame.height
        let usesSidebarPlacement = trafficLightDisplayMode != .automatic
        let originY = round((container.bounds.height - buttonHeight) / 2) + (usesSidebarPlacement ? Metrics.forcedOriginYOffset : Metrics.automaticOriginYOffset)
        let originX: CGFloat = usesSidebarPlacement ? Metrics.forcedOriginX : Metrics.automaticOriginX
        let spacing: CGFloat = usesSidebarPlacement ? Metrics.forcedSpacing : Metrics.automaticSpacing
        var x = originX

        for button in buttons {
            var frame = button.frame
            frame.origin = NSPoint(x: x, y: originY)
            button.setFrameOrigin(frame.origin)
            switch trafficLightDisplayMode {
            case .automatic:
                button.alphaValue = trafficLightsVisible || !shouldAutoHideTrafficLights ? 1 : 0
            case .forcedVisible:
                button.alphaValue = 1
            case .forcedHidden:
                button.alphaValue = 0
            }
            x += frame.width + spacing
        }
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
