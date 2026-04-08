import AppKit

final class SSHPane: NSView {
    private let store = SSHProfileStore.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let heroCard = SettingsCard(title: "SSH Profiles", subtitle: "Saved hosts, bootstrap commands, and environment guards")
    private let heroTitleLabel = NSTextField(labelWithString: "")
    private let heroMetaLabel = NSTextField(labelWithString: "")
    private let heroDetailLabel = NSTextField(labelWithString: "")

    private let profilesCard = SettingsCard(title: "Saved Hosts", subtitle: "Profile commands appear in the command palette automatically")
    private var addButton: StepButton!
    private var removeButton: StepButton!
    private let emptyStateLabel = FooterNote("No saved SSH profiles yet. Add one to create reusable connect commands.")
    private var profileRows: [SSHProfileRow] = []

    private let connectionCard = SettingsCard(title: "Connection", subtitle: "Network identity and access path")
    private let nameLabel = CardRowLabel("Profile Name")
    private var nameField: PrefTextField!
    private let hostLabel = CardRowLabel("Host")
    private var hostField: PrefTextField!
    private let userLabel = CardRowLabel("User")
    private var userField: PrefTextField!
    private let portLabel = CardRowLabel("Port")
    private var portField: MiniNumberField!
    private let identityLabel = CardRowLabel("Identity File")
    private var identityField: PrefTextField!
    private let proxyJumpLabel = CardRowLabel("ProxyJump")
    private var proxyJumpField: PrefTextField!

    private let sessionCard = SettingsCard(title: "Bootstrap", subtitle: "Remote shell setup applied after the SSH session starts")
    private let cwdLabel = CardRowLabel("Remote Directory")
    private var cwdField: PrefTextField!
    private let startupLabel = CardRowLabel("Startup Command")
    private var startupField: PrefTextField!
    private let tmuxLabel = CardRowLabel("Tmux Session")
    private var tmuxField: PrefTextField!
    private let environmentLabel = CardRowLabel("Environment Tag")
    private var environmentField: PrefTextField!
    private let sensitiveLabel = CardRowLabel("Sensitive Host")
    private var sensitiveToggle: PrefToggle!
    private let notesLabel = CardRowLabel("Notes")
    private var notesField: PrefTextField!

    private var profiles: [SSHProfile] = []
    private var selectedProfileID: UUID?
    private var profileObserver: NSObjectProtocol?

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

        heroTitleLabel.font = BellithFont.display(34)
        heroTitleLabel.textColor = Theme.textDisplay
        heroMetaLabel.font = BellithFont.mono(11, weight: .regular)
        heroMetaLabel.textColor = Theme.textSecondary
        heroDetailLabel.font = BellithFont.mono(12, weight: .regular)
        heroDetailLabel.textColor = Theme.textPrimary
        content.addSubview(heroCard)
        for view in [heroTitleLabel, heroMetaLabel, heroDetailLabel] {
            heroCard.addSubview(view)
        }

        addButton = StepButton(symbol: "plus") { [weak self] in self?.addProfile() }
        removeButton = StepButton(symbol: "minus") { [weak self] in self?.removeSelectedProfile() }
        content.addSubview(profilesCard)
        profilesCard.addSubview(addButton)
        profilesCard.addSubview(removeButton)
        profilesCard.addSubview(emptyStateLabel)

