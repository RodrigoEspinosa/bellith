import AppKit

// MARK: - Quick Terminal Pane

final class QuickTerminalPane: NSView {
    private let settings = BellithSettings.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let heroCard = SettingsCard(title: "Quick Terminal", subtitle: "Global summon shortcut and visor geometry")
    private let heroHotkeyLabel = NSTextField(labelWithString: "")
    private let heroMetaLabel = NSTextField(labelWithString: "")
    private let heroSizeLabel = NSTextField(labelWithString: "")

    private let activationCard = SettingsCard(title: "Activation", subtitle: "How the quick terminal appears and disappears")
    private let hotkeyLabel = CardRowLabel("Global Hotkey")
    private let hotkeyValue = NSTextField(labelWithString: "")
    private let hideLabel = CardRowLabel("Hide on Focus Loss")
    private var hideToggle: PrefToggle!

    private let appearanceCard = SettingsCard(title: "Geometry", subtitle: "Placement and proportions on the active screen")
    private let posLabel = CardRowLabel("Screen Edge")
    private var posSegment: PrefSegment!
    private let widthLabel = CardRowLabel("Width")
    private var widthTrack: OpacityTrackView!
    private let heightLabel = CardRowLabel("Height")
    private var heightTrack: OpacityTrackView!

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

        heroHotkeyLabel.font = BellithFont.display(38)
        heroHotkeyLabel.textColor = Theme.textDisplay
        heroMetaLabel.font = BellithFont.mono(11, weight: .regular)
        heroMetaLabel.textColor = Theme.textSecondary
        heroSizeLabel.font = BellithFont.mono(12, weight: .regular)
        heroSizeLabel.textColor = Theme.textPrimary
        content.addSubview(heroCard)
        for view in [heroHotkeyLabel, heroMetaLabel, heroSizeLabel] {
            heroCard.addSubview(view)
        }

        hotkeyValue.font = BellithFont.mono(12, weight: .regular)
        hotkeyValue.textColor = Theme.textPrimary
        hideToggle = PrefToggle(isOn: settings.visorHideOnFocusLoss) { [weak self] value in
            self?.settings.visorHideOnFocusLoss = value
            self?.updateHero()
        }
        content.addSubview(activationCard)
        activationCard.addSubview(hotkeyLabel)
        activationCard.addSubview(hotkeyValue)
        activationCard.addSubview(hideLabel)
        activationCard.addSubview(hideToggle)

        posSegment = PrefSegment(labels: ["Top", "Bottom"], selected: ["top": 0, "bottom": 1][settings.visorPosition] ?? 0) { [weak self] idx in
            self?.settings.visorPosition = ["top", "bottom"][idx]
            self?.updateHero()
        }
        widthTrack = OpacityTrackView(value: settings.visorWidthPercent) { [weak self] value in
            self?.settings.visorWidthPercent = value
            self?.updateHero()
        }
        heightTrack = OpacityTrackView(value: settings.visorHeightPercent) { [weak self] value in
            self?.settings.visorHeightPercent = value
            self?.updateHero()
        }
        content.addSubview(appearanceCard)
        for view: NSView in [posLabel, posSegment, widthLabel, widthTrack, heightLabel, heightTrack] {
            appearanceCard.addSubview(view)
        }

        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        content.layer?.backgroundColor = Theme.base.cgColor
        heroCard.refresh()
        activationCard.refresh()
        appearanceCard.refresh()
        hotkeyValue.stringValue = settings.visorHotkey.uppercased()
        hideToggle.setOn(settings.visorHideOnFocusLoss)
        posSegment.setSelected(["top": 0, "bottom": 1][settings.visorPosition] ?? 0)
        widthTrack.setValue(settings.visorWidthPercent)
        heightTrack.setValue(settings.visorHeightPercent)
        updateHero()
        needsLayout = true
    }

    private func updateHero() {
        heroHotkeyLabel.stringValue = settings.visorHotkey.uppercased()
        heroMetaLabel.stringValue = "[ \(settings.visorPosition.uppercased()) EDGE ]   [ \(settings.visorHideOnFocusLoss ? "AUTO HIDE" : "STAYS OPEN") ]"
        heroSizeLabel.stringValue = "WIDTH \(Int(settings.visorWidthPercent * 100))%   HEIGHT \(Int(settings.visorHeightPercent * 100))%"
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let width = bounds.width
        let cardW = width - PreferencesLayout.hPad * 2
        let labelW: CGFloat = 136
        let controlX = PreferencesLayout.cardPad + labelW
        let controlW = cardW - controlX - PreferencesLayout.cardPad

        var y: CGFloat = PreferencesLayout.hPad

        let heroHeight: CGFloat = 164
        heroCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: heroHeight)
        heroMetaLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 96, width: cardW - PreferencesLayout.cardPad * 2, height: 14)
        heroHotkeyLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 48, width: cardW - PreferencesLayout.cardPad * 2, height: 42)
        heroSizeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 24, width: cardW - PreferencesLayout.cardPad * 2, height: 16)
        y += heroHeight + PreferencesLayout.sectionGap

        let activationCardHeight = activationCard.headerHeight + 2 * PreferencesLayout.rowH + PreferencesLayout.rowGap + PreferencesLayout.cardPad
        activationCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: activationCardHeight)
        let ar0 = activationCardHeight - activationCard.headerHeight - PreferencesLayout.rowH
        hotkeyLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ar0, width: labelW - 12, height: PreferencesLayout.rowH)
        hotkeyValue.frame = NSRect(x: controlX, y: ar0 + 12, width: controlW, height: 16)
        let ar1 = ar0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        hideLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ar1, width: labelW + 28, height: PreferencesLayout.rowH)
        hideToggle.frame = NSRect(x: controlX, y: ar1 + 6, width: 50, height: 28)
        y += activationCardHeight + PreferencesLayout.sectionGap

        let appearanceCardHeight = appearanceCard.headerHeight + 3 * PreferencesLayout.rowH + 2 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        appearanceCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: appearanceCardHeight)
        let gr0 = appearanceCardHeight - appearanceCard.headerHeight - PreferencesLayout.rowH
        posLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: gr0, width: labelW - 12, height: PreferencesLayout.rowH)
        posSegment.frame = NSRect(x: controlX, y: gr0 + 6, width: min(180, controlW), height: 28)
        let gr1 = gr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        widthLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: gr1, width: labelW - 12, height: PreferencesLayout.rowH)
        widthTrack.frame = NSRect(x: controlX, y: gr1 + 8, width: controlW, height: 24)
        let gr2 = gr1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        heightLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: gr2, width: labelW - 12, height: PreferencesLayout.rowH)
        heightTrack.frame = NSRect(x: controlX, y: gr2 + 8, width: controlW, height: 24)
        y += appearanceCardHeight + PreferencesLayout.hPad

        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, bounds.height))
    }
}

extension QuickTerminalPane: PreferencesPaneRefreshable {
    func refreshPreferencesPane() { refresh() }
}
