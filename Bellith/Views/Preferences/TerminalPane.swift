import AppKit

// MARK: - Terminal Pane

final class TerminalPane: NSView {
    private let settings = BellithSettings.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let heroCard = SettingsCard(title: "Live Preview", subtitle: "Typography drives the terminal hierarchy")
    private let heroSizeLabel = NSTextField(labelWithString: "")
    private let heroFamilyLabel = NSTextField(labelWithString: "")
    private let heroPreviewLabel = NSTextField(labelWithString: "")
    private let heroMetaLabel = NSTextField(labelWithString: "")

    private let fontCard = SettingsCard(title: "Typography", subtitle: "Applied to new terminals")
    private let fontSummaryLabel = NSTextField(labelWithString: "")
    private let fontSizeHeroLabel = NSTextField(labelWithString: "")
    private let fontPreviewNote = NSTextField(labelWithString: "Monospaced preview for new sessions")
    private let fontLabel = CardRowLabel("Font Family")
    private var fontField: PrefTextField!
    private let fontPickerBtn = FontPickerButton()
    private let sizeLabel = CardRowLabel("Font Size")
    private var sizeMinus: StepButton!
    private let sizeValue = ValueBadge()
    private var sizePlus: StepButton!

    private let cursorCard = SettingsCard(title: "Cursor", subtitle: "Shape and motion of the active insertion point")
    private let cursorLabel = CardRowLabel("Cursor Style")
    private var cursorSegment: PrefSegment!
    private let blinkLabel = CardRowLabel("Blink")
    private var blinkToggle: PrefToggle!
    private let cursorColorLabel = CardRowLabel("Cursor Color")
    private let cursorColorNote = FooterNote("Inherited from the selected theme")

    private let sessionCard = SettingsCard(title: "Session Defaults", subtitle: "Shell, directory, scrollback, and bell behavior")
    private let shellLabel = CardRowLabel("Shell Command")
    private var shellField: PrefTextField!
    private let shellNote = FooterNote("Leave empty to use the login shell")
    private let cwdLabel = CardRowLabel("Start Directory")
    private var cwdField: PrefTextField!
    private let cwdNote = FooterNote("Used for new tabs and restored sessions")
    private let scrollLabel = CardRowLabel("Scrollback")
    private var scrollField: MiniNumberField!
    private let scrollUnit = SmallLabel("LINES")
    private let bellLabel = CardRowLabel("Bell")
    private var bellSegment: PrefSegment!

    private let shellIntegrationCard = SettingsCard(title: "Shell Integration", subtitle: "Prompt marks, command tracking, and remote shell compatibility")
    private let shellIntegrationEnabledLabel = CardRowLabel("Enable Shell Integration")
    private var shellIntegrationEnabledToggle: PrefToggle!
    private let shellIntegrationCursorLabel = CardRowLabel("Cursor At Prompt")
    private var shellIntegrationCursorToggle: PrefToggle!
    private let shellIntegrationTitleLabel = CardRowLabel("Update Window Title")
    private var shellIntegrationTitleToggle: PrefToggle!
    private let shellIntegrationPathLabel = CardRowLabel("Add Ghostty To PATH")
    private var shellIntegrationPathToggle: PrefToggle!
    private let shellIntegrationSSHEnvLabel = CardRowLabel("SSH Env Compatibility")
    private var shellIntegrationSSHEnvToggle: PrefToggle!
    private let shellIntegrationSSHTerminfoLabel = CardRowLabel("SSH Terminfo Install")
    private var shellIntegrationSSHTerminfoToggle: PrefToggle!
    private let shellIntegrationNote = FooterNote("Prompt marks, command timing, and completion notifications require shell integration.")

    private let behaviorCard = SettingsCard(title: "Behavior", subtitle: "Session lifecycle and cursor visibility")
    private let hideMouseLabel = CardRowLabel("Hide Cursor While Typing")
    private var hideMouseToggle: PrefToggle!
    private let confirmLabel = CardRowLabel("Confirm Before Closing")
    private var confirmToggle: PrefToggle!
    private let restoreLabel = CardRowLabel("Restore Previous Session")
    private var restoreToggle: PrefToggle!

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

        heroSizeLabel.font = BellithFont.display(42)
        heroSizeLabel.textColor = Theme.textDisplay
        heroFamilyLabel.font = BellithFont.mono(11, weight: .regular)
        heroFamilyLabel.textColor = Theme.textSecondary
        heroMetaLabel.font = BellithFont.mono(12, weight: .regular)
        heroMetaLabel.textColor = Theme.textSecondary
        heroPreviewLabel.lineBreakMode = .byTruncatingTail
        heroPreviewLabel.textColor = Theme.textPrimary
        content.addSubview(heroCard)
        for view in [heroSizeLabel, heroFamilyLabel, heroPreviewLabel, heroMetaLabel] {
            heroCard.addSubview(view)
        }

