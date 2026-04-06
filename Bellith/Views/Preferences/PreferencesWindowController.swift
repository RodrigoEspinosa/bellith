import AppKit

// MARK: - Flipped Document View

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Window Controller

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.base
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.minSize = NSSize(width: 600, height: 500)

        super.init(window: window)
        window.contentView = PreferencesRootView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showWindow() {
        (window?.contentView as? PreferencesRootView)?.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
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

    private let sidebarWidth: CGFloat = 180

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
        sidebar.refresh()
        for pane in panes.values {
            (pane as? PreferencesPaneRefreshable)?.refreshPreferencesPane()
        }
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

        // Crossfade transition
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            oldPane?.animator().alphaValue = 0
            activePane?.animator().alphaValue = 1
        }, completionHandler: {
            oldPane?.isHidden = true
            oldPane?.alphaValue = 1
        })

        needsLayout = true
    }

    override func layout() {
        super.layout()
        sidebar.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height)
        divider.frame = NSRect(x: sidebarWidth, y: 12, width: 0.5, height: bounds.height - 24)
        let contentX = sidebarWidth + 0.5
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
    private let brandLabel = NSTextField(labelWithString: "Bellith")
    private let versionLabel = NSTextField(labelWithString: "")
    private let separatorLine = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        // Brand label at top
        brandLabel.font = .systemFont(ofSize: 15, weight: .bold)
        brandLabel.textColor = Theme.textPrimary
        brandLabel.alphaValue = 0.7
        addSubview(brandLabel)

        let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        versionLabel.stringValue = "v\(ver)"
        versionLabel.font = .systemFont(ofSize: 10, weight: .medium)
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
        brandLabel.textColor = Theme.textPrimary
        versionLabel.textColor = Theme.textMuted
        separatorLine.layer?.backgroundColor = Theme.border.cgColor
        updateItems()
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
        let padding: CGFloat = 12
        let itemH: CGFloat = 34

        // Brand area at top
        brandLabel.frame = NSRect(x: padding + 10, y: bounds.height - 46, width: bounds.width - padding * 2, height: 18)
        versionLabel.frame = NSRect(x: padding + 10, y: bounds.height - 60, width: bounds.width - padding * 2, height: 14)

        // Main items below brand
        var y = bounds.height - 76
        for view in mainViews {
            view.frame = NSRect(x: padding, y: y - itemH, width: bounds.width - padding * 2, height: itemH)
            y -= itemH + 2
        }

        // Bottom items
        var bottomY: CGFloat = padding
        for view in bottomViews.reversed() {
            view.frame = NSRect(x: padding, y: bottomY, width: bounds.width - padding * 2, height: itemH)
            bottomY += itemH + 2
        }

        // Separator just above bottom items
        separatorLine.frame = NSRect(x: padding + 10, y: bottomY + 4, width: bounds.width - padding * 2 - 20, height: 0.5)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Subtle gradient background for sidebar
        let gradient = NSGradient(colors: [
            Theme.surface.withAlphaComponent(0.3),
            Theme.base,
        ])
        gradient?.draw(in: bounds, angle: 180)
    }
}

final class PrefSidebarItem: NSView {
    var onClick: (() -> Void)?
    var isSelected: Bool = false { didSet { needsDisplay = true; updateColors() } }

    private let iconView = NSImageView()
    private let label: NSTextField
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(icon: String, label text: String) {
        self.label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        // Accessibility
        setAccessibilityRole(.button)
        setAccessibilityLabel(text)

        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: text)
        iconView.contentTintColor = Theme.textSecondary
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = Theme.textSecondary
        addSubview(label)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func updateColors() {
        if isSelected {
            iconView.contentTintColor = Theme.accent
            label.textColor = Theme.textPrimary
        } else {
            iconView.contentTintColor = Theme.textMuted
            label.textColor = Theme.textSecondary
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 10, y: (h - 16) / 2, width: 16, height: 16)
        label.frame = NSRect(x: 34, y: (h - 16) / 2, width: bounds.width - 44, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            // Accent glow background
            Theme.accent.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
            // Left accent bar
            Theme.accent.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: NSRect(x: 2, y: bounds.height * 0.2, width: 3, height: bounds.height * 0.6),
                         xRadius: 1.5, yRadius: 1.5).fill()
        } else if isHovered {
            NSColor(white: 1, alpha: 0.04).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
}
