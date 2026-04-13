import AppKit

final class FeaturesPane: NSView {
    private let settings: BellithSettings
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let paneTitleLabel = NSTextField(labelWithString: "Features")
    private let paneSubtitleLabel = NSTextField(labelWithString: "Feature flags for alternate or in-progress workflows.")

    private let featureCard = SettingsCard(title: "Feature Flags", subtitle: "Opt into capabilities that may still be evolving")
    private let builtInSettingsLabel = CardRowLabel(BellithFeatureFlag.builtInSettingsWindow.title)
    private var builtInSettingsToggle: PrefToggle!
    private let builtInSettingsNote = FooterNote(BellithFeatureFlag.builtInSettingsWindow.detail)
    private let defaultStateNote = FooterNote("Default: on")

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

        builtInSettingsToggle = PrefToggle(isOn: settings.builtInSettingsWindowEnabled) { [weak self] value in
            self?.settings.builtInSettingsWindowEnabled = value
        }

        content.addSubview(featureCard)
        for view: NSView in [builtInSettingsLabel, builtInSettingsToggle, builtInSettingsNote, defaultStateNote] {
            featureCard.addSubview(view)
        }

        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        content.layer?.backgroundColor = Theme.frame.cgColor
        paneTitleLabel.textColor = Theme.textDisplay
        paneSubtitleLabel.textColor = Theme.textSecondary
        featureCard.refresh()
        builtInSettingsLabel.textColor = Theme.textSecondary
        builtInSettingsToggle.setOn(settings.builtInSettingsWindowEnabled)
        builtInSettingsNote.textColor = Theme.textTertiary
        defaultStateNote.textColor = Theme.textMuted
        needsLayout = true
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let width = bounds.width
        let cardWidth = width - PreferencesLayout.hPad * 2
        let toggleLabelWidth = PreferencesLayout.labelWidth(toTrailingToggleIn: cardWidth)

        var y: CGFloat = PreferencesLayout.hPad

        paneTitleLabel.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: 280, height: 24)
        paneSubtitleLabel.frame = NSRect(x: PreferencesLayout.hPad, y: y + 28, width: cardWidth, height: 16)
        y += 60

        let featureCardHeight = featureCard.headerHeight + PreferencesLayout.rowH + 42 + 16 + PreferencesLayout.cardPad
        featureCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardWidth, height: featureCardHeight)
        let rowY = featureCardHeight - featureCard.headerHeight - PreferencesLayout.rowH
        builtInSettingsLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: rowY, width: toggleLabelWidth, height: PreferencesLayout.rowH)
        builtInSettingsToggle.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardWidth, rowY: rowY)
        builtInSettingsNote.frame = NSRect(x: PreferencesLayout.cardPad, y: rowY - 16, width: cardWidth - PreferencesLayout.cardPad * 2 - 60, height: 28)
        defaultStateNote.frame = NSRect(x: PreferencesLayout.cardPad, y: 16, width: 120, height: 14)
        y += featureCardHeight + PreferencesLayout.hPad

        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, bounds.height))
    }
}

extension FeaturesPane: PreferencesPaneRefreshable {
    func refreshPreferencesPane() { refresh() }
}