        fontSummaryLabel.font = BellithFont.mono(12, weight: .regular)
        fontSummaryLabel.textColor = Theme.textPrimary
        fontSummaryLabel.lineBreakMode = .byTruncatingTail
        fontSizeHeroLabel.font = BellithFont.display(26)
        fontSizeHeroLabel.textColor = Theme.textDisplay
        fontSizeHeroLabel.alignment = .right
        fontPreviewNote.font = BellithFont.ui(11, weight: .regular)
        fontPreviewNote.textColor = Theme.textSecondary

        fontField = PrefTextField(text: settings.fontFamily) { [weak self] value in
            self?.settings.fontFamily = value
            self?.updateHero()
        }
        fontPickerBtn.onFontPicked = { [weak self] name in
            guard let self else { return }
            self.settings.fontFamily = name
            self.fontField.updateText(name)
            self.updateHero()
        }
        sizeValue.stringValue = "\(settings.fontSize)"
        sizeMinus = StepButton(symbol: "minus") { [weak self] in
            guard let self else { return }
            self.settings.fontSize = max(8, self.settings.fontSize - 1)
            self.sizeValue.stringValue = "\(self.settings.fontSize)"
            self.updateHero()
        }
        sizePlus = StepButton(symbol: "plus") { [weak self] in
            guard let self else { return }
            self.settings.fontSize = min(36, self.settings.fontSize + 1)
            self.sizeValue.stringValue = "\(self.settings.fontSize)"
            self.updateHero()
        }
        content.addSubview(fontCard)
        for view: NSView in [fontSummaryLabel, fontSizeHeroLabel, fontPreviewNote, fontLabel, fontField, fontPickerBtn, sizeLabel, sizeMinus, sizeValue, sizePlus] {
            fontCard.addSubview(view)
        }

        cursorSegment = PrefSegment(labels: ["Block", "Bar", "Underline"], selected: ["block": 0, "bar": 1, "underline": 2][settings.cursorStyle] ?? 0) { [weak self] idx in
            self?.settings.cursorStyle = ["block", "bar", "underline"][idx]
            self?.updateHero()
        }
        blinkToggle = PrefToggle(isOn: settings.cursorBlink) { [weak self] value in
            self?.settings.cursorBlink = value
            self?.updateHero()
        }
        content.addSubview(cursorCard)
        for view: NSView in [cursorLabel, cursorSegment, blinkLabel, blinkToggle, cursorColorLabel, cursorColorNote] {
            cursorCard.addSubview(view)
        }

        shellField = PrefTextField(text: settings.shell) { [weak self] value in
            self?.settings.shell = value
            self?.updateHero()
        }
        cwdField = PrefTextField(text: settings.workingDirectory) { [weak self] value in
            self?.settings.workingDirectory = value
            self?.updateHero()
        }
        scrollField = MiniNumberField(value: settings.scrollbackLines, range: 100...1_000_000) { [weak self] value in
            self?.settings.scrollbackLines = value
            self?.updateHero()
        }
        bellSegment = PrefSegment(labels: ["Sound", "Visual", "Bounce", "None"], selected: ["system": 0, "visual": 1, "bounce": 2, "none": 3][settings.bellMode] ?? 0) { [weak self] idx in
            self?.settings.bellMode = ["system", "visual", "bounce", "none"][idx]
            self?.updateHero()
        }
        content.addSubview(sessionCard)
        for view: NSView in [shellLabel, shellField, shellNote, cwdLabel, cwdField, cwdNote, scrollLabel, scrollField, scrollUnit, bellLabel, bellSegment] {
            sessionCard.addSubview(view)
        }

