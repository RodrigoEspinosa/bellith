import AppKit

// MARK: - Sidebar Pane

final class SidebarPane: NSView {
    private let settings: BellithSettings
    private let smartPanelRegistry: SmartPanelRegistry
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let paneTitleLabel = NSTextField(labelWithString: "Sidebar")
    private let paneSubtitleLabel = NSTextField(labelWithString: "Navigation behavior, quick tools, and floating state.")

    private let behaviorCard = SettingsCard(title: "Behavior", subtitle: "Launch state and floating sidebar behavior")
    private let pinnedLabel = CardRowLabel("Pin Sidebar by Default")
    private var pinnedToggle: PrefToggle!
    private let autoHideLabel = CardRowLabel("Auto-hide When Floating")
    private var autoHideToggle: PrefToggle!

    private let toolsCard = SettingsCard(title: "Quick Tools", subtitle: "Show smart panels directly in the sidebar")
    private let showToolsLabel = CardRowLabel("Show Tools Section")
    private let showToolsNote = FooterNote("Turns the entire Tools group in the sidebar on or off.")
    private let toolsDivider = NSView()
    private let toolListLabel = SmallLabel("Included Panels")
    private let toolListNote = FooterNote("These toggles control which panels appear inside that section.")
    private var showToolsToggle: PrefToggle!
    private var toolToggles: [(plugin: SmartPanelPlugin, label: CardRowLabel, toggle: PrefToggle)] = []

    init(
        frame frameRect: NSRect = .zero,
        settings: BellithSettings = .shared,
        smartPanelRegistry: SmartPanelRegistry = .shared
    ) {
        self.settings = settings
        self.smartPanelRegistry = smartPanelRegistry
        super.init(frame: frameRect)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        addSubview(scroll)

        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.frame.cgColor
        scroll.documentView = content

        paneTitleLabel.font = BellithFont.ui(20, weight: .medium)
        paneTitleLabel.textColor = Theme.textDisplay
        content.addSubview(paneTitleLabel)

        paneSubtitleLabel.font = BellithFont.ui(12, weight: .regular)
        paneSubtitleLabel.textColor = Theme.textSecondary
        content.addSubview(paneSubtitleLabel)

        pinnedToggle = PrefToggle(isOn: settings.sidebarPinned) { [weak self] value in
            self?.settings.sidebarPinned = value
        }
        autoHideToggle = PrefToggle(isOn: settings.sidebarAutoHide) { [weak self] value in
            self?.settings.sidebarAutoHide = value
        }
        content.addSubview(behaviorCard)
        behaviorCard.addSubview(pinnedLabel)
        behaviorCard.addSubview(pinnedToggle)
        behaviorCard.addSubview(autoHideLabel)
        behaviorCard.addSubview(autoHideToggle)

        showToolsToggle = PrefToggle(isOn: settings.sidebarShowTools) { [weak self] value in
            self?.settings.sidebarShowTools = value
            self?.updateToolToggleStates()
        }
        toolsDivider.wantsLayer = true
        content.addSubview(toolsCard)
        toolsCard.addSubview(showToolsLabel)
        toolsCard.addSubview(showToolsNote)
        toolsCard.addSubview(toolsDivider)
        toolsCard.addSubview(toolListLabel)
        toolsCard.addSubview(toolListNote)
        toolsCard.addSubview(showToolsToggle)

        let enabledTools = settings.sidebarTools
        for plugin in smartPanelRegistry.allPlugins {
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
        content.layer?.backgroundColor = Theme.frame.cgColor
        paneTitleLabel.textColor = Theme.textDisplay
        paneSubtitleLabel.textColor = Theme.textSecondary
        behaviorCard.refresh()
        toolsCard.refresh()
        toolsDivider.layer?.backgroundColor = Theme.chromeHairline.cgColor
        showToolsNote.textColor = Theme.textTertiary
        toolListLabel.textColor = Theme.textTertiary
        toolListNote.textColor = Theme.textMuted
        pinnedToggle.setOn(settings.sidebarPinned)
        autoHideToggle.setOn(settings.sidebarAutoHide)
        showToolsToggle.setOn(settings.sidebarShowTools)
        for entry in toolToggles {
            entry.toggle.setOn(settings.sidebarTools.contains(entry.plugin.id))
        }
        updateToolToggleStates()
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
    }

    private func updateToolToggleStates() {
        let enabled = settings.sidebarShowTools
        toolsDivider.isHidden = !enabled
        toolListLabel.isHidden = !enabled
        toolListNote.isHidden = !enabled
        for entry in toolToggles {
            entry.label.isHidden = !enabled
            entry.toggle.isHidden = !enabled
            entry.label.alphaValue = enabled ? 1.0 : 0.45
            entry.toggle.alphaValue = enabled ? 1.0 : 0.45
        }
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let width = bounds.width
        let cardW = width - PreferencesLayout.hPad * 2
        let toggleLabelWidth = PreferencesLayout.labelWidth(toTrailingToggleIn: cardW)

        var y: CGFloat = PreferencesLayout.hPad

        paneTitleLabel.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: 280, height: 24)
        paneSubtitleLabel.frame = NSRect(x: PreferencesLayout.hPad, y: y + 28, width: cardW, height: 16)
        y += 60

        let behaviorRows: CGFloat = 2
        let behaviorCardHeight = behaviorCard.headerHeight
            + behaviorRows * PreferencesLayout.rowH
            + PreferencesLayout.rowGap
            + PreferencesLayout.cardPad
        behaviorCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: behaviorCardHeight)
        let br0 = behaviorCardHeight - behaviorCard.headerHeight - PreferencesLayout.rowH
        pinnedLabel.frame = BellithDesignSystem.Settings.leadingLabelFrame(rowY: br0, width: toggleLabelWidth)
        pinnedToggle.frame = BellithDesignSystem.Settings.trailingToggleFrame(cardWidth: cardW, rowY: br0)
        let br1 = br0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        autoHideLabel.frame = BellithDesignSystem.Settings.leadingLabelFrame(rowY: br1, width: toggleLabelWidth)
        autoHideToggle.frame = BellithDesignSystem.Settings.trailingToggleFrame(cardWidth: cardW, rowY: br1)
        y += behaviorCardHeight + PreferencesLayout.sectionGap

