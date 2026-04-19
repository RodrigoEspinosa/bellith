import AppKit
import Carbon
import GhosttyKit
import os

/// Manages a visor-style dropdown terminal activated by a global hotkey.
/// The terminal slides down from the top of the screen and can be toggled
/// with Option+` (customizable).
final class QuickTerminalController: NSObject {
    static let shared = QuickTerminalController()

    private var window: QuickTerminalWindow?
    private var container: TerminalContainerView?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private weak var terminalApp: TerminalApp?
    private var dependencies: BellithDependencies = .live
    private var isVisible = false
    private var isAnimating = false

    private override init() { super.init() }

    // MARK: - Setup

    func setup(terminalApp: TerminalApp, dependencies: BellithDependencies = .live) {
        self.terminalApp = terminalApp
        self.dependencies = dependencies
        registerHotKey()
    }

    deinit {
        unregisterHotKey()
    }

    // MARK: - Global Hotkey (Option+`)

    private func registerHotKey() {
        // Carbon hotkey for Option+` (backtick = kVK_ANSI_Grave = 0x32)
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x424C5448) // "BLTH"
        hotKeyID.id = 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_Grave),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr else {
            Logger.app.warning("Failed to register global hotkey: \(status)")
            return
        }
        hotKeyRef = ref

        // Install Carbon event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<QuickTerminalController>.fromOpaque(userData).takeUnretainedValue()
                controller.toggle()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    // MARK: - Toggle

    func toggle() {
        guard !isAnimating else { return }

        if isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Show

    private func show() {
        guard let terminalApp else { return }

        NSApp.activate()

        if window == nil {
            createWindow(terminalApp: terminalApp)
        }

        guard let window else { return }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        let settings = dependencies.settings
        let width = screenFrame.width * CGFloat(settings.visorWidthPercent)
        let height = screenFrame.height * CGFloat(settings.visorHeightPercent)

        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let hiddenY: CGFloat
        let visibleY: CGFloat
        switch settings.visorPosition {
        case "bottom":
            hiddenY = screenFrame.origin.y - height - 10
            visibleY = screenFrame.origin.y
        default:
            hiddenY = screenFrame.origin.y + screenFrame.height + 10
            visibleY = screenFrame.origin.y + screenFrame.height - height
        }

        // Start offscreen in the hidden direction before animating in
        window.setFrame(NSRect(x: x, y: hiddenY, width: width, height: height), display: false)
        window.makeKeyAndOrderFront(nil)
        window.level = .floating

        isAnimating = true
        isVisible = true

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            window.animator().setFrame(
                NSRect(x: x, y: visibleY, width: width, height: height),
                display: true
            )
        } completionHandler: { [weak self] in
            self?.isAnimating = false
            self?.window?.makeFirstResponder(self?.container?.activeSurface)
        }
    }

    // MARK: - Hide

    private func hide() {
        guard let window else { return }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        let frame = window.frame
        let hiddenY: CGFloat
        switch dependencies.settings.visorPosition {
        case "bottom":
            hiddenY = screenFrame.origin.y - frame.height - 10
        default:
            hiddenY = screenFrame.origin.y + screenFrame.height + 10
        }

        isAnimating = true
        isVisible = false

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(
                NSRect(x: frame.origin.x, y: hiddenY, width: frame.width, height: frame.height),
                display: true
            )
        } completionHandler: { [weak self] in
            self?.isAnimating = false
            self?.window?.orderOut(nil)
        }
    }

    // MARK: - Cleanup

    /// Release resources on app termination.
    func cleanup() {
        window?.close()
        window = nil
        container = nil
    }

    // MARK: - Window Creation

    private func createWindow(terminalApp: TerminalApp) {
        let win = QuickTerminalWindow()
        win.isReleasedWhenClosed = false

        let cont = TerminalContainerView(terminalApp: terminalApp, dependencies: dependencies)
        win.contentView = cont
        win.applyContentAppearance()
        win.delegate = self

        self.window = win
        self.container = cont
    }
}

// MARK: - NSWindowDelegate

extension QuickTerminalController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // Auto-hide when losing focus (if enabled)
        if isVisible && !isAnimating && dependencies.settings.visorHideOnFocusLoss {
            hide()
        }
    }
}

// MARK: - Quick Terminal Window

/// A borderless floating window for the visor terminal.
private final class QuickTerminalWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private var themeObserver: NSObjectProtocol?
    private weak var handleBar: NSView?

    private func configure() {
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovable = false
        hasShadow = true
        isOpaque = true
        backgroundColor = Theme.colors.frame
        appearance = NSAppearance(named: .darkAqua)
        level = .floating

        // Hide traffic lights
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(type)?.isHidden = true
        }

        // Round top corners
        if let contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 12
            contentView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            contentView.layer?.masksToBounds = true
        }

        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.backgroundColor = Theme.colors.frame
            self?.handleBar?.layer?.backgroundColor = Theme.textMuted.withAlphaComponent(0.3).cgColor
        }
    }

    /// Applies corner radius, shadow, and handle bar to the current contentView.
    /// Call after replacing contentView with the terminal container.
    func applyContentAppearance() {
        guard let contentView else { return }

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        contentView.layer?.masksToBounds = true

        // Handle bar indicator at the bottom center
        let handle = NSView()
        handle.wantsLayer = true
        handle.layer?.cornerRadius = 2
        handle.layer?.backgroundColor = Theme.textMuted.withAlphaComponent(0.3).cgColor
        handle.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(handle)

        NSLayoutConstraint.activate([
            handle.widthAnchor.constraint(equalToConstant: 40),
            handle.heightAnchor.constraint(equalToConstant: 4),
            handle.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            handle.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])

        self.handleBar = handle

        invalidateShadow()
    }

    deinit {
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
    }
}