        nameField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.name = value } }
        hostField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.host = value } }
        userField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.user = value } }
        portField = MiniNumberField(value: 22, range: 1...65_535) { [weak self] value in self?.mutateSelectedProfile { $0.port = value } }
        identityField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.identityPath = value } }
        proxyJumpField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.proxyJump = value } }
        content.addSubview(connectionCard)
        for view: NSView in [nameLabel, nameField, hostLabel, hostField, userLabel, userField, portLabel, portField, identityLabel, identityField, proxyJumpLabel, proxyJumpField] {
            connectionCard.addSubview(view)
        }

        cwdField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.defaultDirectory = value } }
        startupField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.startupCommand = value } }
        tmuxField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.tmuxSession = value } }
        environmentField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.environmentTag = value } }
        sensitiveToggle = PrefToggle(isOn: false) { [weak self] value in self?.mutateSelectedProfile { $0.isSensitive = value } }
        notesField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.notes = value } }
        content.addSubview(sessionCard)
        for view: NSView in [cwdLabel, cwdField, startupLabel, startupField, tmuxLabel, tmuxField, environmentLabel, environmentField, sensitiveLabel, sensitiveToggle, notesLabel, notesField] {
            sessionCard.addSubview(view)
        }

        profileObserver = NotificationCenter.default.addObserver(
            forName: SSHProfileStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadProfiles()
            self?.refresh()
        }

        reloadProfiles()
        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let profileObserver {
            NotificationCenter.default.removeObserver(profileObserver)
        }
    }

    func refresh() {
        content.layer?.backgroundColor = Theme.base.cgColor
        heroCard.refresh()
        profilesCard.refresh()
        connectionCard.refresh()
        sessionCard.refresh()
        reloadProfiles()
        updateHero()
        updateFieldValues()
        rebuildProfileRows()
        let hasSelection = selectedProfile != nil
        connectionCard.isHidden = !hasSelection
        sessionCard.isHidden = !hasSelection
        removeButton.isHidden = !hasSelection
        emptyStateLabel.isHidden = !profiles.isEmpty
        needsLayout = true
    }

    private var selectedProfile: SSHProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first { $0.id == selectedProfileID }
    }

    private func reloadProfiles() {
        profiles = store.profiles
        if let selectedProfileID, profiles.contains(where: { $0.id == selectedProfileID }) {
            return
        }
        selectedProfileID = profiles.first?.id
    }

    private func updateHero() {
        if let profile = selectedProfile {
            heroTitleLabel.stringValue = profile.displayName.uppercased()
            let env = profile.environmentTag.isEmpty ? "UNSCOPED" : profile.environmentTag.uppercased()
            let mode = profile.isSensitive ? "GUARDED" : "STANDARD"
            heroMetaLabel.stringValue = "[ \(env) ]   [ \(mode) ]"
            heroDetailLabel.stringValue = SSHLaunchBuilder.command(for: profile)
        } else {
            heroTitleLabel.stringValue = "NO HOSTS"
            heroMetaLabel.stringValue = "[ SSH COMMANDS ]   [ READY WHEN YOU ARE ]"
            heroDetailLabel.stringValue = "Add a profile to create reusable host commands."
        }
    }

    private func updateFieldValues() {
        guard let profile = selectedProfile else {
            for field in [nameField, hostField, userField, identityField, proxyJumpField, cwdField, startupField, tmuxField, environmentField, notesField] {
                field?.updateText("")
            }
            portField.setValue(22)
            sensitiveToggle.setOn(false)
            return
        }

        nameField.updateText(profile.name)
        hostField.updateText(profile.host)
        userField.updateText(profile.user)
        portField.setValue(profile.port)
        identityField.updateText(profile.identityPath)
        proxyJumpField.updateText(profile.proxyJump)
        cwdField.updateText(profile.defaultDirectory)
        startupField.updateText(profile.startupCommand)
        tmuxField.updateText(profile.tmuxSession)
        environmentField.updateText(profile.environmentTag)
        sensitiveToggle.setOn(profile.isSensitive)
        notesField.updateText(profile.notes)
    }

    private func rebuildProfileRows() {
        profileRows.forEach { $0.removeFromSuperview() }
        profileRows.removeAll()

        for profile in profiles {
            let row = SSHProfileRow()
            row.update(profile: profile, isSelected: profile.id == selectedProfileID)
            row.onSelect = { [weak self] in
                self?.selectedProfileID = profile.id
                self?.refresh()
            }
            profilesCard.addSubview(row)
            profileRows.append(row)
        }
    }

    private func addProfile() {
        let nextIndex = profiles.count + 1
        let profile = SSHProfile(name: "Host \(nextIndex)")
        store.upsert(profile)
        selectedProfileID = profile.id
        refresh()
    }

    private func removeSelectedProfile() {
        guard let selectedProfileID else { return }
        store.deleteProfile(id: selectedProfileID)
        self.selectedProfileID = store.profiles.first?.id
        refresh()
    }

    private func mutateSelectedProfile(_ update: (inout SSHProfile) -> Void) {
        guard var profile = selectedProfile else { return }
        update(&profile)
        store.upsert(profile)
        selectedProfileID = profile.id
        refresh()
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds

        let width = bounds.width
        let cardW = width - PreferencesLayout.hPad * 2
        let labelW: CGFloat = 146
        let controlX = PreferencesLayout.cardPad + labelW
        let controlW = cardW - controlX - PreferencesLayout.cardPad

        var y: CGFloat = PreferencesLayout.hPad

        let heroHeight: CGFloat = 168
        heroCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: heroHeight)
        heroMetaLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 106, width: cardW - PreferencesLayout.cardPad * 2, height: 14)
        heroTitleLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 60, width: cardW - PreferencesLayout.cardPad * 2, height: 40)
        heroDetailLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: 22, width: cardW - PreferencesLayout.cardPad * 2, height: 28)
        y += heroHeight + PreferencesLayout.sectionGap

        let rowCount = max(profileRows.count, 1)
        let profileRowsHeight = CGFloat(rowCount) * 38 + CGFloat(max(0, rowCount - 1)) * 6
        let profilesCardHeight = profilesCard.headerHeight + 34 + profileRowsHeight + PreferencesLayout.cardPad
        profilesCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: profilesCardHeight)
        addButton.frame = NSRect(x: cardW - PreferencesLayout.cardPad - 64, y: profilesCardHeight - profilesCard.headerHeight + 4, width: 28, height: 28)
        removeButton.frame = NSRect(x: cardW - PreferencesLayout.cardPad - 30, y: profilesCardHeight - profilesCard.headerHeight + 4, width: 28, height: 28)

        if profiles.isEmpty {
            emptyStateLabel.frame = NSRect(
                x: PreferencesLayout.cardPad,
                y: profilesCardHeight - profilesCard.headerHeight - PreferencesLayout.rowH,
                width: cardW - PreferencesLayout.cardPad * 2,
                height: 16
            )
        } else {
            var rowY = profilesCardHeight - profilesCard.headerHeight - 36
            for row in profileRows {
                row.frame = NSRect(x: PreferencesLayout.cardPad, y: rowY, width: cardW - PreferencesLayout.cardPad * 2, height: 38)
                rowY -= 44
            }
        }
        y += profilesCardHeight + PreferencesLayout.sectionGap

        if let _ = selectedProfile {
            let connectionHeight = connectionCard.headerHeight
                + 6 * PreferencesLayout.rowH
                + 5 * PreferencesLayout.rowGap
                + PreferencesLayout.cardPad
            connectionCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: connectionHeight)
            var rowY = connectionHeight - connectionCard.headerHeight - PreferencesLayout.rowH
            for (label, control) in [
                (nameLabel, nameField as NSView),
                (hostLabel, hostField as NSView),
                (userLabel, userField as NSView),
                (portLabel, portField as NSView),
                (identityLabel, identityField as NSView),
                (proxyJumpLabel, proxyJumpField as NSView),
            ] {
                label.frame = NSRect(x: PreferencesLayout.cardPad, y: rowY, width: labelW - 12, height: PreferencesLayout.rowH)
                control.frame = NSRect(x: controlX, y: rowY + 6, width: controlW, height: 28)
                rowY -= PreferencesLayout.rowH + PreferencesLayout.rowGap
            }
            y += connectionHeight + PreferencesLayout.sectionGap

            let sessionHeight = sessionCard.headerHeight
                + 6 * PreferencesLayout.rowH
                + 5 * PreferencesLayout.rowGap
                + PreferencesLayout.cardPad
            sessionCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: sessionHeight)
            var sessionRowY = sessionHeight - sessionCard.headerHeight - PreferencesLayout.rowH
            for (label, control) in [
                (cwdLabel, cwdField as NSView),
                (startupLabel, startupField as NSView),
                (tmuxLabel, tmuxField as NSView),
                (environmentLabel, environmentField as NSView),
                (sensitiveLabel, sensitiveToggle as NSView),
                (notesLabel, notesField as NSView),
            ] {
                label.frame = NSRect(x: PreferencesLayout.cardPad, y: sessionRowY, width: labelW - 12, height: PreferencesLayout.rowH)
                let controlWidth = control === sensitiveToggle ? 50 : controlW
                control.frame = NSRect(x: controlX, y: sessionRowY + 6, width: controlWidth, height: 28)
                sessionRowY -= PreferencesLayout.rowH + PreferencesLayout.rowGap
            }
            y += sessionHeight + PreferencesLayout.hPad
        }

        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, bounds.height))
    }
}