        let showTools = settings.sidebarShowTools
        let visibleToolRows = showTools ? toolToggles.count : 0
        let toolRowStep: CGFloat = 48
        let toolsCardHeight = toolsCard.headerHeight
            + PreferencesLayout.rowH
            + 18
            + (showTools ? 112 + CGFloat(visibleToolRows) * toolRowStep : 0)
            + PreferencesLayout.cardPad
        toolsCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: toolsCardHeight)
        let tr0 = toolsCardHeight - toolsCard.headerHeight - PreferencesLayout.rowH
        showToolsLabel.frame = BellithDesignSystem.Settings.leadingLabelFrame(rowY: tr0, width: toggleLabelWidth)
        showToolsToggle.frame = BellithDesignSystem.Settings.trailingToggleFrame(cardWidth: cardW, rowY: tr0)
        showToolsNote.frame = NSRect(x: PreferencesLayout.cardPad, y: tr0 - 14, width: toggleLabelWidth, height: 14)

        if showTools {
            let dividerY = tr0 - 44
            toolsDivider.frame = NSRect(
                x: PreferencesLayout.cardPad,
                y: dividerY,
                width: cardW - PreferencesLayout.cardPad * 2,
                height: 1
            )
            toolListLabel.frame = NSRect(x: PreferencesLayout.cardPad + 16, y: dividerY - 26, width: 180, height: 12)
            toolListNote.frame = NSRect(x: PreferencesLayout.cardPad + 16, y: dividerY - 42, width: toggleLabelWidth, height: 14)

            var rowY = dividerY - 92
            for entry in toolToggles {
                let labelX = PreferencesLayout.cardPad + 20
                entry.label.frame = NSRect(
                    x: labelX,
                    y: rowY,
                    width: PreferencesLayout.labelWidth(toTrailingToggleIn: cardW, from: labelX),
                    height: PreferencesLayout.rowH
                )
                entry.toggle.frame = BellithDesignSystem.Settings.trailingToggleFrame(cardWidth: cardW, rowY: rowY)
                rowY -= toolRowStep
            }
        }

        y += toolsCardHeight + PreferencesLayout.hPad
        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, bounds.height))
    }
}

extension SidebarPane: PreferencesPaneRefreshable {
    func refreshPreferencesPane() { refresh() }
}
