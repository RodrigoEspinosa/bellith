import AppKit

// MARK: - Appearance Pane

final class AppearancePane: NSView {
    private let settings: BellithSettings
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let paneTitleLabel = NSTextField(labelWithString: "Appearance")
    private let paneSubtitleLabel = NSTextField(labelWithString: "Choose theme pairs, window chrome, and status metadata.")
    private let importBtn = LinkButton(title: "Import Theme…")

    private let summaryCard = SettingsCard(title: "Current Pair", subtitle: "Dark and light defaults for new terminals")
    private let darkSummaryLabel = CardRowLabel("Dark")
    private let darkSummaryValue = NSTextField(labelWithString: "")
    private let lightSummaryLabel = CardRowLabel("Light")
    private let lightSummaryValue = NSTextField(labelWithString: "")
    private let activeSummaryLabel = CardRowLabel("Active Now")
    private let activeSummaryValue = NSTextField(labelWithString: "")
    private let activeSummaryNote = FooterNote("")
    private let appearanceModeLabel = CardRowLabel("Appearance Mode")
    private var appearanceModeSegment: PrefSegment!

    private let themeCard = SettingsCard(title: "Theme Library", subtitle: "Pick one library at a time, then select the default palette")
    private var themeGrid: ThemeGridView!

    private let interfaceCard = SettingsCard(title: "Interface", subtitle: "Window chrome and navigation structure")
    private let tabLabel = CardRowLabel("Tab Style")
    private var tabSegment: PrefSegment!
    private let statusBarLabel = CardRowLabel("Show Status Bar")
    private var statusBarToggle: PrefToggle!
    private let padLabel = CardRowLabel("Window Padding")
    private let padXLabel = SmallLabel("H")
    private var padXField: MiniNumberField!
    private let padYLabel = SmallLabel("V")
    private var padYField: MiniNumberField!

    private let windowCard = SettingsCard(title: "Window", subtitle: "Texture, chrome, and traffic-light behavior")
    private let noiseLabel = CardRowLabel("Noise Grain")
    private var noiseTrack: OpacityTrackView!
    private let oledChromeLabel = CardRowLabel("True-Black Chrome")
    private var oledChromeToggle: PrefToggle!
    private let trafficLightLabel = CardRowLabel("Auto-hide Traffic Lights")
    private var trafficLightToggle: PrefToggle!

    private let profileCard = SettingsCard(
        title: "Profile Appearance",
        subtitle: "Per-profile frame translucency and wallpaper tint"
    )
    private let profileSelectLabel = CardRowLabel("Active Profile")
    private let profilePopup = NSPopUpButton()
    private let translucencyLabel = CardRowLabel("Frame Translucency")
    private var translucencyTrack: OpacityTrackView!
    private let tintLabel = CardRowLabel("Wallpaper Tint")
    private var tintToggle: PrefToggle!

    private let statusBarCard = SettingsCard(title: "Status Bar", subtitle: "Choose which indicators appear in the lower metadata strip")
    private let statusBarContextLabel = CardRowLabel("Host & Environment")
    private var statusBarContextToggle: PrefToggle!
    private let statusBarPathLabel = CardRowLabel("Working Directory")
    private var statusBarPathToggle: PrefToggle!
    private let statusBarWorktreeLabel = CardRowLabel("Git Worktree")
    private var statusBarWorktreeToggle: PrefToggle!
    private let statusBarBranchLabel = CardRowLabel("Git Branch")
    private var statusBarBranchToggle: PrefToggle!
    private let statusBarGitHubLabel = CardRowLabel("PRs & Issues")
    private var statusBarGitHubToggle: PrefToggle!
    private let statusBarProcessLabel = CardRowLabel("Foreground Process")
    private var statusBarProcessToggle: PrefToggle!
    private let statusBarSizeLabel = CardRowLabel("Terminal Size")
    private var statusBarSizeToggle: PrefToggle!

    private static func segmentIndex(for mode: AppAppearanceMode) -> Int {
        switch mode {
        case .system: 0
        case .dark: 1
        case .light: 2
        }
    }

