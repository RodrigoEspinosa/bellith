import AppKit

// MARK: - Sidebar Pane

final class SidebarPane: NSView {
    private let settings = BellithSettings.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()

    // Behavior card
    private let behaviorCard = SettingsCard(title: "Behavior")
    private let pinnedLabel = CardRowLabel("Pin sidebar by default")
    private var pinnedToggle: PrefToggle!

    // Tools card
    private let toolsCard = SettingsCard(title: "Quick Tools", subtitle: "Show tool shortcuts in the sidebar")
    private let showToolsLabel = CardRowLabel("Show tools section")
    private var showToolsToggle: PrefToggle!
    private var toolToggles: [(plugin: SmartPanelPlugin, label: CardRowLabel, toggle: PrefToggle)] = []

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

        // Behavior card
        pinnedToggle = PrefToggle(isOn: settings.sidebarPinned) { [weak self] v in
            self?.settings.sidebarPinned = v
        }
        content.addSubview(behaviorCard)
        behaviorCard.addSubview(pinnedLabel)
        behaviorCard.addSubview(pinnedToggle)

        // Tools card
        showToolsToggle = PrefToggle(isOn: settings.sidebarShowTools) { [weak self] v in
            self?.settings.sidebarShowTools = v
            self?.updateToolToggleStates()
        }
        content.addSubview(toolsCard)
        toolsCard.addSubview(showToolsLabel)
        toolsCard.addSubview(showToolsToggle)

        let enabledTools = settings.sidebarTools
        for plugin in SmartPanelRegistry.shared.allPlugins {
            let label = CardRowLabel(plugin.title)
            let isEnabled = enabledTools.contains(plugin.id)
            let toggle = PrefToggle(isOn: isEnabled) { [weak self] v in
                self?.handleToolToggle(plugin: plugin, enabled: v)
            }
            toolsCard.addSubview(label)
            toolsCard.addSubview(toggle)
            toolToggles.append((plugin: plugin, label: label, toggle: toggle))
        }

        updateToolToggleStates()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func handleToolToggle(plugin: SmartPanelPlugin, enabled: Bool) {
        var tools = settings.sidebarTools
        if enabled {
            if !tools.contains(plugin.id) {
                tools.append(plugin.id)
            }
        } else {
            tools.removeAll { $0 == plugin.id }
        }
        settings.sidebarTools = tools
    }

    private func updateToolToggleStates() {
        let enabled = settings.sidebarShowTools
        for entry in toolToggles {
            entry.label.alphaValue = enabled ? 1.0 : 0.4
            entry.toggle.alphaValue = enabled ? 1.0 : 0.4
            entry.toggle.isHidden = !enabled
            entry.label.isHidden = !enabled
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let w = bounds.width
        let cardW = w - PreferencesLayout.hPad * 2
        let innerW = cardW - PreferencesLayout.cardPad * 2
        let ctlX: CGFloat = 180
        let ctlW = innerW - ctlX

        var y: CGFloat = PreferencesLayout.hPad

        // Behavior card (1 row)
        let behaviorCardH = behaviorCard.headerHeight + PreferencesLayout.rowH + PreferencesLayout.cardPad
        behaviorCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: behaviorCardH)

        let br0 = behaviorCardH - behaviorCard.headerHeight - PreferencesLayout.rowH
        pinnedLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: br0 + (PreferencesLayout.rowH - 16) / 2, width: 170, height: 16)
        pinnedToggle.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: br0 + (PreferencesLayout.rowH - 22) / 2, width: 50, height: 28)

        y += behaviorCardH + PreferencesLayout.sectionGap

        // Tools card
        let showTools = settings.sidebarShowTools
        let toolRowCount = showTools ? toolToggles.count : 0
        let toolsCardH = toolsCard.headerHeight
            + PreferencesLayout.rowH  // show tools toggle row
            + (showTools ? PreferencesLayout.rowGap + 8 : 0)
            + CGFloat(toolRowCount) * PreferencesLayout.rowH
            + CGFloat(max(0, toolRowCount - 1)) * PreferencesLayout.rowGap
            + PreferencesLayout.cardPad

        toolsCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: toolsCardH)

        // Row 0: Show tools toggle
        let tr0 = toolsCardH - toolsCard.headerHeight - PreferencesLayout.rowH
        showToolsLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: tr0 + (PreferencesLayout.rowH - 16) / 2, width: 170, height: 16)
        showToolsToggle.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: tr0 + (PreferencesLayout.rowH - 22) / 2, width: 50, height: 28)

        // Individual tool toggles
        if showTools {
            var toolY = tr0 - PreferencesLayout.rowGap - 8
            let toolLabelX: CGFloat = PreferencesLayout.cardPad + 8

            for entry in toolToggles {
                toolY -= PreferencesLayout.rowH
                entry.label.frame = NSRect(x: toolLabelX, y: toolY + (PreferencesLayout.rowH - 16) / 2, width: 160, height: 16)
                entry.toggle.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: toolY + (PreferencesLayout.rowH - 22) / 2, width: 50, height: 28)
                toolY -= PreferencesLayout.rowGap
            }
        }

        y += toolsCardH + PreferencesLayout.hPad

        content.frame = NSRect(x: 0, y: 0, width: w, height: max(y, bounds.height))
    }
}