extension SSHPane: PreferencesPaneRefreshable {
    func refreshPreferencesPane() { refresh() }
}

private final class SSHProfileRow: NSView {
    var onSelect: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isSelected = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10

        titleLabel.font = BellithFont.mono(11, weight: .regular)
        titleLabel.textColor = Theme.textPrimary
        addSubview(titleLabel)

        detailLabel.font = BellithFont.mono(10, weight: .regular)
        detailLabel.textColor = Theme.textSecondary
        addSubview(detailLabel)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func update(profile: SSHProfile, isSelected: Bool) {
        titleLabel.stringValue = profile.displayName.uppercased()
        detailLabel.stringValue = profile.destination.isEmpty ? "UNCONFIGURED" : profile.destination
        self.isSelected = isSelected
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 12, y: 18, width: bounds.width - 24, height: 14)
        detailLabel.frame = NSRect(x: 12, y: 6, width: bounds.width - 24, height: 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill: NSColor
        if isSelected {
            fill = Theme.selectionFill
        } else if isHovered {
            fill = Theme.overlay.withAlphaComponent(0.55)
        } else {
            fill = Theme.surface.withAlphaComponent(0.35)
        }
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()

        let stroke = isSelected ? Theme.selectionStroke : Theme.border
        stroke.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        border.lineWidth = 0.5
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }
}