        shellIntegrationEnabledToggle = PrefToggle(isOn: settings.shellIntegrationEnabled) { [weak self] value in
            self?.settings.shellIntegrationEnabled = value
        }
        shellIntegrationCursorToggle = PrefToggle(isOn: settings.shellIntegrationCursor) { [weak self] value in
            self?.settings.shellIntegrationCursor = value
        }
        shellIntegrationTitleToggle = PrefToggle(isOn: settings.shellIntegrationTitle) { [weak self] value in
            self?.settings.shellIntegrationTitle = value
        }
        shellIntegrationPathToggle = PrefToggle(isOn: settings.shellIntegrationPath) { [weak self] value in
            self?.settings.shellIntegrationPath = value
        }
        shellIntegrationSSHEnvToggle = PrefToggle(isOn: settings.shellIntegrationSSHEnv) { [weak self] value in
            self?.settings.shellIntegrationSSHEnv = value
        }
        shellIntegrationSSHTerminfoToggle = PrefToggle(isOn: settings.shellIntegrationSSHTerminfo) { [weak self] value in
            self?.settings.shellIntegrationSSHTerminfo = value
        }
        content.addSubview(shellIntegrationCard)
        for view: NSView in [
            shellIntegrationEnabledLabel,
            shellIntegrationEnabledToggle,
            shellIntegrationCursorLabel,
            shellIntegrationCursorToggle,
            shellIntegrationTitleLabel,
            shellIntegrationTitleToggle,
            shellIntegrationPathLabel,
            shellIntegrationPathToggle,
            shellIntegrationSSHEnvLabel,
            shellIntegrationSSHEnvToggle,
            shellIntegrationSSHTerminfoLabel,
            shellIntegrationSSHTerminfoToggle,
            shellIntegrationNote
        ] {
            shellIntegrationCard.addSubview(view)
        }