    init(frame frameRect: NSRect = .zero, settings: BellithSettings = .shared) {
        self.settings = settings
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

        importBtn.onClick = { [weak self] in self?.importThemes() }
        content.addSubview(importBtn)

        darkSummaryValue.font = BellithFont.mono(12, weight: .regular)
        darkSummaryValue.textColor = Theme.textPrimary
        darkSummaryValue.lineBreakMode = .byTruncatingTail
        lightSummaryValue.font = BellithFont.mono(12, weight: .regular)
        lightSummaryValue.textColor = Theme.textPrimary
        lightSummaryValue.lineBreakMode = .byTruncatingTail
        activeSummaryValue.font = BellithFont.mono(12, weight: .regular)
        activeSummaryValue.textColor = Theme.textDisplay
        activeSummaryValue.lineBreakMode = .byTruncatingTail
        activeSummaryNote.font = BellithFont.mono(10, weight: .regular)
        activeSummaryNote.textColor = Theme.textSecondary

        appearanceModeSegment = PrefSegment(
            labels: ["Auto", "Dark", "Light"],
            selected: Self.segmentIndex(for: settings.appearanceMode)
        ) { [weak self] index in
            guard let self else { return }
            switch index {
            case 1:
                self.settings.appearanceMode = .dark
            case 2:
                self.settings.appearanceMode = .light
            default:
                self.settings.appearanceMode = .system
            }
            self.updateSummary()
        }

        content.addSubview(summaryCard)
        for view: NSView in [
            darkSummaryLabel, darkSummaryValue,
            lightSummaryLabel, lightSummaryValue,
            activeSummaryLabel, activeSummaryValue,
            activeSummaryNote, appearanceModeLabel,
            appearanceModeSegment,
        ] {
            summaryCard.addSubview(view)
        }

        themeGrid = ThemeGridView(settings: settings) { [weak self] in
            self?.refresh()
        }
        content.addSubview(themeCard)
        themeCard.addSubview(themeGrid)

        tabSegment = PrefSegment(labels: ["Sidebar", "Tab Bar"], selected: settings.tabMode == "sidebar" ? 0 : 1) { [weak self] index in
            self?.settings.tabMode = index == 0 ? "sidebar" : "tabbar"
        }
        statusBarToggle = PrefToggle(isOn: settings.showStatusBar) { [weak self] value in
            self?.settings.showStatusBar = value
            self?.updateSummary()
        }
        padXField = MiniNumberField(value: settings.windowPaddingX, range: 0...40) { [weak self] value in
            self?.settings.windowPaddingX = value
        }
        padYField = MiniNumberField(value: settings.windowPaddingY, range: 0...60) { [weak self] value in
            self?.settings.windowPaddingY = value
        }
        content.addSubview(interfaceCard)
        for view: NSView in [tabLabel, tabSegment, statusBarLabel, statusBarToggle, padLabel, padXLabel, padXField, padYLabel, padYField] {
            interfaceCard.addSubview(view)
        }

        noiseTrack = OpacityTrackView(value: settings.noiseIntensity, minValue: 0.0) { [weak self] value in
            self?.settings.noiseIntensity = value
        }
        oledChromeToggle = PrefToggle(isOn: settings.oledChromeForDarkThemes) { [weak self] value in
            self?.settings.oledChromeForDarkThemes = value
        }
        trafficLightToggle = PrefToggle(isOn: settings.trafficLightAutoHide) { [weak self] value in
            self?.settings.trafficLightAutoHide = value
        }
        content.addSubview(windowCard)
        for view: NSView in [noiseLabel, noiseTrack, oledChromeLabel, oledChromeToggle, trafficLightLabel, trafficLightToggle] {
            windowCard.addSubview(view)
        }

        profilePopup.font = BellithFont.mono(12, weight: .regular)
        profilePopup.focusRingType = .none
        profilePopup.target = self
        profilePopup.action = #selector(handleProfileChanged)
        rebuildProfilePopup()

        let activeProfile = settings.activeProfile
        translucencyTrack = OpacityTrackView(
            value: activeProfile.effectiveFrameTranslucency(fallback: settings),
            minValue: 0.0
        ) { [weak self] value in
            self?.settings.updateActiveProfile { $0.backgroundOpacity = 1.0 - value }
        }
        tintToggle = PrefToggle(isOn: activeProfile.effectiveWallpaperTint()) { [weak self] value in
            self?.settings.updateActiveProfile { $0.wallpaperTint = value }
            WallpaperTint.shared.invalidate()
        }
        content.addSubview(profileCard)
        for view: NSView in [
            profileSelectLabel, profilePopup,
            translucencyLabel, translucencyTrack,
            tintLabel, tintToggle,
        ] {
            profileCard.addSubview(view)
        }

        statusBarContextToggle = PrefToggle(isOn: settings.showStatusBarContext) { [weak self] value in
            self?.settings.showStatusBarContext = value
        }
        statusBarPathToggle = PrefToggle(isOn: settings.showStatusBarPath) { [weak self] value in
            self?.settings.showStatusBarPath = value
        }
        statusBarWorktreeToggle = PrefToggle(isOn: settings.showStatusBarGitWorktree) { [weak self] value in
            self?.settings.showStatusBarGitWorktree = value
        }
        statusBarBranchToggle = PrefToggle(isOn: settings.showStatusBarGitBranch) { [weak self] value in
            self?.settings.showStatusBarGitBranch = value
        }
        statusBarGitHubToggle = PrefToggle(isOn: settings.showStatusBarGitHub) { [weak self] value in
            self?.settings.showStatusBarGitHub = value
        }
        statusBarProcessToggle = PrefToggle(isOn: settings.showStatusBarProcess) { [weak self] value in
            self?.settings.showStatusBarProcess = value
        }
        statusBarSizeToggle = PrefToggle(isOn: settings.showStatusBarSize) { [weak self] value in
            self?.settings.showStatusBarSize = value
        }
        content.addSubview(statusBarCard)
        for view: NSView in [
            statusBarContextLabel,
            statusBarContextToggle,
            statusBarPathLabel,
            statusBarPathToggle,
            statusBarWorktreeLabel,
            statusBarWorktreeToggle,
            statusBarBranchLabel,
            statusBarBranchToggle,
            statusBarGitHubLabel,
            statusBarGitHubToggle,
            statusBarProcessLabel,
            statusBarProcessToggle,
            statusBarSizeLabel,
            statusBarSizeToggle,
        ] {
            statusBarCard.addSubview(view)
        }

        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        content.layer?.backgroundColor = Theme.frame.cgColor
        paneTitleLabel.textColor = Theme.textDisplay
        paneSubtitleLabel.textColor = Theme.textSecondary

        summaryCard.refresh()
        themeCard.refresh()
        interfaceCard.refresh()
        windowCard.refresh()
        statusBarCard.refresh()
        themeGrid.refresh()

        tabSegment.setSelected(settings.tabMode == "sidebar" ? 0 : 1)
        tabSegment.refreshAppearance()
        statusBarToggle.setOn(settings.showStatusBar)
        statusBarToggle.refreshAppearance()
        statusBarContextToggle.setOn(settings.showStatusBarContext)
        statusBarContextToggle.refreshAppearance()
        statusBarPathToggle.setOn(settings.showStatusBarPath)
        statusBarPathToggle.refreshAppearance()
        statusBarWorktreeToggle.setOn(settings.showStatusBarGitWorktree)
        statusBarWorktreeToggle.refreshAppearance()
        statusBarBranchToggle.setOn(settings.showStatusBarGitBranch)
        statusBarBranchToggle.refreshAppearance()
        statusBarGitHubToggle.setOn(settings.showStatusBarGitHub)
        statusBarGitHubToggle.refreshAppearance()
        statusBarProcessToggle.setOn(settings.showStatusBarProcess)
        statusBarProcessToggle.refreshAppearance()
        statusBarSizeToggle.setOn(settings.showStatusBarSize)
        statusBarSizeToggle.refreshAppearance()
        padXField.setValue(settings.windowPaddingX)
        padYField.setValue(settings.windowPaddingY)
        rebuildProfilePopup()
        let active = settings.activeProfile
        translucencyTrack.setValue(active.effectiveFrameTranslucency(fallback: settings))
        tintToggle.setOn(active.effectiveWallpaperTint())
        tintToggle.refreshAppearance()
        profileCard.refresh()
        noiseTrack.setValue(settings.noiseIntensity)
        oledChromeToggle.setOn(settings.oledChromeForDarkThemes)
        oledChromeToggle.refreshAppearance()
        trafficLightToggle.setOn(settings.trafficLightAutoHide)
        trafficLightToggle.refreshAppearance()
        appearanceModeSegment.setSelected(Self.segmentIndex(for: settings.appearanceMode))
        appearanceModeSegment.refreshAppearance()

        updateSummary()
        needsLayout = true
    }

