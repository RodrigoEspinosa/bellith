import AppKit

// MARK: - Terminal Pane

final class TerminalPane: NSView {
    private let settings = BellithSettings.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()

    // Font card
    private let fontCard = SettingsCard(title: "Font", subtitle: "Applied to new terminals")
    private let fontLabel = CardRowLabel("Family")
    private var fontField: PrefTextField!
    private let fontPickerBtn = FontPickerButton()
    private let sizeLabel = CardRowLabel("Size")
    private var sizeMinus: StepButton!
    private let sizeValue = ValueBadge()
    private var sizePlus: StepButton!

    // Cursor card
    private let cursorCard = SettingsCard(title: "Cursor")
    private let cursorLabel = CardRowLabel("Style")
    private var cursorSegment: PrefSegment!
    private let blinkLabel = CardRowLabel("Blink")
    private var blinkToggle: PrefToggle!
    private let cursorColorLabel = CardRowLabel("Color")
    private let cursorColorNote = FooterNote("Inherited from theme")

    // Shell card
    private let shellCard = SettingsCard(title: "Shell", subtitle: "Applied to new terminals")
    private let shellLabel = CardRowLabel("Command")
    private var shellField: PrefTextField!
    private let shellNote = FooterNote("Leave empty for default login shell")
    private let cwdLabel = CardRowLabel("Directory")
    private var cwdField: PrefTextField!
    private let cwdNote = FooterNote("Starting directory for new tabs")
    private let scrollLabel = CardRowLabel("Scrollback")
    private var scrollField: MiniNumberField!
    private let scrollUnit = SmallLabel("lines")
    private let bellLabel = CardRowLabel("Bell")
    private var bellSegment: PrefSegment!

    // Behavior card
    private let behaviorCard = SettingsCard(title: "Behavior")
    private let hideMouseLabel = CardRowLabel("Hide cursor while typing")
    private var hideMouseToggle: PrefToggle!
    private let confirmLabel = CardRowLabel("Confirm before closing")
    private var confirmToggle: PrefToggle!
    private let restoreLabel = CardRowLabel("Restore previous session")
    private var restoreToggle: PrefToggle!

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

        // Font
        fontField = PrefTextField(text: settings.fontFamily) { [weak self] v in self?.settings.fontFamily = v }
        fontPickerBtn.onFontPicked = { [weak self] name in
            guard let self else { return }
            self.settings.fontFamily = name
            self.fontField.updateText(name)
        }
        sizeValue.stringValue = "\(settings.fontSize)"
        sizeMinus = StepButton(symbol: "minus") { [weak self] in
            guard let self else { return }
            self.settings.fontSize = max(8, self.settings.fontSize - 1)
            self.sizeValue.stringValue = "\(self.settings.fontSize)"
        }
        sizePlus = StepButton(symbol: "plus") { [weak self] in
            guard let self else { return }
            self.settings.fontSize = min(36, self.settings.fontSize + 1)
            self.sizeValue.stringValue = "\(self.settings.fontSize)"
        }
        content.addSubview(fontCard)
        for v: NSView in [fontLabel, fontField, fontPickerBtn, sizeLabel, sizeMinus, sizeValue, sizePlus] {
            fontCard.addSubview(v)
        }

        // Cursor
        cursorSegment = PrefSegment(labels: ["Block", "Bar", "Underline"],
                                    selected: ["block": 0, "bar": 1, "underline": 2][settings.cursorStyle] ?? 0) { [weak self] idx in
            self?.settings.cursorStyle = ["block", "bar", "underline"][idx]
        }
        blinkToggle = PrefToggle(isOn: settings.cursorBlink) { [weak self] v in self?.settings.cursorBlink = v }
        content.addSubview(cursorCard)
        for v: NSView in [cursorLabel, cursorSegment, blinkLabel, blinkToggle, cursorColorLabel, cursorColorNote] {
            cursorCard.addSubview(v)
        }

        // Shell
        shellField = PrefTextField(text: settings.shell) { [weak self] v in self?.settings.shell = v }
        cwdField = PrefTextField(text: settings.workingDirectory) { [weak self] v in self?.settings.workingDirectory = v }
        scrollField = MiniNumberField(value: settings.scrollbackLines, range: 100...1_000_000) { [weak self] v in
            self?.settings.scrollbackLines = v
        }
        let bellIdx = ["system": 0, "visual": 1, "bounce": 2, "none": 3][settings.bellMode] ?? 0
        bellSegment = PrefSegment(labels: ["Sound", "Visual", "Bounce", "None"], selected: bellIdx) { [weak self] idx in
            self?.settings.bellMode = ["system", "visual", "bounce", "none"][idx]
        }
        content.addSubview(shellCard)
        for v: NSView in [shellLabel, shellField, shellNote, cwdLabel, cwdField, cwdNote, scrollLabel, scrollField, scrollUnit, bellLabel, bellSegment] {
            shellCard.addSubview(v)
        }

        // Behavior
        hideMouseToggle = PrefToggle(isOn: settings.mouseHideWhileTyping) { [weak self] v in self?.settings.mouseHideWhileTyping = v }
        confirmToggle = PrefToggle(isOn: settings.confirmClose) { [weak self] v in self?.settings.confirmClose = v }
        restoreToggle = PrefToggle(isOn: settings.restoreSession) { [weak self] v in self?.settings.restoreSession = v }
        content.addSubview(behaviorCard)
        for v: NSView in [hideMouseLabel, hideMouseToggle, confirmLabel, confirmToggle, restoreLabel, restoreToggle] {
            behaviorCard.addSubview(v)
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

        // Font card (2 rows)
        let fontCardH = fontCard.headerHeight + 2 * PreferencesLayout.rowH + PreferencesLayout.rowGap + PreferencesLayout.cardPad
        fontCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: fontCardH)

