import AppKit

// MARK: - Flipped Document View

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Unified Layout Constants

private let hPad: CGFloat = 24
private let labelW: CGFloat = 80
private let rowH: CGFloat = 40
private let sectionGap: CGFloat = 20
private let rowGap: CGFloat = 4
private let headerH: CGFloat = 24

// MARK: - Window Controller

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 580),
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
        window.minSize = NSSize(width: 560, height: 460)

        super.init(window: window)
        window.contentView = PreferencesRootView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showWindow() {
        (window?.contentView as? PreferencesRootView)?.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Root View (sidebar + content)

private final class PreferencesRootView: NSView {
    private let sidebar = PrefSidebar()
    private let divider = NSView()
    private var panes: [String: NSView] = [:]
    private var activePane: NSView?
    private let contentClip = NSView()

    private let sidebarWidth: CGFloat = 160

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

        panes["appearance"] = AppearancePane()
        panes["terminal"] = TerminalPane()
        panes["keybindings"] = KeybindingsPane()

        for (_, pane) in panes { contentClip.addSubview(pane); pane.isHidden = true }

        showPane("appearance")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        layer?.backgroundColor = Theme.base.cgColor
        window?.backgroundColor = Theme.base
        sidebar.refresh()
        (panes["appearance"] as? AppearancePane)?.refresh()
    }

    private func showPane(_ id: String) {
        activePane?.isHidden = true
        activePane = panes[id]
        activePane?.isHidden = false
        sidebar.selected = id
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

private final class PrefSidebar: NSView {
    var onSelect: ((String) -> Void)?
    var selected: String = "appearance" { didSet { needsDisplay = true; updateItems() } }

    private struct Item { let id: String; let icon: String; let label: String }
    private let items: [Item] = [
        Item(id: "appearance", icon: "paintbrush", label: "Appearance"),
        Item(id: "terminal", icon: "terminal", label: "Terminal"),
        Item(id: "keybindings", icon: "keyboard", label: "Keybindings"),
    ]
    private var itemViews: [PrefSidebarItem] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        for item in items {
            let view = PrefSidebarItem(icon: item.icon, label: item.label)
            view.onClick = { [weak self] in self?.onSelect?(item.id) }
            addSubview(view)
            itemViews.append(view)
        }
        updateItems()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() { updateItems() }

    private func updateItems() {
        for (i, item) in items.enumerated() {
            itemViews[i].isSelected = item.id == selected
        }
    }

    override func layout() {
        super.layout()
        let topInset: CGFloat = 52
        let itemH: CGFloat = 32
        let padding: CGFloat = 12
        var y = bounds.height - topInset

        for view in itemViews {
            view.frame = NSRect(x: padding, y: y - itemH, width: bounds.width - padding * 2, height: itemH)
            y -= itemH + 2
        }
    }
}

private final class PrefSidebarItem: NSView {
    var onClick: (() -> Void)?
    var isSelected: Bool = false { didSet { needsDisplay = true } }

    private let iconView = NSImageView()
    private let label: NSTextField
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(icon: String, label text: String) {
        self.label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: text)
        iconView.contentTintColor = Theme.textSecondary
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = Theme.textSecondary
        addSubview(label)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 10, y: (h - 16) / 2, width: 16, height: 16)
        label.frame = NSRect(x: 34, y: (h - 16) / 2, width: bounds.width - 44, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            Theme.accent.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
            iconView.contentTintColor = Theme.accent
            label.textColor = Theme.textPrimary
        } else if isHovered {
            NSColor(white: 1, alpha: 0.04).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
            iconView.contentTintColor = Theme.textSecondary
            label.textColor = Theme.textSecondary
        } else {
            iconView.contentTintColor = Theme.textMuted
            label.textColor = Theme.textSecondary
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

// MARK: - ═══════════════════════════════════════
// MARK:   Appearance Pane
// MARK: - ═══════════════════════════════════════

private final class AppearancePane: NSView {
    private let settings = BellithSettings.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()

    // Theme
    private let themeHeader = SectionHeader("Theme")
    private var themeGrid: ThemeGridView!

    // Tab style
    private let tabLabel = RowLabel("Tab Style")
    private var tabSegment: PrefSegment!

    // Opacity
    private let opacityLabel = RowLabel("Opacity")
    private var opacityTrack: OpacityTrackView!

    // Padding
    private let padLabel = RowLabel("Padding")
    private let padXLabel = SmallLabel("H")
    private var padXField: MiniNumberField!
    private let padYLabel = SmallLabel("V")
    private var padYField: MiniNumberField!

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        addSubview(scroll)
        content.wantsLayer = true
        scroll.documentView = content

        themeGrid = ThemeGridView(settings: settings) { [weak self] in self?.refresh() }
        content.addSubview(themeHeader)
        content.addSubview(themeGrid)

        tabSegment = PrefSegment(labels: ["Sidebar", "Tab Bar"],
                                 selected: settings.tabMode == "sidebar" ? 0 : 1) { [weak self] idx in
            self?.settings.tabMode = idx == 0 ? "sidebar" : "tabbar"
            if let w = NSApp.windows.first(where: { $0.contentView is TerminalContainerView }),
               let c = w.contentView as? TerminalContainerView { c.applyTabMode() }
        }
        content.addSubview(tabLabel)
        content.addSubview(tabSegment)

        opacityTrack = OpacityTrackView(value: settings.backgroundOpacity) { [weak self] v in
            self?.settings.backgroundOpacity = v
        }
        content.addSubview(opacityLabel)
        content.addSubview(opacityTrack)

        padXField = MiniNumberField(value: settings.windowPaddingX, range: 0...40) { [weak self] v in
            self?.settings.windowPaddingX = v
        }
        padYField = MiniNumberField(value: settings.windowPaddingY, range: 0...60) { [weak self] v in
            self?.settings.windowPaddingY = v
        }
        content.addSubview(padLabel)
        content.addSubview(padXLabel)
        content.addSubview(padXField)
        content.addSubview(padYLabel)
        content.addSubview(padYField)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        themeGrid.refresh()
        window?.backgroundColor = Theme.base
        superview?.superview?.layer?.backgroundColor = Theme.base.cgColor
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let w = bounds.width
        let ctlX = hPad + labelW + 12
        let ctlW = w - ctlX - hPad
        let gridH: CGFloat = 124

        var y: CGFloat = hPad

        // Theme section
        themeHeader.frame = NSRect(x: hPad, y: y, width: w - hPad * 2, height: headerH)
        y += headerH + rowGap

        themeGrid.frame = NSRect(x: hPad, y: y, width: w - hPad * 2, height: gridH)
        y += gridH + sectionGap

        // Tab style row
        tabLabel.frame = NSRect(x: hPad, y: y + (rowH - 16) / 2, width: labelW, height: 16)
        tabSegment.frame = NSRect(x: ctlX, y: y + (rowH - 28) / 2, width: min(180, ctlW), height: 28)
        y += rowH + rowGap

        // Opacity row
        opacityLabel.frame = NSRect(x: hPad, y: y + (rowH - 16) / 2, width: labelW, height: 16)
        opacityTrack.frame = NSRect(x: ctlX, y: y + (rowH - 24) / 2, width: ctlW, height: 24)
        y += rowH + rowGap

        // Padding row
        padLabel.frame = NSRect(x: hPad, y: y + (rowH - 16) / 2, width: labelW, height: 16)
        let fieldW: CGFloat = 48
        let miniLabelW: CGFloat = 14
        padXLabel.frame = NSRect(x: ctlX, y: y + (rowH - 16) / 2, width: miniLabelW, height: 16)
        padXField.frame = NSRect(x: ctlX + miniLabelW + 4, y: y + (rowH - 28) / 2, width: fieldW, height: 28)
        padYLabel.frame = NSRect(x: ctlX + miniLabelW + fieldW + 16, y: y + (rowH - 16) / 2, width: miniLabelW, height: 16)
        padYField.frame = NSRect(x: ctlX + miniLabelW * 2 + fieldW + 20, y: y + (rowH - 28) / 2, width: fieldW, height: 28)
        y += rowH + hPad

        content.frame = NSRect(x: 0, y: 0, width: w, height: max(y, bounds.height))
    }
}

// MARK: - ═══════════════════════════════════════
// MARK:   Terminal Pane
// MARK: - ═══════════════════════════════════════

private final class TerminalPane: NSView {
    private let settings = BellithSettings.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let fontHeader = SectionHeader("Font")
    private let fontLabel = RowLabel("Family")
    private var fontField: PrefTextField!
    private let sizeLabel = RowLabel("Size")
    private var sizeMinus: StepButton!
    private let sizeValue = ValueBadge()
    private var sizePlus: StepButton!

    private let cursorHeader = SectionHeader("Cursor")
    private let cursorLabel = RowLabel("Style")
    private var cursorSegment: PrefSegment!
    private let blinkLabel = RowLabel("Blink")
    private var blinkToggle: PrefToggle!

    private let shellHeader = SectionHeader("Shell")
    private let shellLabel = RowLabel("Command")
    private var shellField: PrefTextField!
    private let shellNote = FooterNote("Leave empty for default login shell")
    private let scrollLabel = RowLabel("Scrollback")
    private var scrollField: MiniNumberField!
    private let scrollUnit = SmallLabel("lines")

    private let behaviorHeader = SectionHeader("Behavior")
    private let hideMouseLabel = RowLabel("Hide cursor")
    private var hideMouseToggle: PrefToggle!
    private let confirmLabel = RowLabel("Confirm close")
    private var confirmToggle: PrefToggle!

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        addSubview(scroll)
        content.wantsLayer = true
        scroll.documentView = content

        // Font
        fontField = PrefTextField(text: settings.fontFamily) { [weak self] v in self?.settings.fontFamily = v }
        sizeValue.stringValue = "\(settings.fontSize)"
        sizeMinus = StepButton(symbol: "minus") { [weak self] in
            guard let self else { return }
            self.settings.fontSize = max(8, self.settings.fontSize - 1)
            self.sizeValue.stringValue = "\(self.settings.fontSize)"
        }
        sizePlus = StepButton(symbol: "plus") { [weak self] in
            guard let self else { return }
            self.settings.fontSize = min(36, self.settings.fontSize + 1)
            self.sizeValue.stringValue = "\(self.settings.fontSize)"
        }
        for v: NSView in [fontHeader, fontLabel, fontField, sizeLabel, sizeMinus, sizeValue, sizePlus] {
            content.addSubview(v)
        }

        // Cursor
        cursorSegment = PrefSegment(labels: ["Block", "Bar", "Underline"],
                                    selected: ["block": 0, "bar": 1, "underline": 2][settings.cursorStyle] ?? 0) { [weak self] idx in
            self?.settings.cursorStyle = ["block", "bar", "underline"][idx]
        }
        blinkToggle = PrefToggle(isOn: settings.cursorBlink) { [weak self] v in self?.settings.cursorBlink = v }
        for v: NSView in [cursorHeader, cursorLabel, cursorSegment, blinkLabel, blinkToggle] {
            content.addSubview(v)
        }

        // Shell
        shellField = PrefTextField(text: settings.shell) { [weak self] v in self?.settings.shell = v }
        scrollField = MiniNumberField(value: settings.scrollbackLines, range: 100...1_000_000) { [weak self] v in
            self?.settings.scrollbackLines = v
        }
        for v: NSView in [shellHeader, shellLabel, shellField, shellNote, scrollLabel, scrollField, scrollUnit] {
            content.addSubview(v)
        }

        // Behavior
        hideMouseToggle = PrefToggle(isOn: settings.mouseHideWhileTyping) { [weak self] v in self?.settings.mouseHideWhileTyping = v }
        confirmToggle = PrefToggle(isOn: settings.confirmClose) { [weak self] v in self?.settings.confirmClose = v }
        for v: NSView in [behaviorHeader, hideMouseLabel, hideMouseToggle, confirmLabel, confirmToggle] {
            content.addSubview(v)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let w = bounds.width
        let ctlX = hPad + labelW + 12
        let ctlW = w - ctlX - hPad

        var y: CGFloat = hPad

        // Font section
        fontHeader.frame = NSRect(x: hPad, y: y, width: w - hPad * 2, height: headerH)
        y += headerH + rowGap

        fontLabel.frame = NSRect(x: hPad, y: y + (rowH - 16) / 2, width: labelW, height: 16)
        fontField.frame = NSRect(x: ctlX, y: y + (rowH - 28) / 2, width: ctlW, height: 28)
        y += rowH + rowGap

        sizeLabel.frame = NSRect(x: hPad, y: y + (rowH - 16) / 2, width: labelW, height: 16)
        let btnS: CGFloat = 28
        sizeMinus.frame = NSRect(x: ctlX, y: y + (rowH - btnS) / 2, width: btnS, height: btnS)
        sizeValue.frame = NSRect(x: ctlX + btnS + 6, y: y + (rowH - 20) / 2, width: 36, height: 20)
        sizePlus.frame = NSRect(x: ctlX + btnS + 48, y: y + (rowH - btnS) / 2, width: btnS, height: btnS)
        y += rowH + sectionGap

        // Cursor section
        cursorHeader.frame = NSRect(x: hPad, y: y, width: w - hPad * 2, height: headerH)
        y += headerH + rowGap

        cursorLabel.frame = NSRect(x: hPad, y: y + (rowH - 16) / 2, width: labelW, height: 16)
        cursorSegment.frame = NSRect(x: ctlX, y: y + (rowH - 28) / 2, width: min(220, ctlW), height: 28)
        y += rowH + rowGap

        blinkLabel.frame = NSRect(x: hPad, y: y + (rowH - 16) / 2, width: labelW, height: 16)
        blinkToggle.frame = NSRect(x: ctlX, y: y + (rowH - 22) / 2, width: 50, height: 28)
        y += rowH + sectionGap

        // Shell section
        shellHeader.frame = NSRect(x: hPad, y: y, width: w - hPad * 2, height: headerH)
        y += headerH + rowGap

        shellLabel.frame = NSRect(x: hPad, y: y + (rowH - 16) / 2, width: labelW, height: 16)
        shellField.frame = NSRect(x: ctlX, y: y + (rowH - 28) / 2, width: ctlW, height: 28)
        y += rowH
        shellNote.frame = NSRect(x: ctlX, y: y, width: ctlW, height: 14)
        y += 14 + rowGap

        scrollLabel.frame = NSRect(x: hPad, y: y + (rowH - 16) / 2, width: labelW, height: 16)
        scrollField.frame = NSRect(x: ctlX, y: y + (rowH - 28) / 2, width: 80, height: 28)
        scrollUnit.frame = NSRect(x: ctlX + 86, y: y + (rowH - 14) / 2, width: 40, height: 14)
        y += rowH + sectionGap

        // Behavior section
        behaviorHeader.frame = NSRect(x: hPad, y: y, width: w - hPad * 2, height: headerH)
        y += headerH + rowGap

        hideMouseLabel.frame = NSRect(x: hPad, y: y + (rowH - 16) / 2, width: labelW, height: 16)
        hideMouseToggle.frame = NSRect(x: ctlX, y: y + (rowH - 22) / 2, width: 50, height: 28)
        y += rowH + rowGap

        confirmLabel.frame = NSRect(x: hPad, y: y + (rowH - 16) / 2, width: labelW, height: 16)
        confirmToggle.frame = NSRect(x: ctlX, y: y + (rowH - 22) / 2, width: 50, height: 28)
        y += rowH + hPad

        content.frame = NSRect(x: 0, y: 0, width: w, height: max(y, bounds.height))
    }
}

// MARK: - ═══════════════════════════════════════
// MARK:   Keybindings Pane
// MARK: - ═══════════════════════════════════════

private final class KeybindingsPane: NSView {
    private let settings = BellithSettings.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()
    private var rows: [NSView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        addSubview(scroll)
        content.wantsLayer = true
        scroll.documentView = content
        buildRows()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func buildRows() {
        rows.forEach { $0.removeFromSuperview() }
        rows.removeAll()

        let bindings = settings.keybindings
        var lastCategory = ""

        for (i, binding) in bindings.enumerated() {
            if binding.category != lastCategory {
                let header = SectionHeader(binding.category)
                content.addSubview(header)
                rows.append(header)
                lastCategory = binding.category
            }

            let row = KeybindingActionRow(binding: binding, index: i)
            row.onShortcutChanged = { [weak self] idx, shortcut in
                guard let self else { return }
                var all = self.settings.keybindings
                all[idx].shortcut = shortcut
                self.settings.keybindings = all
            }
            content.addSubview(row)
            rows.append(row)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        let w = bounds.width

        var y: CGFloat = hPad

        for row in rows {
            let isHeader = row is SectionHeader
            let h: CGFloat = isHeader ? headerH : rowH

            if isHeader && y > hPad {
                y += sectionGap
            }

            row.frame = NSRect(x: hPad, y: y, width: w - hPad * 2, height: h)
            y += h + rowGap
        }

        y += hPad

        content.frame = NSRect(x: 0, y: 0, width: w, height: max(y, bounds.height))
    }
}

// Keybinding action row (no longer inherits from a shared base)
private final class KeybindingActionRow: NSView {
    var onShortcutChanged: ((Int, KeyShortcut) -> Void)?
    private let binding: KeyBindingEntry
    private let index: Int
    private let actionLabel: NSTextField
    private let shortcutBadge: ShortcutBadge
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(binding: KeyBindingEntry, index: Int) {
        self.binding = binding
        self.index = index
        self.actionLabel = NSTextField(labelWithString: binding.label)
        self.shortcutBadge = ShortcutBadge(shortcut: binding.shortcut)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        actionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        actionLabel.textColor = Theme.textPrimary
        addSubview(actionLabel)
        addSubview(shortcutBadge)

        shortcutBadge.onNewShortcut = { [weak self] shortcut in
            guard let self else { return }
            self.onShortcutChanged?(self.index, shortcut)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        actionLabel.frame = NSRect(x: 14, y: (h - 16) / 2, width: bounds.width - 180, height: 16)
        shortcutBadge.frame = NSRect(x: bounds.width - 160, y: (h - 28) / 2, width: 150, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Subtle bottom separator
        Theme.border.setFill()
        NSRect(x: 14, y: bounds.height - 0.5, width: bounds.width - 28, height: 0.5).fill()
    }
}

// MARK: - Shortcut Badge (click to record)

private final class ShortcutBadge: NSView {
    var onNewShortcut: ((KeyShortcut) -> Void)?
    private var shortcut: KeyShortcut
    private var isRecording = false
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private let recordingLabel = NSTextField(labelWithString: "")

    init(shortcut: KeyShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        wantsLayer = true

        recordingLabel.font = .systemFont(ofSize: 11, weight: .medium)
        recordingLabel.textColor = Theme.accent
        recordingLabel.alignment = .center
        recordingLabel.isEditable = false
        recordingLabel.isBezeled = false
        recordingLabel.drawsBackground = false
        recordingLabel.isHidden = true
        addSubview(recordingLabel)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        recordingLabel.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        if isRecording {
            // Pulsing recording state
            Theme.accent.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
            Theme.accent.withAlphaComponent(0.3).setStroke()
            let bp = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            bp.lineWidth = 1.5
            bp.setLineDash([4, 3], count: 2, phase: 0)
            bp.stroke()
            return
        }

        // Render individual keycaps
        let keys = shortcut.keycapStrings
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.textSecondary]

        let capH: CGFloat = 22
        let capPad: CGFloat = 7
        let capGap: CGFloat = 3
        let capR: CGFloat = 5

        // Measure total width
        var totalW: CGFloat = 0
        var widths: [CGFloat] = []
        for key in keys {
            let size = (key as NSString).size(withAttributes: attrs)
            let w = max(22, size.width + capPad * 2)
            widths.append(w)
            totalW += w
        }
        totalW += CGFloat(max(0, keys.count - 1)) * capGap

        // Draw right-aligned
        var x = bounds.width - totalW
        let y = (bounds.height - capH) / 2

        for (i, key) in keys.enumerated() {
            let w = widths[i]
            let capRect = NSRect(x: x, y: y, width: w, height: capH)

            // Cap background with subtle gradient effect
            let capBg = isHovered ? Theme.overlay : Theme.surface.withAlphaComponent(0.6)
            capBg.setFill()
            NSBezierPath(roundedRect: capRect, xRadius: capR, yRadius: capR).fill()

            // Cap border
            Theme.border.setStroke()
            let borderPath = NSBezierPath(roundedRect: capRect.insetBy(dx: 0.5, dy: 0.5), xRadius: capR, yRadius: capR)
            borderPath.lineWidth = 0.5
            borderPath.stroke()

            // Bottom shadow edge (makes it look 3D)
            let shadowRect = NSRect(x: capRect.minX + 2, y: capRect.maxY - 1, width: capRect.width - 4, height: 1)
            NSColor(white: 0, alpha: 0.15).setFill()
            NSBezierPath(roundedRect: shadowRect, xRadius: 0.5, yRadius: 0.5).fill()

            // Text centered
            let textSize = (key as NSString).size(withAttributes: attrs)
            let textX = capRect.midX - textSize.width / 2
            let textY = capRect.midY - textSize.height / 2
            (key as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

            x += w + capGap
        }
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        recordingLabel.stringValue = "Press shortcut\u{2026}"
        recordingLabel.isHidden = false
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { cancelRecording(); return }
        if let newShortcut = KeyShortcut.from(event: event) {
            shortcut = newShortcut
            isRecording = false
            recordingLabel.isHidden = true
            needsDisplay = true
            onNewShortcut?(newShortcut)
        }
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { cancelRecording() }
        return super.resignFirstResponder()
    }

    private func cancelRecording() {
        isRecording = false
        recordingLabel.isHidden = true
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
}

// MARK: - ═══════════════════════════════════════
// MARK:   Shared Components
// MARK: - ═══════════════════════════════════════

// Section header with subtle line
private final class SectionHeader: NSView {
    private let label: NSTextField
    init(_ text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = Theme.textMuted
        addSubview(label)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let textW = label.attributedStringValue.size().width + 4
        label.frame = NSRect(x: 0, y: (bounds.height - 14) / 2, width: textW, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        let textW = label.attributedStringValue.size().width + 12
        let lineY = bounds.height / 2
        Theme.border.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: textW, y: lineY))
        path.line(to: NSPoint(x: bounds.width, y: lineY))
        path.lineWidth = 0.5
        path.stroke()
    }
}

// Row label
private final class RowLabel: NSTextField {
    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text
        font = .systemFont(ofSize: 13)
        textColor = Theme.textSecondary
        isEditable = false; isBezeled = false; drawsBackground = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

// Small inline label
private final class SmallLabel: NSTextField {
    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text
        font = .systemFont(ofSize: 11, weight: .medium)
        textColor = Theme.textMuted
        isEditable = false; isBezeled = false; drawsBackground = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

// Footer note
private final class FooterNote: NSTextField {
    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text
        font = .systemFont(ofSize: 11)
        textColor = Theme.textMuted
        isEditable = false; isBezeled = false; drawsBackground = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

// Value badge (centered number)
private final class ValueBadge: NSTextField {
    init() {
        super.init(frame: .zero)
        font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        textColor = Theme.textPrimary
        alignment = .center
        isEditable = false; isBezeled = false; drawsBackground = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Custom Segmented Control

private final class PrefSegment: NSView {
    private var selected: Int
    private let onChange: (Int) -> Void
    private var buttons: [NSButton] = []

    init(labels: [String], selected: Int, onChange: @escaping (Int) -> Void) {
        self.selected = selected
        self.onChange = onChange
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = Theme.base.cgColor
        layer?.borderColor = Theme.border.cgColor
        layer?.borderWidth = 0.5

        for (i, title) in labels.enumerated() {
            let btn = NSButton(title: title, target: self, action: #selector(tapped(_:)))
            btn.tag = i
            btn.isBordered = false
            btn.font = .systemFont(ofSize: 12, weight: .medium)
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            addSubview(btn)
            buttons.append(btn)
        }
        updateAppearance()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let count = CGFloat(buttons.count)
        let inset: CGFloat = 3
        let btnW = (bounds.width - inset * 2) / count
        for (i, btn) in buttons.enumerated() {
            btn.frame = NSRect(x: inset + CGFloat(i) * btnW, y: inset, width: btnW, height: bounds.height - inset * 2)
        }
    }

    @objc private func tapped(_ sender: NSButton) {
        selected = sender.tag
        updateAppearance()
        onChange(selected)
    }

    private func updateAppearance() {
        for (i, btn) in buttons.enumerated() {
            if i == selected {
                btn.contentTintColor = Theme.textPrimary
                btn.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.15).cgColor
            } else {
                btn.contentTintColor = Theme.textSecondary
                btn.layer?.backgroundColor = .clear
            }
        }
    }
}

// MARK: - Custom Toggle

private final class PrefToggle: NSView {
    private var isOn: Bool
    private let onChange: (Bool) -> Void
    private var trackingArea: NSTrackingArea?

    init(isOn: Bool, onChange: @escaping (Bool) -> Void) {
        self.isOn = isOn
        self.onChange = onChange
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let trackW: CGFloat = 44
        let trackH: CGFloat = 24
        let trackRect = NSRect(x: 0, y: (bounds.height - trackH) / 2, width: trackW, height: trackH)
        let trackColor = isOn ? Theme.accent : Theme.overlay
        trackColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackH / 2, yRadius: trackH / 2).fill()

        if !isOn {
            Theme.border.setStroke()
            NSBezierPath(roundedRect: trackRect.insetBy(dx: 0.5, dy: 0.5), xRadius: trackH / 2, yRadius: trackH / 2).stroke()
        }

        // Knob
        let knobD: CGFloat = 18
        let knobInset: CGFloat = 3
        let knobX: CGFloat = isOn ? trackRect.maxX - knobD - knobInset : trackRect.minX + knobInset
        let knobY = trackRect.midY - knobD / 2
        // Shadow
        NSColor(white: 0, alpha: 0.2).setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX, y: knobY - 1, width: knobD, height: knobD)).fill()
        // Knob
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX, y: knobY, width: knobD, height: knobD)).fill()
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        onChange(isOn)
        needsDisplay = true
    }
}

// MARK: - Custom Opacity Track

private final class OpacityTrackView: NSView {
    private var value: Double
    private let onChange: (Double) -> Void
    private let percentLabel: NSTextField

    init(value: Double, onChange: @escaping (Double) -> Void) {
        self.value = value
        self.onChange = onChange
        self.percentLabel = NSTextField(labelWithString: "\(Int(value * 100))%")
        super.init(frame: .zero)
        wantsLayer = true
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        percentLabel.textColor = Theme.textMuted
        percentLabel.alignment = .right
        addSubview(percentLabel)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        percentLabel.frame = NSRect(x: bounds.width - 38, y: (bounds.height - 14) / 2, width: 38, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackW = bounds.width - 48
        let trackH: CGFloat = 4
        let trackY = (bounds.height - trackH) / 2

        Theme.base.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: trackY, width: trackW, height: trackH), xRadius: 2, yRadius: 2).fill()

        let fillW = trackW * CGFloat(value)
        Theme.accent.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: trackY, width: fillW, height: trackH), xRadius: 2, yRadius: 2).fill()

        let thumbR: CGFloat = 7
        NSColor(white: 0.85, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: fillW - thumbR, y: bounds.height / 2 - thumbR, width: thumbR * 2, height: thumbR * 2)).fill()
    }

    override func mouseDown(with event: NSEvent) { updateValue(from: event) }
    override func mouseDragged(with event: NSEvent) { updateValue(from: event) }

    private func updateValue(from event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let trackW = bounds.width - 48
        value = min(1.0, max(0.3, Double(loc.x / trackW)))
        onChange(value)
        percentLabel.stringValue = "\(Int(value * 100))%"
        needsDisplay = true
    }
}

// MARK: - Text Field

private final class PrefTextField: NSView {
    private let field: NSTextField
    private let onChange: (String) -> Void

    init(text: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        self.field = NSTextField(string: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = Theme.base.cgColor
        layer?.borderColor = Theme.border.cgColor
        layer?.borderWidth = 0.5

        field.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        field.textColor = Theme.textPrimary
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.target = self
        field.action = #selector(edited)
        addSubview(field)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        field.frame = bounds.insetBy(dx: 10, dy: 4)
    }

    @objc private func edited() { onChange(field.stringValue) }
}

// MARK: - Mini Number Field

private final class MiniNumberField: NSView {
    private let field: NSTextField
    private let range: ClosedRange<Int>
    private let onChange: (Int) -> Void

    init(value: Int, range: ClosedRange<Int>, onChange: @escaping (Int) -> Void) {
        self.range = range
        self.onChange = onChange
        self.field = NSTextField(string: "\(value)")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = Theme.base.cgColor
        layer?.borderColor = Theme.border.cgColor
        layer?.borderWidth = 0.5

        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        field.textColor = Theme.textPrimary
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.alignment = .center
        field.target = self
        field.action = #selector(edited)
        addSubview(field)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        field.frame = bounds.insetBy(dx: 4, dy: 4)
    }

    @objc private func edited() {
        let val = max(range.lowerBound, min(range.upperBound, Int(field.stringValue) ?? range.lowerBound))
        field.stringValue = "\(val)"
        onChange(val)
    }
}

// MARK: - Step Button

private final class StepButton: NSView {
    private let action: () -> Void
    private let symbol: NSImage?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(symbol name: String, action: @escaping () -> Void) {
        self.action = action
        self.symbol = NSImage(systemSymbolName: name, accessibilityDescription: name)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        (isHovered ? Theme.overlay : Theme.base).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        Theme.border.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()

        if let img = symbol {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            let tinted = img.withSymbolConfiguration(config)
            let s: CGFloat = 14
            tinted?.draw(in: NSRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s),
                         from: .zero, operation: .sourceOver, fraction: isHovered ? 0.9 : 0.5)
        }
    }

    override func mouseDown(with event: NSEvent) { action() }
    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
}

// MARK: - Theme Grid

private final class ThemeGridView: NSView {
    private let settings: BellithSettings
    private let onApply: () -> Void
    private var cells: [ThemeCell] = []

    init(settings: BellithSettings, onApply: @escaping () -> Void) {
        self.settings = settings
        self.onApply = onApply
        super.init(frame: .zero)
        for theme in ThemeColors.allThemes {
            let cell = ThemeCell(theme: theme, isSelected: theme.name == settings.themeName)
            cell.onSelect = { [weak self] t in
                guard let self else { return }
                self.settings.themeName = t.name
                ThemeManager.shared.apply(t)
                self.refresh()
                self.onApply()
            }
            addSubview(cell)
            cells.append(cell)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        for c in cells { c.isSelected = c.theme.name == settings.themeName; c.needsDisplay = true }
    }

    override func layout() {
        super.layout()
        let cols = 3
        let spacing: CGFloat = 8
        let cellW = (bounds.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let cellH: CGFloat = 54
        for (i, cell) in cells.enumerated() {
            let col = i % cols
            let row = i / cols
            cell.frame = NSRect(
                x: CGFloat(col) * (cellW + spacing),
                y: bounds.height - CGFloat(row + 1) * (cellH + spacing) + spacing,
                width: cellW, height: cellH)
        }
    }
}

private final class ThemeCell: NSView {
    let theme: ThemeColors
    var isSelected: Bool
    var onSelect: ((ThemeColors) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private let nameLabel: NSTextField

    init(theme: ThemeColors, isSelected: Bool) {
        self.theme = theme
        self.isSelected = isSelected
        self.nameLabel = NSTextField(labelWithString: theme.name)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        toolTip = theme.name
        nameLabel.font = .systemFont(ofSize: 9.5, weight: .medium)
        nameLabel.textColor = theme.textSecondary
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        nameLabel.frame = NSRect(x: 4, y: 3, width: bounds.width - 8, height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        theme.base.setFill()
        NSBezierPath(roundedRect: b, xRadius: 8, yRadius: 8).fill()

        let barInset: CGFloat = 10
        theme.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: barInset, y: 20, width: b.width - barInset * 2, height: 5),
                     xRadius: 2.5, yRadius: 2.5).fill()

        let dotR: CGFloat = 2.5
        let dotGap: CGFloat = 7
        let totalDotsW = 3 * (dotR * 2) + 2 * dotGap
        let startX = (b.width - totalDotsW) / 2
        for (i, c) in [theme.textPrimary, theme.textSecondary, theme.textMuted].enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: startX + CGFloat(i) * (dotR * 2 + dotGap), y: b.height - 13, width: dotR * 2, height: dotR * 2)).fill()
        }

        let bc: NSColor = isSelected ? theme.accent.withAlphaComponent(0.8) : (isHovered ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 1, alpha: 0.04))
        bc.setStroke()
        let bp = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        bp.lineWidth = isSelected ? 1.5 : 0.5
        bp.stroke()
    }

    override func updateTrackingAreas() {
        if let a = trackingArea { removeTrackingArea(a) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onSelect?(theme) }
}