    private func updateSummary() {
        let activeTheme = settings.resolvedTheme

        darkSummaryValue.stringValue = settings.darkThemeName.uppercased()
        lightSummaryValue.stringValue = settings.lightThemeName.uppercased()
        activeSummaryValue.stringValue = activeTheme.name.uppercased()

        switch settings.appearanceMode {
        case .system:
            activeSummaryNote.stringValue = settings.systemIsDark
                ? "FOLLOWS SYSTEM · CURRENTLY DARK"
                : "FOLLOWS SYSTEM · CURRENTLY LIGHT"
        case .dark:
            activeSummaryNote.stringValue = "FORCED DARK MODE"
        case .light:
            activeSummaryNote.stringValue = "FORCED LIGHT MODE"
        }

        darkSummaryValue.textColor = Theme.textPrimary
        lightSummaryValue.textColor = Theme.textPrimary
        activeSummaryValue.textColor = Theme.textDisplay
        activeSummaryNote.textColor = Theme.textSecondary
    }

    private func rebuildProfilePopup() {
        profilePopup.removeAllItems()
        let list = settings.profiles
        for profile in list {
            profilePopup.addItem(withTitle: profile.name)
            profilePopup.lastItem?.representedObject = profile.id
        }
        let activeID = settings.activeProfileID
        if let index = list.firstIndex(where: { $0.id == activeID }) {
            profilePopup.selectItem(at: index)
        }
    }