        hideMouseToggle = PrefToggle(isOn: settings.mouseHideWhileTyping) { [weak self] value in self?.settings.mouseHideWhileTyping = value }
        confirmToggle = PrefToggle(isOn: settings.confirmClose) { [weak self] value in self?.settings.confirmClose = value }
        restoreToggle = PrefToggle(isOn: settings.restoreSession) { [weak self] value in self?.settings.restoreSession = value }
        content.addSubview(behaviorCard)
        for view: NSView in [hideMouseLabel, hideMouseToggle, confirmLabel, confirmToggle, restoreLabel, restoreToggle] {
            behaviorCard.addSubview(view)
        }

        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        content.layer?.backgroundColor = Theme.base.cgColor
        heroCard.refresh()
        fontCard.refresh()
        cursorCard.refresh()
        sessionCard.refresh()
        shellIntegrationCard.refresh()
        behaviorCard.refresh()
        fontField.updateText(settings.fontFamily)
        sizeValue.stringValue = "\(settings.fontSize)"
        cursorSegment.setSelected(["block": 0, "bar": 1, "underline": 2][settings.cursorStyle] ?? 0)
        blinkToggle.setOn(settings.cursorBlink)
        shellField.updateText(settings.shell)
        cwdField.updateText(settings.workingDirectory)
        scrollField.setValue(settings.scrollbackLines)
        bellSegment.setSelected(["system": 0, "visual": 1, "bounce": 2, "none": 3][settings.bellMode] ?? 0)
        shellIntegrationEnabledToggle.setOn(settings.shellIntegrationEnabled)
        shellIntegrationCursorToggle.setOn(settings.shellIntegrationCursor)
        shellIntegrationTitleToggle.setOn(settings.shellIntegrationTitle)
        shellIntegrationPathToggle.setOn(settings.shellIntegrationPath)
        shellIntegrationSSHEnvToggle.setOn(settings.shellIntegrationSSHEnv)
        shellIntegrationSSHTerminfoToggle.setOn(settings.shellIntegrationSSHTerminfo)
        hideMouseToggle.setOn(settings.mouseHideWhileTyping)
        confirmToggle.setOn(settings.confirmClose)
        restoreToggle.setOn(settings.restoreSession)
        updateHero()
        needsLayout = true
    }

    private func updateHero() {
        heroSizeLabel.stringValue = "\(settings.fontSize) PX"
        heroFamilyLabel.stringValue = settings.fontFamily.uppercased()
        heroMetaLabel.stringValue = "[ \(settings.cursorStyle.uppercased()) ]   [ \(settings.cursorBlink ? "BLINK" : "STATIC") ]   [ \(settings.scrollbackLines) LINES ]"
        let prompt = settings.shell.isEmpty ? "$ bellith --new-session" : "$ \(settings.shell)"
        heroPreviewLabel.stringValue = prompt
        heroPreviewLabel.font = NSFont(name: settings.fontFamily, size: CGFloat(settings.fontSize))
            ?? BellithFont.mono(CGFloat(settings.fontSize), weight: .regular)
        heroPreviewLabel.textColor = Theme.textPrimary

        fontSummaryLabel.stringValue = settings.fontFamily.uppercased()
        fontSizeHeroLabel.stringValue = "\(settings.fontSize) PX"
        fontSummaryLabel.textColor = Theme.textPrimary
        fontSizeHeroLabel.textColor = Theme.textDisplay
        fontPreviewNote.textColor = Theme.textSecondary
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let width = bounds.width
        let cardW = width - PreferencesLayout.hPad * 2
        let innerW = cardW - PreferencesLayout.cardPad * 2
        let labelW: CGFloat = 146
        let controlX = PreferencesLayout.cardPad + labelW
        let controlW = cardW - controlX - PreferencesLayout.cardPad

        var y: CGFloat = PreferencesLayout.hPad

        let heroHeight: CGFloat = 172
        heroCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: heroHeight)
        heroSizeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 68, width: innerW * 0.45, height: 46)
        heroFamilyLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 118, width: innerW * 0.45, height: 14)
        heroPreviewLabel.frame = NSRect(x: PreferencesLayout.cardPad + innerW * 0.48, y: 78, width: innerW * 0.48, height: 24)
        heroMetaLabel.frame = NSRect(x: PreferencesLayout.cardPad + innerW * 0.48, y: 106, width: innerW * 0.48, height: 16)
        y += heroHeight + PreferencesLayout.sectionGap

        let fontHeroBlockH: CGFloat = 52
        let fontCardHeight = fontCard.headerHeight + fontHeroBlockH + 2 * PreferencesLayout.rowH + PreferencesLayout.rowGap + PreferencesLayout.cardPad + 10
        fontCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: fontCardHeight)
        let fontHeroTop = fontCardHeight - fontCard.headerHeight - 14
        fontSummaryLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: fontHeroTop - 18, width: innerW - 110, height: 16)
        fontSizeHeroLabel.frame = NSRect(x: cardW - PreferencesLayout.cardPad - 96, y: fontHeroTop - 34, width: 96, height: 30)
        fontPreviewNote.frame = NSRect(x: PreferencesLayout.cardPad, y: fontHeroTop - 34, width: innerW - 110, height: 14)

        let fr0 = fontHeroTop - fontHeroBlockH - 10
        fontLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: fr0, width: labelW - 12, height: PreferencesLayout.rowH)
        let pickerW: CGFloat = 84
        fontField.frame = NSRect(x: controlX, y: fr0 + 6, width: controlW - pickerW - 10, height: 28)
        fontPickerBtn.frame = NSRect(x: controlX + controlW - pickerW, y: fr0 + 6, width: pickerW, height: 28)
        let fr1 = fr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        sizeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: fr1, width: labelW - 12, height: PreferencesLayout.rowH)
        let stepSize: CGFloat = 28
        sizeMinus.frame = NSRect(x: controlX, y: fr1 + 6, width: stepSize, height: stepSize)
        sizeValue.frame = NSRect(x: controlX + 42, y: fr1 + 10, width: 54, height: 20)
        sizePlus.frame = NSRect(x: controlX + 110, y: fr1 + 6, width: stepSize, height: stepSize)
        y += fontCardHeight + PreferencesLayout.sectionGap

        let cursorCardHeight = cursorCard.headerHeight + 3 * PreferencesLayout.rowH + 2 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        cursorCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: cursorCardHeight)
        let cr0 = cursorCardHeight - cursorCard.headerHeight - PreferencesLayout.rowH
        cursorLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: cr0, width: labelW - 12, height: PreferencesLayout.rowH)
        cursorSegment.frame = NSRect(x: controlX, y: cr0 + 6, width: min(250, controlW), height: 28)
        let cr1 = cr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        blinkLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: cr1, width: labelW - 12, height: PreferencesLayout.rowH)
        blinkToggle.frame = NSRect(x: controlX, y: cr1 + 6, width: 50, height: 28)
        let cr2 = cr1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        cursorColorLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: cr2, width: labelW - 12, height: PreferencesLayout.rowH)
        cursorColorNote.frame = NSRect(x: controlX, y: cr2 + 12, width: controlW, height: 14)
        y += cursorCardHeight + PreferencesLayout.sectionGap

        let sessionCardHeight = sessionCard.headerHeight + 4 * PreferencesLayout.rowH + 2 * 14 + 3 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        sessionCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: sessionCardHeight)
        let sr0 = sessionCardHeight - sessionCard.headerHeight - PreferencesLayout.rowH
        shellLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sr0, width: labelW - 12, height: PreferencesLayout.rowH)
        shellField.frame = NSRect(x: controlX, y: sr0 + 6, width: controlW, height: 28)
        let shellNoteY = sr0 - 14
        shellNote.frame = NSRect(x: controlX, y: shellNoteY, width: controlW, height: 14)
        let sr1 = shellNoteY - PreferencesLayout.rowH
        cwdLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sr1, width: labelW - 12, height: PreferencesLayout.rowH)
        cwdField.frame = NSRect(x: controlX, y: sr1 + 6, width: controlW, height: 28)
        let cwdNoteY = sr1 - 14
        cwdNote.frame = NSRect(x: controlX, y: cwdNoteY, width: controlW, height: 14)
        let sr2 = cwdNoteY - PreferencesLayout.rowH
        scrollLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sr2, width: labelW - 12, height: PreferencesLayout.rowH)
        scrollField.frame = NSRect(x: controlX, y: sr2 + 6, width: 96, height: 28)
        scrollUnit.frame = NSRect(x: controlX + 106, y: sr2 + 12, width: 40, height: 12)
        let sr3 = sr2 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        bellLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sr3, width: labelW - 12, height: PreferencesLayout.rowH)
        bellSegment.frame = NSRect(x: controlX, y: sr3 + 6, width: min(320, controlW), height: 28)
        y += sessionCardHeight + PreferencesLayout.sectionGap

        let shellToggleX = cardW - PreferencesLayout.cardPad - 50
        let shellLabelW = shellToggleX - PreferencesLayout.cardPad - 8
        let shellIntegrationCardHeight = shellIntegrationCard.headerHeight + 6 * PreferencesLayout.rowH + 5 * PreferencesLayout.rowGap + PreferencesLayout.cardPad + 14
        shellIntegrationCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: shellIntegrationCardHeight)
        let ir0 = shellIntegrationCardHeight - shellIntegrationCard.headerHeight - PreferencesLayout.rowH
        shellIntegrationEnabledLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ir0, width: shellLabelW, height: PreferencesLayout.rowH)
        shellIntegrationEnabledToggle.frame = NSRect(x: shellToggleX, y: ir0 + 6, width: 50, height: 28)
        let ir1 = ir0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        shellIntegrationCursorLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ir1, width: shellLabelW, height: PreferencesLayout.rowH)
        shellIntegrationCursorToggle.frame = NSRect(x: shellToggleX, y: ir1 + 6, width: 50, height: 28)
        let ir2 = ir1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        shellIntegrationTitleLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ir2, width: shellLabelW, height: PreferencesLayout.rowH)
        shellIntegrationTitleToggle.frame = NSRect(x: shellToggleX, y: ir2 + 6, width: 50, height: 28)
        let ir3 = ir2 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        shellIntegrationPathLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ir3, width: shellLabelW, height: PreferencesLayout.rowH)
        shellIntegrationPathToggle.frame = NSRect(x: shellToggleX, y: ir3 + 6, width: 50, height: 28)
        let ir4 = ir3 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        shellIntegrationSSHEnvLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ir4, width: shellLabelW, height: PreferencesLayout.rowH)
        shellIntegrationSSHEnvToggle.frame = NSRect(x: shellToggleX, y: ir4 + 6, width: 50, height: 28)
        let ir5 = ir4 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        shellIntegrationSSHTerminfoLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: ir5, width: shellLabelW, height: PreferencesLayout.rowH)
        shellIntegrationSSHTerminfoToggle.frame = NSRect(x: shellToggleX, y: ir5 + 6, width: 50, height: 28)
        shellIntegrationNote.frame = NSRect(x: PreferencesLayout.cardPad, y: PreferencesLayout.cardPad - 2, width: innerW, height: 14)
        y += shellIntegrationCardHeight + PreferencesLayout.sectionGap

        let behaviorCardHeight = behaviorCard.headerHeight + 3 * PreferencesLayout.rowH + 2 * PreferencesLayout.rowGap + PreferencesLayout.cardPad
        behaviorCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: behaviorCardHeight)
        let toggleX = cardW - PreferencesLayout.cardPad - 50
        let behaviorLabelW = toggleX - PreferencesLayout.cardPad - 8
        let br0 = behaviorCardHeight - behaviorCard.headerHeight - PreferencesLayout.rowH
        hideMouseLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: br0, width: behaviorLabelW, height: PreferencesLayout.rowH)
        hideMouseToggle.frame = NSRect(x: toggleX, y: br0 + 6, width: 50, height: 28)
        let br1 = br0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        confirmLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: br1, width: behaviorLabelW, height: PreferencesLayout.rowH)
        confirmToggle.frame = NSRect(x: toggleX, y: br1 + 6, width: 50, height: 28)
        let br2 = br1 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        restoreLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: br2, width: behaviorLabelW, height: PreferencesLayout.rowH)
        restoreToggle.frame = NSRect(x: toggleX, y: br2 + 6, width: 50, height: 28)
        y += behaviorCardHeight + PreferencesLayout.hPad

        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, bounds.height))
    }
}

extension TerminalPane: PreferencesPaneRefreshable {
    func refreshPreferencesPane() { refresh() }
}
