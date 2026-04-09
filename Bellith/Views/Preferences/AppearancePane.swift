import AppKit

private final class AppearancePreviewMiniView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        Theme.surface.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()

        Theme.border.setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        border.lineWidth = 1
        border.stroke()

        let chrome = NSRect(x: 0, y: rect.height - 28, width: rect.width, height: 28)
        Theme.chromeElevated.setFill()
        NSBezierPath(roundedRect: chrome, xRadius: 12, yRadius: 12).fill()
        NSBezierPath(rect: NSRect(x: 0, y: rect.height - 28, width: rect.width, height: 16)).fill()

        for (idx, color) in [Theme.destructive, Theme.warning, Theme.success].enumerated() {
            color.withAlphaComponent(0.9).setFill()
            let dotRect = NSRect(x: 12 + CGFloat(idx) * 10, y: rect.height - 18, width: 6, height: 6)
            NSBezierPath(ovalIn: dotRect).fill()
        }

        let lineGap: CGFloat = 3
        let segments = 12
        let segmentW = (rect.width - 28 - CGFloat(segments - 1) * lineGap) / CGFloat(segments)
        for idx in 0..<segments {
            let fill = idx < 7 ? Theme.textDisplay : Theme.border
            fill.setFill()
            let y: CGFloat = 18
            let lineRect = NSRect(x: 14 + CGFloat(idx) * (segmentW + lineGap), y: y, width: segmentW, height: 6)
            NSBezierPath(roundedRect: lineRect, xRadius: 1.5, yRadius: 1.5).fill()
        }

        Theme.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: 14, y: 34, width: rect.width - 28, height: 8), xRadius: 4, yRadius: 4).fill()

        Theme.textSecondary.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: NSRect(x: 14, y: 50, width: rect.width * 0.52, height: 6), xRadius: 3, yRadius: 3).fill()
        NSBezierPath(roundedRect: NSRect(x: 14, y: 62, width: rect.width * 0.33, height: 6), xRadius: 3, yRadius: 3).fill()
    }
}

// MARK: - Appearance Pane

final class AppearancePane: NSView {
    private let settings: BellithSettings
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let heroCard = SettingsCard(title: "Current Theme", subtitle: "Primary palette and window identity")
    private let heroThemeLabel = NSTextField(labelWithString: "")
    private let heroMetaLabel = NSTextField(labelWithString: "")
    private let heroCommandLabel = NSTextField(labelWithString: "")
    private let heroPreview = AppearancePreviewMiniView()

    private let themeCard = SettingsCard(title: "Theme Library", subtitle: "Pick the visual voice of every new terminal")
    private var themeGrid: ThemeGridView!
    private let importBtn = LinkButton(title: "Import Theme…")

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

    private let windowCard = SettingsCard(title: "Window", subtitle: "Opacity and traffic-light behavior")
    private let opacityLabel = CardRowLabel("Background Opacity")
    private var opacityTrack: OpacityTrackView!
    private let noiseLabel = CardRowLabel("Noise Grain")
    private var noiseTrack: OpacityTrackView!
    private let trafficLightLabel = CardRowLabel("Auto-hide Traffic Lights")
    private var trafficLightToggle: PrefToggle!

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
        content.layer?.backgroundColor = Theme.base.cgColor
        scroll.documentView = content

        heroThemeLabel.font = BellithFont.display(34)
        heroThemeLabel.textColor = Theme.textDisplay
        heroThemeLabel.lineBreakMode = .byTruncatingTail
        content.addSubview(heroCard)
        heroCard.addSubview(heroThemeLabel)

        heroMetaLabel.font = BellithFont.mono(11, weight: .regular)
        heroMetaLabel.textColor = Theme.textSecondary
        heroCard.addSubview(heroMetaLabel)

        heroCommandLabel.font = BellithFont.mono(12, weight: .regular)
        heroCommandLabel.textColor = Theme.textPrimary
        heroCard.addSubview(heroCommandLabel)
        heroCard.addSubview(heroPreview)

        themeGrid = ThemeGridView(settings: settings) { [weak self] in self?.refresh() }
        importBtn.onClick = { [weak self] in self?.importThemes() }
        content.addSubview(themeCard)
        themeCard.addSubview(themeGrid)
        themeCard.addSubview(importBtn)

