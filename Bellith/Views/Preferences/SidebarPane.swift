import AppKit

// MARK: - Sidebar Pane

final class SidebarPane: NSView {
    private let settings = BellithSettings.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let heroCard = SettingsCard(title: "Sidebar State", subtitle: "Navigation density and quick-access modules")
    private let heroStateLabel = NSTextField(labelWithString: "")
    private let heroMetaLabel = NSTextField(labelWithString: "")
    private let heroCountLabel = NSTextField(labelWithString: "")

    private let behaviorCard = SettingsCard(title: "Behavior", subtitle: "How the main navigation should appear on launch")
    private let pinnedLabel = CardRowLabel("Pin Sidebar by Default")
    private var pinnedToggle: PrefToggle!

    private let toolsCard = SettingsCard(title: "Quick Tools", subtitle: "Show smart panels directly in the sidebar")
    private let showToolsLabel = CardRowLabel("Show Tools Section")
    private var showToolsToggle: PrefToggle!
    private var toolToggles: [(plugin: SmartPanelPlugin, label: CardRowLabel, toggle: PrefToggle)] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        addSubview(scroll)

        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.base.cgColor
        scroll.documentView = content

        heroStateLabel.font = BellithFont.display(34)
        heroStateLabel.textColor = Theme.textDisplay
        heroMetaLabel.font = BellithFont.mono(11, weight: .regular)
        heroMetaLabel.textColor = Theme.textSecondary
        heroCountLabel.font = BellithFont.mono(12, weight: .regular)
        heroCountLabel.textColor = Theme.textPrimary
        content.addSubview(heroCard)
        for view in [heroStateLabel, heroMetaLabel, heroCountLabel] {
            heroCard.addSubview(view)
        }

        pinnedToggle = PrefToggle(isOn: settings.sidebarPinned) { [weak self] value in
            self?.settings.sidebarPinned = value
            self?.updateHero()
        }
        content.addSubview(behaviorCard)
        behaviorCard.addSubview(pinnedLabel)
        behaviorCard.addSubview(pinnedToggle)

        showToolsToggle = PrefToggle(isOn: settings.sidebarShowTools) { [weak self] value in
            self?.settings.sidebarShowTools = value
            self?.updateToolToggleStates()
            self?.updateHero()
        }
        content.addSubview(toolsCard)
        toolsCard.addSubview(showToolsLabel)
        toolsCard.addSubview(showToolsToggle)

        let enabledTools = settings.sidebarTools
        for plugin in SmartPanelRegistry.shared.allPlugins {
            let label = CardRowLabel(plugin.title)
            let toggle = PrefToggle(isOn: enabledTools.contains(plugin.id)) { [weak self] enabled in
                self?.handleToolToggle(plugin: plugin, enabled: enabled)
            }
            toolsCard.addSubview(label)
            toolsCard.addSubview(toggle)
            toolToggles.append((plugin: plugin, label: label, toggle: toggle))
        }

        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        content.layer?.backgroundColor = Theme.base.cgColor
        heroCard.refresh()
        behaviorCard.refresh()
        toolsCard.refresh()
        pinnedToggle.setOn(settings.sidebarPinned)
        showToolsToggle.setOn(settings.sidebarShowTools)
        for entry in toolToggles {
            entry.toggle.setOn(settings.sidebarTools.contains(entry.plugin.id))
        }
        updateToolToggleStates()
        updateHero()
        needsLayout = true
    }

    private func handleToolToggle(plugin: SmartPanelPlugin, enabled: Bool) {
        var tools = settings.sidebarTools
        if enabled {
            if !tools.contains(plugin.id) { tools.append(plugin.id) }
        } else {
            tools.removeAll { $0 == plugin.id }
        }
        settings.sidebarTools = tools
        updateHero()
    }

    private func updateToolToggleStates() {
        let enabled = settings.sidebarShowTools
        for entry in toolToggles {
            entry.label.isHidden = !enabled
            entry.toggle.isHidden = !enabled
        }
    }

    private func updateHero() {
        let enabledCount = settings.sidebarShowTools ? settings.sidebarTools.count : 0
        heroStateLabel.stringValue = settings.sidebarPinned ? "PINNED" : "FLOATING"
        heroMetaLabel.stringValue = settings.tabMode == "sidebar" ? "[ PRIMARY NAVIGATION ]" : "[ SECONDARY NAVIGATION ]"
        heroCountLabel.stringValue = settings.sidebarShowTools
            ? "\(enabledCount) TOOL\(enabledCount == 1 ? "" : "S") ENABLED"
            : "TOOLS HIDDEN"
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let width = bounds.width
        let cardW = width - PreferencesLayout.hPad * 2
        let labelW: CGFloat = 176
        let controlX = PreferencesLayout.cardPad + labelW

        var y: CGFloat = PreferencesLayout.hPad

        let heroHeight: CGFloat = 156
        heroCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: heroHeight)
        heroMetaLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 90, width: cardW - PreferencesLayout.cardPad * 2, height: 14)
        heroStateLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 46, width: cardW - PreferencesLayout.cardPad * 2, height: 40)
        heroCountLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 22, width: cardW - PreferencesLayout.cardPad * 2, height: 16)
        y += heroHeight + PreferencesLayout.sectionGap

        let behaviorCardHeight = behaviorCard.headerHeight + PreferencesLayout.rowH + PreferencesLayout.cardPad
        behaviorCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: behaviorCardHeight)
        let br0 = behaviorCardHeight - behaviorCard.headerHeight - PreferencesLayout.rowH
        pinnedLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: br0, width: labelW, height: PreferencesLayout.rowH)
        pinnedToggle.frame = NSRect(x: controlX, y: br0 + 6, width: 50, height: 28)
        y += behaviorCardHeight + PreferencesLayout.sectionGap

        let showTools = settings.sidebarShowTools
        let visibleToolRows = showTools ? toolToggles.count : 0
        let toolsCardHeight = toolsCard.headerHeight
            + PreferencesLayout.rowH
            + (showTools ? PreferencesLayout.rowGap + CGFloat(visibleToolRows) * PreferencesLayout.rowH + CGFloat(max(0, visibleToolRows - 1)) * PreferencesLayout.rowGap : 0)
            + PreferencesLayout.cardPad
        toolsCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: toolsCardHeight)
        let tr0 = toolsCardHeight - toolsCard.headerHeight - PreferencesLayout.rowH
        showToolsLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: tr0, width: labelW, height: PreferencesLayout.rowH)
        showToolsToggle.frame = NSRect(x: controlX, y: tr0 + 6, width: 50, height: 28)

        if showTools {
            var rowY = tr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
            for entry in toolToggles {
                entry.label.frame = NSRect(x: PreferencesLayout.cardPad + 10, y: rowY, width: labelW + 20, height: PreferencesLayout.rowH)
                entry.toggle.frame = NSRect(x: controlX, y: rowY + 6, width: 50, height: 28)
                rowY -= PreferencesLayout.rowH + PreferencesLayout.rowGap
            }
        }

        y += toolsCardHeight + PreferencesLayout.hPad
        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, bounds.height))
    }
}

extension SidebarPane: PreferencesPaneRefreshable {
    func refreshPreferencesPane() { refresh() }
}
