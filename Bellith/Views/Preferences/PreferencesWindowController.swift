import AppKit

// MARK: - Flipped Document View

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Window Controller

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private let settings: BellithSettings
    private let themeManager: ThemeManager
    private var settingsObserver: NSObjectProtocol?
    private var themeObserver: NSObjectProtocol?

    init(settings: BellithSettings = .shared, themeManager: ThemeManager = .shared) {
        self.settings = settings
        self.themeManager = themeManager
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.base
        window.center()
        window.minSize = NSSize(width: 680, height: 560)
        window.setFrameAutosaveName("BellithPreferencesWindow")

        super.init(window: window)
        window.contentView = PreferencesRootView()
        applyWindowAppearance()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: BellithSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyWindowAppearance()
            (self?.window?.contentView as? PreferencesRootView)?.refresh()
        }

        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.window?.backgroundColor = Theme.base
            (self?.window?.contentView as? PreferencesRootView)?.refresh()
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showWindow(selecting paneID: String? = nil) {
        applyWindowAppearance()
        let root = window?.contentView as? PreferencesRootView
        root?.refresh()
        if let paneID {
            root?.selectPane(paneID)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyWindowAppearance() {
        window?.appearance = Theme.overlayAppearance
        window?.backgroundColor = Theme.base
    }
}

// MARK: - Root View (sidebar + content)

final class PreferencesRootView: NSView {
    private let sidebar = PrefSidebar()
    private let divider = NSView()
    private var panes: [String: NSView] = [:]
    private var activePane: NSView?
    private var activePaneId: String = ""
    private let contentClip = NSView()

    private let sidebarWidth: CGFloat = 196

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.base.cgColor

        addSubview(sidebar)
        sidebar.onSelect = { [weak self] id in self?.showPane(id) }

        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.border.cgColor
        addSubview(divider)

        contentClip.wantsLayer = true
        contentClip.layer?.backgroundColor = Theme.base.cgColor
        addSubview(contentClip)

        for plugin in PreferencesPaneRegistry.shared.allPlugins {
            let pane = plugin.makePane()
            panes[plugin.id] = pane
            contentClip.addSubview(pane)
            pane.isHidden = true
        }

        if let initialPaneID = PreferencesPaneRegistry.shared.mainPlugins.first?.id {
            showPane(initialPaneID)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        layer?.backgroundColor = Theme.base.cgColor
        window?.backgroundColor = Theme.base
        contentClip.layer?.backgroundColor = Theme.base.cgColor
        divider.layer?.backgroundColor = Theme.border.cgColor
        sidebar.refresh()
        for pane in panes.values {
            (pane as? PreferencesPaneRefreshable)?.refreshPreferencesPane()
        }
    }

    func selectPane(_ id: String) {
        showPane(id)
    }

    private func showPane(_ id: String) {
        guard id != activePaneId, let nextPane = panes[id] else { return }
        let oldPane = activePane

        activePane = nextPane
        activePane?.isHidden = false
        activePane?.alphaValue = 0
        activePane?.frame = contentClip.bounds
        sidebar.selected = id
        activePaneId = id

        Theme.animate(duration: 0.18, timing: CAMediaTimingFunction(name: .easeOut), { _ in
            oldPane?.animator().alphaValue = 0
            nextPane.animator().alphaValue = 1
        }, completion: {
            oldPane?.isHidden = true
            oldPane?.alphaValue = 1
        })

        needsLayout = true
    }

    override func layout() {
        super.layout()
        sidebar.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height)
        divider.frame = NSRect(x: sidebarWidth, y: 14, width: 1, height: bounds.height - 28)
        let contentX = sidebarWidth + 1
        contentClip.frame = NSRect(x: contentX, y: 0, width: bounds.width - contentX, height: bounds.height)
        activePane?.frame = contentClip.bounds
    }
}

// MARK: - Sidebar

final class PrefSidebar: NSView {
    var onSelect: ((String) -> Void)?
    var selected: String = PreferencesPaneRegistry.shared.mainPlugins.first?.id ?? "appearance" {
        didSet { needsDisplay = true; updateItems() }
    }

    private let mainItems = PreferencesPaneRegistry.shared.mainPlugins
    private let bottomItems = PreferencesPaneRegistry.shared.footerPlugins
    private var mainViews: [PrefSidebarItem] = []
    private var bottomViews: [PrefSidebarItem] = []
    private let logoView = NSImageView()
    private let overlineLabel = NSTextField(labelWithString: "BELLITH")
    private let titleLabel = NSTextField(labelWithString: "SETTINGS")
    private let versionLabel = NSTextField(labelWithString: "")
    private let separatorLine = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        logoView.image = BellithBranding.logoImage(accessibilityDescription: BellithBranding.appName)
        logoView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(logoView)