        tabSegment = PrefSegment(labels: ["Sidebar", "Tab Bar"], selected: settings.tabMode == "sidebar" ? 0 : 1) { [weak self] idx in
            self?.settings.tabMode = idx == 0 ? "sidebar" : "tabbar"
            if let window = NSApp.windows.first(where: { $0.contentView is TerminalContainerView }),
               let container = window.contentView as? TerminalContainerView {
                container.applyTabMode()
            }
            self?.updateHero()
        }
        statusBarToggle = PrefToggle(isOn: settings.showStatusBar) { [weak self] value in
            self?.settings.showStatusBar = value
            self?.updateHero()
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

        opacityTrack = OpacityTrackView(value: settings.backgroundOpacity) { [weak self] value in
            self?.settings.backgroundOpacity = value
        }
        noiseTrack = OpacityTrackView(value: settings.noiseIntensity, minValue: 0.0) { [weak self] value in
            self?.settings.noiseIntensity = value
        }
        trafficLightToggle = PrefToggle(isOn: settings.trafficLightAutoHide) { [weak self] value in
            self?.settings.trafficLightAutoHide = value
        }
        content.addSubview(windowCard)
        for view: NSView in [opacityLabel, opacityTrack, noiseLabel, noiseTrack, trafficLightLabel, trafficLightToggle] {
            windowCard.addSubview(view)
        }

        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        content.layer?.backgroundColor = Theme.base.cgColor
        heroCard.refresh()
        themeCard.refresh()
        interfaceCard.refresh()
        statusBarCard.refresh()
        windowCard.refresh()
        themeGrid.refresh()
        tabSegment.setSelected(settings.tabMode == "sidebar" ? 0 : 1)
        statusBarToggle.setOn(settings.showStatusBar)
        statusBarContextToggle.setOn(settings.showStatusBarContext)
        statusBarPathToggle.setOn(settings.showStatusBarPath)
        statusBarWorktreeToggle.setOn(settings.showStatusBarGitWorktree)
        statusBarBranchToggle.setOn(settings.showStatusBarGitBranch)
        statusBarGitHubToggle.setOn(settings.showStatusBarGitHub)
        statusBarProcessToggle.setOn(settings.showStatusBarProcess)
        statusBarSizeToggle.setOn(settings.showStatusBarSize)
        padXField.setValue(settings.windowPaddingX)
        padYField.setValue(settings.windowPaddingY)
        opacityTrack.setValue(settings.backgroundOpacity)
        noiseTrack.setValue(settings.noiseIntensity)
        trafficLightToggle.setOn(settings.trafficLightAutoHide)
        updateHero()
        needsLayout = true
    }

