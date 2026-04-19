import AppKit

// MARK: - Quick Terminal Pane

final class QuickTerminalPane: NSView {
    private let settings: BellithSettings
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let paneTitleLabel = NSTextField(labelWithString: "Quick Terminal")
    private let paneSubtitleLabel = NSTextField(labelWithString: "Summon shortcut, screen edge, and visor proportions.")

    private let activationCard = SettingsCard(title: "Activation", subtitle: "How the quick terminal appears and disappears")
    private let hotkeyLabel = CardRowLabel("Global Hotkey")
    private let hotkeyValue = NSTextField(labelWithString: "⌥ `")
    private let hotkeyNote = FooterNote("Option + backtick toggles the visor anywhere in macOS.")
    private let hideLabel = CardRowLabel("Hide on Focus Loss")
    private var hideToggle: PrefToggle!

    private let appearanceCard = SettingsCard(title: "Geometry", subtitle: "Placement and proportions on the active screen")
    private let posLabel = CardRowLabel("Screen Edge")
    private var posSegment: PrefSegment!
    private let widthLabel = CardRowLabel("Width")
    private var widthTrack: OpacityTrackView!
    private let heightLabel = CardRowLabel("Height")
    private var heightTrack: OpacityTrackView!

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

        hotkeyValue.font = BellithFont.mono(12, weight: .regular)
        hotkeyValue.textColor = Theme.textPrimary
        hideToggle = PrefToggle(isOn: settings.visorHideOnFocusLoss) { [weak self] value in
            self?.settings.visorHideOnFocusLoss = value
        }
        content.addSubview(activationCard)
        activationCard.addSubview(hotkeyLabel)
        activationCard.addSubview(hotkeyValue)
        activationCard.addSubview(hotkeyNote)
        activationCard.addSubview(hideLabel)
        activationCard.addSubview(hideToggle)

        posSegment = PrefSegment(labels: ["Top", "Bottom"], selected: ["top": 0, "bottom": 1][settings.visorPosition] ?? 0) { [weak self] idx in
            self?.settings.visorPosition = ["top", "bottom"][idx]
        }
        widthTrack = OpacityTrackView(value: settings.visorWidthPercent) { [weak self] value in
            self?.settings.visorWidthPercent = value
        }
        heightTrack = OpacityTrackView(value: settings.visorHeightPercent) { [weak self] value in
            self?.settings.visorHeightPercent = value
        }
        content.addSubview(appearanceCard)
        for view: NSView in [posLabel, posSegment, widthLabel, widthTrack, heightLabel, heightTrack] {
            appearanceCard.addSubview(view)
        }

        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        content.layer?.backgroundColor = Theme.frame.cgColor
        paneTitleLabel.textColor = Theme.textDisplay
        paneSubtitleLabel.textColor = Theme.textSecondary
        activationCard.refresh()
        appearanceCard.refresh()
        hotkeyValue.textColor = Theme.textPrimary
        hotkeyNote.textColor = Theme.textTertiary
        hideToggle.setOn(settings.visorHideOnFocusLoss)
        posSegment.setSelected(["top": 0, "bottom": 1][settings.visorPosition] ?? 0)
        widthTrack.setValue(settings.visorWidthPercent)
        heightTrack.setValue(settings.visorHeightPercent)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let width = bounds.width
        let cardW = width - PreferencesLayout.hPad * 2
        let labelW: CGFloat = 136
        let controlX = PreferencesLayout.cardPad + labelW
        let controlW = cardW - controlX - PreferencesLayout.cardPad
        let toggleLabelWidth = PreferencesLayout.labelWidth(toTrailingToggleIn: cardW)

        var y: CGFloat = PreferencesLayout.hPad

        paneTitleLabel.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: 280, height: 24)
        paneSubtitleLabel.frame = NSRect(x: PreferencesLayout.hPad, y: y + 28, width: cardW, height: 16)
        y += 60

        let activationCardHeight = activationCard.headerHeight + 2 * PreferencesLayout.rowH + 14 + PreferencesLayout.rowGap + PreferencesLayout.cardPad
        activationCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: activationCardHeight)
        let ar0 = activationCardHeight - activationCard.headerHeight - PreferencesLayout.rowH
        hotkeyLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ar0, width: labelW - 12, height: PreferencesLayout.rowH)
        hotkeyValue.frame = NSRect(x: controlX, y: ar0 + 12, width: controlW, height: 16)
        hotkeyNote.frame = NSRect(x: controlX, y: ar0 - 2, width: controlW, height: 14)
        let ar1 = ar0 - PreferencesLayout.rowH - 14 - PreferencesLayout.rowGap
        hideLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ar1, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        hideToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardW, rowY: ar1)
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
