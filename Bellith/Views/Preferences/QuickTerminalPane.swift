import AppKit

// MARK: - Quick Terminal Pane

final class QuickTerminalPane: NSView {
    private let settings = BellithSettings.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()

    // Activation card
    private let activationCard = SettingsCard(title: "Activation", subtitle: "Global hotkey and behavior")
    private let hotkeyLabel = CardRowLabel("Hotkey")
    private let hotkeyValue = NSTextField(labelWithString: "")
    private let hideLabel = CardRowLabel("Hide on focus loss")
    private var hideToggle: PrefToggle!

    // Appearance card
    private let appearanceCard = SettingsCard(title: "Appearance")
    private let posLabel = CardRowLabel("Position")
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
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        addSubview(scroll)
        content.wantsLayer = true
        scroll.documentView = content

        // Activation
        hotkeyValue.stringValue = settings.visorHotkey
        hotkeyValue.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        hotkeyValue.textColor = Theme.textSecondary
        hotkeyValue.isEditable = false
        hotkeyValue.isBezeled = false
        hotkeyValue.drawsBackground = false
        hideToggle = PrefToggle(isOn: settings.visorHideOnFocusLoss) { [weak self] v in
            self?.settings.visorHideOnFocusLoss = v
        }
        content.addSubview(activationCard)
        activationCard.addSubview(hotkeyLabel)
        activationCard.addSubview(hotkeyValue)
        activationCard.addSubview(hideLabel)
        activationCard.addSubview(hideToggle)

        // Appearance
        let posIdx = ["top": 0, "bottom": 1][settings.visorPosition] ?? 0
        posSegment = PrefSegment(labels: ["Top", "Bottom"], selected: posIdx) { [weak self] idx in
            self?.settings.visorPosition = ["top", "bottom"][idx]
        }
        widthTrack = OpacityTrackView(value: settings.visorWidthPercent) { [weak self] v in
            self?.settings.visorWidthPercent = v
        }
        heightTrack = OpacityTrackView(value: settings.visorHeightPercent) { [weak self] v in
            self?.settings.visorHeightPercent = v
        }
        content.addSubview(appearanceCard)
        for v: NSView in [posLabel, posSegment, widthLabel, widthTrack, heightLabel, heightTrack] {
            appearanceCard.addSubview(v)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let w = bounds.width
        let cardW = w - PreferencesLayout.hPad * 2
        let innerW = cardW - PreferencesLayout.cardPad * 2
        let ctlX: CGFloat = 90
        let ctlW = innerW - ctlX

        var y: CGFloat = PreferencesLayout.hPad

        // Activation card (2 rows)
        let actCardH = activationCard.headerHeight + 2 * PreferencesLayout.rowH + PreferencesLayout.rowGap + PreferencesLayout.cardPad
        activationCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: actCardH)
        let ar0 = actCardH - activationCard.headerHeight - PreferencesLayout.rowH
        hotkeyLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ar0 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        hotkeyValue.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: ar0 + (PreferencesLayout.rowH - 16) / 2, width: ctlW, height: 16)
        let ar1 = ar0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        hideLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ar1 + (PreferencesLayout.rowH - 16) / 2, width: 160, height: 16)
        hideToggle.frame = NSRect(x: PreferencesLayout.cardPad + 168, y: ar1 + (PreferencesLayout.rowH - 22) / 2, width: 50, height: 28)
        y += actCardH + PreferencesLayout.sectionGap

        // Appearance card (3 rows)
        let appCardH = appearanceCard.headerHeight + 3 * PreferencesLayout.rowH + 2 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        appearanceCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: appCardH)
        let pr0 = appCardH - appearanceCard.headerHeight - PreferencesLayout.rowH
        posLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: pr0 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        posSegment.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: pr0 + (PreferencesLayout.rowH - 28) / 2, width: min(160, ctlW), height: 28)
        let pr1 = pr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        widthLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: pr1 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        widthTrack.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: pr1 + (PreferencesLayout.rowH - 24) / 2, width: ctlW, height: 24)
        let pr2 = pr1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        heightLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: pr2 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        heightTrack.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: pr2 + (PreferencesLayout.rowH - 24) / 2, width: ctlW, height: 24)
        y += appCardH + PreferencesLayout.hPad

        content.frame = NSRect(x: 0, y: 0, width: w, height: max(y, bounds.height))
    }
}
