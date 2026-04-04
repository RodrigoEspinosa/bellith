import AppKit

// MARK: - Appearance Pane

final class AppearancePane: NSView {
    private let settings = BellithSettings.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()

    // Theme card
    private let themeCard = SettingsCard(title: "Theme", subtitle: "Choose your color scheme")
    private var themeGrid: ThemeGridView!

    // Layout card
    private let layoutCard = SettingsCard(title: "Layout")
    private let tabLabel = CardRowLabel("Tab Style")
    private var tabSegment: PrefSegment!
    private let padLabel = CardRowLabel("Padding")
    private let padXLabel = SmallLabel("H")
    private var padXField: MiniNumberField!
    private let padYLabel = SmallLabel("V")
    private var padYField: MiniNumberField!

    // Appearance card
    private let modeCard = SettingsCard(title: "Appearance Mode", subtitle: "Affects window chrome and system integration")
    private let modeLabel = CardRowLabel("Mode")
    private var modeSegment: PrefSegment!
    private let importBtn = LinkButton(title: "Import Theme…")

    // Window card
    private let windowCard = SettingsCard(title: "Window")
    private let opacityLabel = CardRowLabel("Opacity")
    private var opacityTrack: OpacityTrackView!
    private let trafficLightLabel = CardRowLabel("Auto-hide traffic lights")
    private var trafficLightToggle: PrefToggle!

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

        // Theme card
        themeGrid = ThemeGridView(settings: settings) { [weak self] in self?.refresh() }
        content.addSubview(themeCard)
        themeCard.addSubview(themeGrid)

        // Layout card
        tabSegment = PrefSegment(labels: ["Sidebar", "Tab Bar"],
                                 selected: settings.tabMode == "sidebar" ? 0 : 1) { [weak self] idx in
            self?.settings.tabMode = idx == 0 ? "sidebar" : "tabbar"
            if let w = NSApp.windows.first(where: { $0.contentView is TerminalContainerView }),
               let c = w.contentView as? TerminalContainerView { c.applyTabMode() }
        }
        padXField = MiniNumberField(value: settings.windowPaddingX, range: 0...40) { [weak self] v in
            self?.settings.windowPaddingX = v
        }
        padYField = MiniNumberField(value: settings.windowPaddingY, range: 0...60) { [weak self] v in
            self?.settings.windowPaddingY = v
        }
        content.addSubview(layoutCard)
        for v: NSView in [tabLabel, tabSegment, padLabel, padXLabel, padXField, padYLabel, padYField] {
            layoutCard.addSubview(v)
        }

        // Appearance mode card
        let modeIdx = ["dark": 0, "light": 1, "system": 2][settings.appearanceMode] ?? 0
        modeSegment = PrefSegment(labels: ["Dark", "Light", "System"], selected: modeIdx) { [weak self] idx in
            self?.settings.appearanceMode = ["dark", "light", "system"][idx]
        }
        importBtn.onClick = {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = true
            panel.message = "Select theme JSON files to import"
            if panel.runModal() == .OK {
                for url in panel.urls {
                    if let dest = CustomThemeLoader.shared.themesDirectory?.appendingPathComponent(url.lastPathComponent) {
                        try? FileManager.default.copyItem(at: url, to: dest)
                    }
                }
                CustomThemeLoader.shared.reload()
            }
        }
        content.addSubview(modeCard)
        modeCard.addSubview(modeLabel)
        modeCard.addSubview(modeSegment)
        modeCard.addSubview(importBtn)

        // Window card
        opacityTrack = OpacityTrackView(value: settings.backgroundOpacity) { [weak self] v in
            self?.settings.backgroundOpacity = v
        }
        trafficLightToggle = PrefToggle(isOn: settings.trafficLightAutoHide) { [weak self] v in
            self?.settings.trafficLightAutoHide = v
        }
        content.addSubview(windowCard)
        windowCard.addSubview(opacityLabel)
        windowCard.addSubview(opacityTrack)
        windowCard.addSubview(trafficLightLabel)
        windowCard.addSubview(trafficLightToggle)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        themeGrid.refresh()
        themeCard.refresh()
        layoutCard.refresh()
        windowCard.refresh()
        window?.backgroundColor = Theme.base
        superview?.superview?.layer?.backgroundColor = Theme.base.cgColor
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let w = bounds.width
        let cardW = w - PreferencesLayout.hPad * 2
        let innerW = cardW - PreferencesLayout.cardPad * 2
        let ctlX: CGFloat = 90
        let ctlW = innerW - ctlX