        overlineLabel.font = BellithFont.mono(10, weight: .regular)
        overlineLabel.textColor = Theme.textSecondary
        addSubview(overlineLabel)

        titleLabel.font = BellithFont.display(24)
        titleLabel.textColor = Theme.textDisplay
        addSubview(titleLabel)

        let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        versionLabel.stringValue = "[V\(ver)]"
        versionLabel.font = BellithFont.mono(10, weight: .regular)
        versionLabel.textColor = Theme.textMuted
        addSubview(versionLabel)

        for item in mainItems {
            let view = PrefSidebarItem(icon: item.iconName, label: item.title)
            view.onClick = { [weak self] in self?.onSelect?(item.id) }
            addSubview(view)
            mainViews.append(view)
        }

        separatorLine.wantsLayer = true
        separatorLine.layer?.backgroundColor = Theme.border.cgColor
        addSubview(separatorLine)

        for item in bottomItems {
            let view = PrefSidebarItem(icon: item.iconName, label: item.title)
            view.onClick = { [weak self] in self?.onSelect?(item.id) }
            addSubview(view)
            bottomViews.append(view)
        }

        updateItems()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        layer?.backgroundColor = Theme.chromePanel.cgColor
        overlineLabel.textColor = Theme.textSecondary
        titleLabel.textColor = Theme.textDisplay
        versionLabel.textColor = Theme.textMuted
        logoView.alphaValue = 0.96
        separatorLine.layer?.backgroundColor = Theme.border.cgColor
        updateItems()
        needsDisplay = true
    }

    private func updateItems() {
        for (i, item) in mainItems.enumerated() {
            mainViews[i].isSelected = item.id == selected
        }
        for (i, item) in bottomItems.enumerated() {
            bottomViews[i].isSelected = item.id == selected
        }
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 14
        let itemH: CGFloat = 36
        let itemGap: CGFloat = 6
        let logoSize: CGFloat = 24
        let topSafeArea = max(safeAreaInsets.top, 28)
        let headerHeight: CGFloat = 56
        let headerTopInset = topSafeArea + 16
        let headerBottom = bounds.height - headerTopInset - headerHeight
        let headerIconX = padding + 14
        let headerTextX = padding + 38
        let headerTextWidth = bounds.width - headerTextX - padding

        logoView.frame = NSRect(x: headerIconX, y: headerBottom + 16, width: logoSize, height: logoSize)
        overlineLabel.frame = NSRect(x: headerTextX, y: headerBottom + 40, width: headerTextWidth, height: 14)
        titleLabel.frame = NSRect(x: headerTextX, y: headerBottom + 18, width: headerTextWidth, height: 20)
        versionLabel.frame = NSRect(x: headerTextX, y: headerBottom, width: headerTextWidth, height: 12)

        var y = headerBottom - 22
        for view in mainViews {
            view.frame = NSRect(x: padding, y: y - itemH, width: bounds.width - padding * 2, height: itemH)
            y -= itemH + itemGap
        }

        var bottomY: CGFloat = padding
        for view in bottomViews.reversed() {
            view.frame = NSRect(x: padding, y: bottomY, width: bounds.width - padding * 2, height: itemH)
            bottomY += itemH + itemGap
        }

        separatorLine.frame = NSRect(x: padding + 14, y: bottomY + 8, width: bounds.width - padding * 2 - 28, height: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chromePanel.setFill()
        dirtyRect.fill()
    }
}

final class PrefSidebarItem: NSView {
    var onClick: (() -> Void)?
    var isSelected: Bool = false { didSet { needsDisplay = true; updateColors() } }

    private let iconView = NSImageView()
    private let label: NSTextField
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(icon: String, label text: String) {
        self.label = NSTextField(labelWithString: text.uppercased())
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10

        setAccessibilityRole(.button)
        setAccessibilityLabel(text)

        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: text)
        iconView.contentTintColor = Theme.textTertiary
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        label.font = BellithFont.mono(11, weight: .regular)
        label.textColor = Theme.textSecondary
        addSubview(label)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func updateColors() {
        if isSelected {
            iconView.contentTintColor = Theme.textDisplay
            label.textColor = Theme.textDisplay
        } else {
            iconView.contentTintColor = Theme.textTertiary
            label.textColor = isHovered ? Theme.textPrimary : Theme.textSecondary
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 14, y: (h - 14) / 2, width: 14, height: 14)
        label.frame = NSRect(x: 38, y: (h - 14) / 2, width: bounds.width - 50, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        if isSelected {
            Theme.chromeElevated.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()

            Theme.accent.setFill()
            NSBezierPath(roundedRect: NSRect(x: 8, y: 8, width: 2, height: rect.height - 16), xRadius: 1, yRadius: 1).fill()
        } else if isHovered {
            Theme.hoverOverlay.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        }
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36:
            onClick?()
        default:
            super.keyDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateColors()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateColors()
        needsDisplay = true
    }
}