    @objc private func handleProfileChanged() {
        guard let id = profilePopup.selectedItem?.representedObject as? String else { return }
        settings.activeProfileID = id
        let active = settings.activeProfile
        translucencyTrack.setValue(active.effectiveFrameTranslucency(fallback: settings))
        tintToggle.setOn(active.effectiveWallpaperTint())
        tintToggle.refreshAppearance()
    }

    private func importThemes() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.message = "Select theme JSON files to import"
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let dest = CustomThemeLoader.shared.themesDirectory?.appendingPathComponent(url.lastPathComponent) else { continue }
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        CustomThemeLoader.shared.reload()
        themeGrid.refresh()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let width = bounds.width
        let cardWidth = width - PreferencesLayout.hPad * 2
        let innerWidth = cardWidth - PreferencesLayout.cardPad * 2
        let labelWidth: CGFloat = 152
        let controlX = PreferencesLayout.cardPad + labelWidth
        let controlWidth = cardWidth - controlX - PreferencesLayout.cardPad
        let toggleX = PreferencesLayout.trailingToggleX(cardWidth: cardWidth)
        let toggleLabelWidth = PreferencesLayout.labelWidth(toTrailingToggleIn: cardWidth)

        var y: CGFloat = PreferencesLayout.hPad

        paneTitleLabel.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: 280, height: 24)
        paneSubtitleLabel.frame = NSRect(x: PreferencesLayout.hPad, y: y + 28, width: cardWidth - 160, height: 16)
        importBtn.frame = NSRect(x: width - PreferencesLayout.hPad - 132, y: y + 8, width: 132, height: 16)
        y += 60

        let summaryCardHeight: CGFloat = 204
        summaryCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardWidth, height: summaryCardHeight)
        let summaryValueX = PreferencesLayout.cardPad + 108
        let textColumnWidth = cardWidth - summaryValueX - PreferencesLayout.cardPad
        darkSummaryLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 120, width: 120, height: 16)
        darkSummaryValue.frame = NSRect(x: summaryValueX, y: 120, width: textColumnWidth, height: 16)
        lightSummaryLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 92, width: 120, height: 16)
        lightSummaryValue.frame = NSRect(x: summaryValueX, y: 92, width: textColumnWidth, height: 16)
        activeSummaryLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 64, width: 120, height: 16)
        activeSummaryValue.frame = NSRect(x: summaryValueX, y: 64, width: textColumnWidth, height: 16)
        activeSummaryNote.frame = NSRect(x: summaryValueX, y: 42, width: textColumnWidth, height: 12)
        appearanceModeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 12, width: 136, height: 16)
        appearanceModeSegment.frame = NSRect(x: summaryValueX, y: 6, width: textColumnWidth, height: 32)
        y += summaryCardHeight + PreferencesLayout.sectionGap

        let gridHeight = themeGrid.requiredHeight(for: innerWidth)
        let themeCardHeight = themeCard.headerHeight + gridHeight + PreferencesLayout.cardPad
        themeCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardWidth, height: themeCardHeight)
        themeGrid.frame = NSRect(
            x: PreferencesLayout.cardPad,
            y: themeCardHeight - themeCard.headerHeight - gridHeight,
            width: innerWidth,
            height: gridHeight
        )
        y += themeCardHeight + PreferencesLayout.sectionGap

        let interfaceCardHeight = interfaceCard.headerHeight + 3 * PreferencesLayout.rowH + 2 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        interfaceCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardWidth, height: interfaceCardHeight)
        let ir0 = interfaceCardHeight - interfaceCard.headerHeight - PreferencesLayout.rowH
        tabLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ir0, width: labelWidth - 12, height: PreferencesLayout.rowH)
        tabSegment.frame = NSRect(x: controlX, y: ir0 + 6, width: min(220, controlWidth), height: 28)
        let ir1 = ir0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ir1, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        statusBarToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardWidth, rowY: ir1)
        let ir2 = ir1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        padLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ir2, width: labelWidth - 12, height: PreferencesLayout.rowH)
        padXLabel.frame = NSRect(x: controlX, y: ir2 + 12, width: 14, height: 12)
        padXField.frame = NSRect(x: controlX + 18, y: ir2 + 6, width: 56, height: 28)
        padYLabel.frame = NSRect(x: controlX + 88, y: ir2 + 12, width: 14, height: 12)
        padYField.frame = NSRect(x: controlX + 106, y: ir2 + 6, width: 56, height: 28)
        y += interfaceCardHeight + PreferencesLayout.sectionGap

        let windowCardHeight = windowCard.headerHeight + 3 * PreferencesLayout.rowH + 2 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        windowCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardWidth, height: windowCardHeight)
        let wr0 = windowCardHeight - windowCard.headerHeight - PreferencesLayout.rowH
        noiseLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: wr0, width: labelWidth, height: PreferencesLayout.rowH)
        noiseTrack.frame = NSRect(x: controlX, y: wr0 + 8, width: controlWidth, height: 24)
        let wr1 = wr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        oledChromeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: wr1, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        oledChromeToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardWidth, rowY: wr1)
        let wr2 = wr1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        trafficLightLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: wr2, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        trafficLightToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardWidth, rowY: wr2)
        y += windowCardHeight + PreferencesLayout.sectionGap

        let profileCardHeight = profileCard.headerHeight + 3 * PreferencesLayout.rowH + 2 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        profileCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardWidth, height: profileCardHeight)
        let pr0 = profileCardHeight - profileCard.headerHeight - PreferencesLayout.rowH
        profileSelectLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: pr0, width: labelWidth, height: PreferencesLayout.rowH)
        profilePopup.frame = NSRect(x: controlX, y: pr0 + 4, width: min(220, controlWidth), height: 28)
        let pr1 = pr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        translucencyLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: pr1, width: labelWidth, height: PreferencesLayout.rowH)
        translucencyTrack.frame = NSRect(x: controlX, y: pr1 + 8, width: controlWidth, height: 24)
        let pr2 = pr1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        tintLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: pr2, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        tintToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardWidth, rowY: pr2)
        y += profileCardHeight + PreferencesLayout.sectionGap

        let statusBarCardHeight = statusBarCard.headerHeight + 7 * PreferencesLayout.rowH + 6 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        statusBarCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardWidth, height: statusBarCardHeight)
        let sb0 = statusBarCardHeight - statusBarCard.headerHeight - PreferencesLayout.rowH
        statusBarContextLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb0, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        statusBarContextToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardWidth, rowY: sb0)
        let sb1 = sb0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarPathLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb1, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        statusBarPathToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardWidth, rowY: sb1)
        let sb2 = sb1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarWorktreeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb2, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        statusBarWorktreeToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardWidth, rowY: sb2)
        let sb3 = sb2 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarBranchLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb3, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        statusBarBranchToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardWidth, rowY: sb3)
        let sb4 = sb3 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarGitHubLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb4, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        statusBarGitHubToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardWidth, rowY: sb4)
        let sb5 = sb4 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarProcessLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb5, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        statusBarProcessToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardWidth, rowY: sb5)
        let sb6 = sb5 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarSizeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb6, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        statusBarSizeToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardWidth, rowY: sb6)
        y += statusBarCardHeight + PreferencesLayout.hPad

        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, bounds.height))
    }
}

extension AppearancePane: PreferencesPaneRefreshable {
    func refreshPreferencesPane() { refresh() }
}