        // Row 0: Family (top row in card)
        let fr0 = fontCardH - fontCard.headerHeight - PreferencesLayout.rowH
        fontLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: fr0 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        let pickerW: CGFloat = 32
        fontField.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: fr0 + (PreferencesLayout.rowH - 28) / 2, width: ctlW - pickerW - 6, height: 28)
        fontPickerBtn.frame = NSRect(x: PreferencesLayout.cardPad + ctlX + ctlW - pickerW, y: fr0 + (PreferencesLayout.rowH - 28) / 2, width: pickerW, height: 28)
        // Row 1: Size
        let fr1 = fr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        sizeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: fr1 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        let btnS: CGFloat = 28
        sizeMinus.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: fr1 + (PreferencesLayout.rowH - btnS) / 2, width: btnS, height: btnS)
        sizeValue.frame = NSRect(x: PreferencesLayout.cardPad + ctlX + btnS + 6, y: fr1 + (PreferencesLayout.rowH - 20) / 2, width: 36, height: 20)
        sizePlus.frame = NSRect(x: PreferencesLayout.cardPad + ctlX + btnS + 48, y: fr1 + (PreferencesLayout.rowH - btnS) / 2, width: btnS, height: btnS)

        y += fontCardH + PreferencesLayout.sectionGap

        // Cursor card (3 rows)
        let cursorCardH = cursorCard.headerHeight + 3 * PreferencesLayout.rowH + 2 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        cursorCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: cursorCardH)

        let cr0 = cursorCardH - cursorCard.headerHeight - PreferencesLayout.rowH
        cursorLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: cr0 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        cursorSegment.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: cr0 + (PreferencesLayout.rowH - 28) / 2, width: min(220, ctlW), height: 28)
        let cr1 = cr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        blinkLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: cr1 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        blinkToggle.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: cr1 + (PreferencesLayout.rowH - 22) / 2, width: 50, height: 28)
        let cr2 = cr1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        cursorColorLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: cr2 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        cursorColorNote.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: cr2 + (PreferencesLayout.rowH - 14) / 2, width: ctlW, height: 14)

        y += cursorCardH + PreferencesLayout.sectionGap

        // Shell card (4 rows + 2 notes)
        let shellCardH = shellCard.headerHeight + 4 * PreferencesLayout.rowH + 2 * 14 + 3 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        shellCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: shellCardH)

        let sr0 = shellCardH - shellCard.headerHeight - PreferencesLayout.rowH
        shellLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sr0 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        shellField.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: sr0 + (PreferencesLayout.rowH - 28) / 2, width: ctlW, height: 28)
        let noteY = sr0 - 14
        shellNote.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: noteY, width: ctlW, height: 14)

        let sr1 = noteY - PreferencesLayout.rowH
        cwdLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sr1 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        cwdField.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: sr1 + (PreferencesLayout.rowH - 28) / 2, width: ctlW, height: 28)
        let cwdNoteY = sr1 - 14
        cwdNote.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: cwdNoteY, width: ctlW, height: 14)

        let sr2 = cwdNoteY - PreferencesLayout.rowH
        scrollLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sr2 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        scrollField.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: sr2 + (PreferencesLayout.rowH - 28) / 2, width: 80, height: 28)
        scrollUnit.frame = NSRect(x: PreferencesLayout.cardPad + ctlX + 86, y: sr2 + (PreferencesLayout.rowH - 14) / 2, width: 40, height: 14)

        let sr3 = sr2 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        bellLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sr3 + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        bellSegment.frame = NSRect(x: PreferencesLayout.cardPad + ctlX, y: sr3 + (PreferencesLayout.rowH - 28) / 2, width: min(280, ctlW), height: 28)

        y += shellCardH + PreferencesLayout.sectionGap

        // Behavior card (3 rows)
        let behaviorCardH = behaviorCard.headerHeight + 3 * PreferencesLayout.rowH + 2 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        behaviorCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: behaviorCardH)

        let behaviorLabelW: CGFloat = 180
        let br0 = behaviorCardH - behaviorCard.headerHeight - PreferencesLayout.rowH
        hideMouseLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: br0 + (PreferencesLayout.rowH - 16) / 2, width: behaviorLabelW, height: 16)
        hideMouseToggle.frame = NSRect(x: PreferencesLayout.cardPad + behaviorLabelW + 8, y: br0 + (PreferencesLayout.rowH - 22) / 2, width: 50, height: 28)
        let br1 = br0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        confirmLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: br1 + (PreferencesLayout.rowH - 16) / 2, width: behaviorLabelW, height: 16)
        confirmToggle.frame = NSRect(x: PreferencesLayout.cardPad + behaviorLabelW + 8, y: br1 + (PreferencesLayout.rowH - 22) / 2, width: 50, height: 28)
        let br2 = br1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        restoreLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: br2 + (PreferencesLayout.rowH - 16) / 2, width: behaviorLabelW, height: 16)
        restoreToggle.frame = NSRect(x: PreferencesLayout.cardPad + behaviorLabelW + 8, y: br2 + (PreferencesLayout.rowH - 22) / 2, width: 50, height: 28)

        y += behaviorCardH + PreferencesLayout.hPad

        content.frame = NSRect(x: 0, y: 0, width: w, height: max(y, bounds.height))
    }
}