    private func updateHero() {
        heroThemeLabel.stringValue = settings.resolvedTheme.name.uppercased()
        let tabs = settings.tabMode == "sidebar" ? "SIDEBAR" : "TAB BAR"
        let statusBar = settings.showStatusBar ? "STATUS BAR ON" : "STATUS BAR OFF"
        heroMetaLabel.stringValue = "[ DARK: \(settings.darkThemeName) ]   [ LIGHT: \(settings.lightThemeName) ]   [ \(tabs) ]   [ \(statusBar) ]"
        heroCommandLabel.stringValue = "bellith --theme \"\(settings.resolvedTheme.name)\" --opacity \(Int(settings.backgroundOpacity * 100))%"
        heroThemeLabel.textColor = Theme.textDisplay
        heroMetaLabel.textColor = Theme.textSecondary
        heroCommandLabel.textColor = Theme.textPrimary
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
        let cardW = width - PreferencesLayout.hPad * 2
        let innerW = cardW - PreferencesLayout.cardPad * 2
        let labelW: CGFloat = 136
        let controlX = PreferencesLayout.cardPad + labelW
        let controlW = cardW - controlX - PreferencesLayout.cardPad

        var y: CGFloat = PreferencesLayout.hPad

        let heroHeight: CGFloat = 176
        heroCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: heroHeight)
        heroThemeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 76, width: innerW * 0.52, height: 40)
        heroMetaLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 56, width: innerW * 0.52, height: 14)
        heroCommandLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 34, width: innerW * 0.52, height: 16)
        heroPreview.frame = NSRect(x: cardW - PreferencesLayout.cardPad - 210, y: 24, width: 210, height: 102)
        y += heroHeight + PreferencesLayout.sectionGap

        let gridHeight = themeGrid.requiredHeight(for: innerW)
        let themeCardHeight = themeCard.headerHeight + gridHeight + 18 + 18 + PreferencesLayout.cardPad
        themeCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: themeCardHeight)
        themeGrid.frame = NSRect(x: PreferencesLayout.cardPad, y: themeCardHeight - themeCard.headerHeight - gridHeight, width: innerW, height: gridHeight)
        importBtn.frame = NSRect(x: PreferencesLayout.cardPad, y: 18, width: innerW, height: 16)
        y += themeCardHeight + PreferencesLayout.sectionGap

        let interfaceCardHeight = interfaceCard.headerHeight + 3 * PreferencesLayout.rowH + 2 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        interfaceCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: interfaceCardHeight)
        let ir0 = interfaceCardHeight - interfaceCard.headerHeight - PreferencesLayout.rowH
        tabLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ir0, width: labelW - 12, height: PreferencesLayout.rowH)
        tabSegment.frame = NSRect(x: controlX, y: ir0 + 6, width: min(220, controlW), height: 28)
        let ir1 = ir0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ir1, width: labelW + 20, height: PreferencesLayout.rowH)
        statusBarToggle.frame = NSRect(x: controlX, y: ir1 + 6, width: 50, height: 28)
        let ir2 = ir1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        padLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ir2, width: labelW - 12, height: PreferencesLayout.rowH)
        padXLabel.frame = NSRect(x: controlX, y: ir2 + 12, width: 14, height: 12)
        padXField.frame = NSRect(x: controlX + 18, y: ir2 + 6, width: 56, height: 28)
        padYLabel.frame = NSRect(x: controlX + 88, y: ir2 + 12, width: 14, height: 12)
        padYField.frame = NSRect(x: controlX + 106, y: ir2 + 6, width: 56, height: 28)
        y += interfaceCardHeight + PreferencesLayout.sectionGap

        let statusBarCardHeight = statusBarCard.headerHeight + 7 * PreferencesLayout.rowH + 6 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        statusBarCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: statusBarCardHeight)
        let sb0 = statusBarCardHeight - statusBarCard.headerHeight - PreferencesLayout.rowH
        statusBarContextLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb0, width: labelW + 40, height: PreferencesLayout.rowH)
        statusBarContextToggle.frame = NSRect(x: controlX, y: sb0 + 6, width: 50, height: 28)
        let sb1 = sb0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarPathLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb1, width: labelW + 40, height: PreferencesLayout.rowH)
        statusBarPathToggle.frame = NSRect(x: controlX, y: sb1 + 6, width: 50, height: 28)
        let sb2 = sb1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarWorktreeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb2, width: labelW + 40, height: PreferencesLayout.rowH)
        statusBarWorktreeToggle.frame = NSRect(x: controlX, y: sb2 + 6, width: 50, height: 28)
        let sb3 = sb2 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarBranchLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb3, width: labelW + 40, height: PreferencesLayout.rowH)
        statusBarBranchToggle.frame = NSRect(x: controlX, y: sb3 + 6, width: 50, height: 28)
        let sb4 = sb3 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarGitHubLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb4, width: labelW + 40, height: PreferencesLayout.rowH)
        statusBarGitHubToggle.frame = NSRect(x: controlX, y: sb4 + 6, width: 50, height: 28)
        let sb5 = sb4 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarProcessLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb5, width: labelW + 40, height: PreferencesLayout.rowH)
        statusBarProcessToggle.frame = NSRect(x: controlX, y: sb5 + 6, width: 50, height: 28)
        let sb6 = sb5 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        statusBarSizeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sb6, width: labelW + 40, height: PreferencesLayout.rowH)
        statusBarSizeToggle.frame = NSRect(x: controlX, y: sb6 + 6, width: 50, height: 28)
        y += statusBarCardHeight + PreferencesLayout.sectionGap

        let windowCardHeight = windowCard.headerHeight + 3 * PreferencesLayout.rowH + 2 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        windowCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: windowCardHeight)
        let wr0 = windowCardHeight - windowCard.headerHeight - PreferencesLayout.rowH
        opacityLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: wr0, width: labelW - 12, height: PreferencesLayout.rowH)
        opacityTrack.frame = NSRect(x: controlX, y: wr0 + 8, width: controlW, height: 24)
        let wr1 = wr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        noiseLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: wr1, width: labelW - 12, height: PreferencesLayout.rowH)
        noiseTrack.frame = NSRect(x: controlX, y: wr1 + 8, width: controlW, height: 24)
        let wr2 = wr1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        trafficLightLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: wr2, width: labelW + 28, height: PreferencesLayout.rowH)
        trafficLightToggle.frame = NSRect(x: controlX, y: wr2 + 6, width: 50, height: 28)
        y += windowCardHeight + PreferencesLayout.hPad

        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, bounds.height))
    }
}

extension AppearancePane: PreferencesPaneRefreshable {
    func refreshPreferencesPane() { refresh() }
}