        var y: CGFloat = PreferencesLayout.hPad

        // Theme card
        let gridH: CGFloat = 124
        let themeCardH = themeCard.headerHeight + gridH + PreferencesLayout.cardPad
        themeCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: themeCardH)
        themeGrid.frame = NSRect(x: PreferencesLayout.cardPad, y: PreferencesLayout.cardPad, width: innerW, height: gridH)
        y += themeCardH + PreferencesLayout.sectionGap

        // Layout card
        let layoutCardH = layoutCard.headerHeight + 2 * PreferencesLayout.rowH + PreferencesLayout.rowGap + PreferencesLayout.cardPad
        layoutCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: layoutCardH)

        let lr0 = layoutCardH - layoutCard.headerHeight - PreferencesLayout.rowH
        tabLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: lr0 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        tabSegment.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: lr0 + (PreferencesLayout.rowH - 28) / 2, width: min(180, ctlW), height: 28)
        let lr1 = lr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap

        padLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: lr1 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        let fieldW: CGFloat = 48
        let miniLabelW: CGFloat = 14
        padXLabel.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: lr1 + (PreferencesLayout.rowH - 16) / 2, width: miniLabelW, height: 16)
        padXField.frame = NSRect(x: PreferencesLayout.cardPad + ctlX + miniLabelW + 4, y: lr1 + (PreferencesLayout.rowH - 28) / 2, width: fieldW, height: 28)
        padYLabel.frame = NSRect(x: PreferencesLayout.cardPad + ctlX + miniLabelW + fieldW + 16, y: lr1 + (PreferencesLayout.rowH - 16) / 2, width: miniLabelW, height: 16)
        padYField.frame = NSRect(x: PreferencesLayout.cardPad + ctlX + miniLabelW * 2 + fieldW + 20, y: lr1 + (PreferencesLayout.rowH - 28) / 2, width: fieldW, height: 28)

        y += layoutCardH + PreferencesLayout.sectionGap

        // Appearance mode card
        let modeCardH = modeCard.headerHeight + 2 * PreferencesLayout.rowH + PreferencesLayout.rowGap + PreferencesLayout.cardPad
        modeCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: modeCardH)
        let mr0 = modeCardH - modeCard.headerHeight - PreferencesLayout.rowH
        modeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: mr0 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        modeSegment.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: mr0 + (PreferencesLayout.rowH - 28) / 2, width: min(220, ctlW), height: 28)
        let mr1 = mr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        importBtn.frame = NSRect(x: PreferencesLayout.cardPad, y: mr1 + (PreferencesLayout.rowH - 16) / 2, width: innerW, height: 16)
        y += modeCardH + PreferencesLayout.sectionGap

        // Window card
        let windowCardH = windowCard.headerHeight + 2 * PreferencesLayout.rowH + PreferencesLayout.rowGap + PreferencesLayout.cardPad
        windowCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: windowCardH)
        let wy0 = windowCardH - windowCard.headerHeight - PreferencesLayout.rowH
        opacityLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: wy0 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        opacityTrack.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: wy0 + (PreferencesLayout.rowH - 24) / 2, width: ctlW, height: 24)
        let wy1 = wy0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        trafficLightLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: wy1 + (PreferencesLayout.rowH - 16) / 2, width: 160, height: 16)
        trafficLightToggle.frame = NSRect(x: PreferencesLayout.cardPad + 168, y: wy1 + (PreferencesLayout.rowH - 22) / 2, width: 50, height: 28)
        y += windowCardH + PreferencesLayout.hPad

        content.frame = NSRect(x: 0, y: 0, width: w, height: max(y, bounds.height))
    }
}
