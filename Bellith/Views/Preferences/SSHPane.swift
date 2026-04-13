import AppKit

final class SSHPane: NSView {
    private let store = SSHProfileStore.shared
    private let scroll = NSScrollView()
    private let content = FlippedView()

    private let paneTitleLabel = NSTextField(labelWithString: "SSH")
    private let paneSubtitleLabel = NSTextField(labelWithString: "Saved hosts, connection bootstrap, and reusable remote sessions.")

    private let profilesCard = SettingsCard(title: "Saved Hosts", subtitle: "Profile commands appear in the command palette automatically")
    private var addButton: StepButton!
    private var removeButton: StepButton!
    private let emptyStateLabel = FooterNote("No saved SSH profiles yet. Add one to create reusable connect commands.")
    private var profileRows: [SSHProfileRow] = []

    private let connectionCard = SettingsCard(title: "Connection", subtitle: "Network identity, transport, and access path")
    private let nameLabel = CardRowLabel("Profile Name")
    private var nameField: PrefTextField!
    private let hostLabel = CardRowLabel("Host")
    private var hostField: PrefTextField!
    private let userLabel = CardRowLabel("User")
    private var userField: PrefTextField!
    private let transportLabel = CardRowLabel("Transport")
    private var transportSegment: PrefSegment!
    private let portLabel = CardRowLabel("Port")
    private var portField: MiniNumberField!
    private let identityLabel = CardRowLabel("Identity File")
    private var identityField: PrefTextField!
    private let proxyJumpLabel = CardRowLabel("Jump Hosts")
    private var proxyJumpEditor: SSHProxyJumpEditorView!

    private let sessionCard = SettingsCard(title: "Bootstrap", subtitle: "Remote shell setup applied after the SSH session starts")
    private let cwdLabel = CardRowLabel("Remote Directory")
    private var cwdField: PrefTextField!
    private let startupLabel = CardRowLabel("Startup Command")
    private var startupField: PrefTextField!
    private let multiplexerLabel = CardRowLabel("Session Manager")
    private var multiplexerSegment: PrefSegment!
    private let sessionNameLabel = CardRowLabel("Session Name")
    private var sessionNameField: PrefTextField!
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
        content.layer?.backgroundColor = Theme.frame.cgColor
        scroll.documentView = content

        paneTitleLabel.font = BellithFont.ui(20, weight: .medium)
        paneTitleLabel.textColor = Theme.textDisplay
        content.addSubview(paneTitleLabel)

        paneSubtitleLabel.font = BellithFont.ui(12, weight: .regular)
        paneSubtitleLabel.textColor = Theme.textSecondary
        content.addSubview(paneSubtitleLabel)

        addButton = StepButton(symbol: "plus") { [weak self] in self?.addProfile() }
        removeButton = StepButton(symbol: "minus") { [weak self] in self?.removeSelectedProfile() }
        content.addSubview(profilesCard)
        profilesCard.addSubview(addButton)
        profilesCard.addSubview(removeButton)
        profilesCard.addSubview(emptyStateLabel)

        nameField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.name = value } }
        hostField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.host = value } }
        userField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.user = value } }
        transportSegment = PrefSegment(
            labels: SSHTransport.allCases.map(\.title),
            selected: 0
        ) { [weak self] idx in
            guard let transport = SSHTransport.allCases[safe: idx] else { return }
            self?.mutateSelectedProfile { $0.transport = transport }
        }
        portField = MiniNumberField(value: 22, range: 1...65_535) { [weak self] value in self?.mutateSelectedProfile { $0.port = value } }
        identityField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.identityPath = value } }
        proxyJumpEditor = SSHProxyJumpEditorView()
        proxyJumpEditor.onAddProfile = { [weak self] jumpProfileID in
            guard let self else { return }
            self.mutateSelectedProfile { profile in
                profile.updateProxyJumpChain(
                    profileIDs: profile.proxyJumpProfileIDs + [jumpProfileID],
                    availableProfiles: self.profiles
                )
            }
        }
        proxyJumpEditor.onRemoveProfile = { [weak self] jumpProfileID in
            guard let self else { return }
            self.mutateSelectedProfile { profile in
                profile.updateProxyJumpChain(
                    profileIDs: profile.proxyJumpProfileIDs.filter { $0 != jumpProfileID },
                    availableProfiles: self.profiles
                )
            }
        }
        content.addSubview(connectionCard)
        for view: NSView in [
            nameLabel,
            nameField,
            hostLabel,
            hostField,
            userLabel,
            userField,
            transportLabel,
            transportSegment as NSView,
            portLabel,
            portField,
            identityLabel,
            identityField,
            proxyJumpLabel,
            proxyJumpEditor,
        ] {
            connectionCard.addSubview(view)
        }

        cwdField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.defaultDirectory = value } }
        startupField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.startupCommand = value } }
        multiplexerSegment = PrefSegment(
            labels: SSHSessionBootstrap.allCases.map(\.title),
            selected: 0
        ) { [weak self] idx in
            guard let bootstrap = SSHSessionBootstrap.allCases[safe: idx] else { return }
            self?.mutateSelectedProfile { profile in
                profile.sessionBootstrap = bootstrap
                if bootstrap == .none {
                    profile.sessionName = ""
                }
            }
        }
        sessionNameField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.sessionName = value } }
        environmentField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.environmentTag = value } }
        sensitiveToggle = PrefToggle(isOn: false) { [weak self] value in self?.mutateSelectedProfile { $0.isSensitive = value } }
        notesField = PrefTextField(text: "") { [weak self] value in self?.mutateSelectedProfile { $0.notes = value } }
        content.addSubview(sessionCard)
        for view: NSView in [
            cwdLabel,
            cwdField,
            startupLabel,
            startupField,
            multiplexerLabel,
            multiplexerSegment,
            sessionNameLabel,
            sessionNameField,
            environmentLabel,
            environmentField,
            sensitiveLabel,
            sensitiveToggle,
            notesLabel,
            notesField,
        ] {
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
        content.layer?.backgroundColor = Theme.frame.cgColor
        paneTitleLabel.textColor = Theme.textDisplay
        paneSubtitleLabel.textColor = Theme.textSecondary
        profilesCard.refresh()
        connectionCard.refresh()
        sessionCard.refresh()
        reloadProfiles()
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

    private func updateFieldValues() {
        guard let profile = selectedProfile else {
            for field in [nameField, hostField, userField, identityField, cwdField, startupField, sessionNameField, environmentField, notesField] {
                field?.updateText("")
            }
            transportSegment.setSelected(0)
            portField.setValue(22)
            multiplexerSegment.setSelected(0)
            sensitiveToggle.setOn(false)
            proxyJumpEditor.update(profile: nil, availableProfiles: profiles)
            return
        }

        nameField.updateText(profile.name)
        hostField.updateText(profile.host)
        userField.updateText(profile.user)
        transportSegment.setSelected(SSHTransport.allCases.firstIndex(of: profile.transport) ?? 0)
        portField.setValue(profile.port)
        identityField.updateText(profile.identityPath)
        proxyJumpEditor.update(profile: profile, availableProfiles: profiles)
        cwdField.updateText(profile.defaultDirectory)
        startupField.updateText(profile.startupCommand)
        multiplexerSegment.setSelected(SSHSessionBootstrap.allCases.firstIndex(of: profile.sessionBootstrap) ?? 0)
        sessionNameField.updateText(profile.sessionName)
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

        paneTitleLabel.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: 280, height: 24)
        paneSubtitleLabel.frame = NSRect(x: PreferencesLayout.hPad, y: y + 28, width: cardW, height: 16)
        y += 60

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
            let proxyJumpHeight = SSHProxyJumpEditorView.preferredHeight
            let connectionHeight = connectionCard.headerHeight
                + 6 * PreferencesLayout.rowH
                + proxyJumpHeight
                + 6 * PreferencesLayout.rowGap
                + PreferencesLayout.cardPad
            connectionCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: connectionHeight)
            var rowY = connectionHeight - connectionCard.headerHeight - PreferencesLayout.rowH
            for (label, control) in [
                (nameLabel, nameField as NSView),
                (hostLabel, hostField as NSView),
                (userLabel, userField as NSView),
                (transportLabel, transportSegment as NSView),
                (portLabel, portField as NSView),
                (identityLabel, identityField as NSView),
            ] {
                label.frame = NSRect(x: PreferencesLayout.cardPad, y: rowY, width: labelW - 12, height: PreferencesLayout.rowH)
                control.frame = NSRect(x: controlX, y: rowY + 6, width: controlW, height: 28)
                rowY -= PreferencesLayout.rowH + PreferencesLayout.rowGap
            }

            let proxyJumpRowY = rowY - (proxyJumpHeight - PreferencesLayout.rowH)
            proxyJumpLabel.frame = NSRect(
                x: PreferencesLayout.cardPad,
                y: proxyJumpRowY + max(0, proxyJumpHeight - PreferencesLayout.rowH),
                width: labelW - 12,
                height: PreferencesLayout.rowH
            )
            proxyJumpEditor.frame = NSRect(x: controlX, y: proxyJumpRowY + 4, width: controlW, height: proxyJumpHeight - 8)
            y += connectionHeight + PreferencesLayout.sectionGap

            let sessionHeight = sessionCard.headerHeight
                + 7 * PreferencesLayout.rowH
                + 6 * PreferencesLayout.rowGap
                + PreferencesLayout.cardPad
            sessionCard.frame = NSRect(x: PreferencesLayout.hPad, y: y, width: cardW, height: sessionHeight)
            var sessionRowY = sessionHeight - sessionCard.headerHeight - PreferencesLayout.rowH
            for (label, control) in [
                (cwdLabel, cwdField as NSView),
                (startupLabel, startupField as NSView),
                (multiplexerLabel, multiplexerSegment as NSView),
                (sessionNameLabel, sessionNameField as NSView),
                (environmentLabel, environmentField as NSView),
                (sensitiveLabel, sensitiveToggle as NSView),
                (notesLabel, notesField as NSView),
            ] {
                if control === sensitiveToggle {
                    label.frame = NSRect(
                        x: PreferencesLayout.cardPad,
                        y: sessionRowY,
                        width: PreferencesLayout.labelWidth(toTrailingToggleIn: cardW),
                        height: PreferencesLayout.rowH
                    )
                    control.frame = PreferencesLayout.trailingToggleFrame(cardWidth: cardW, rowY: sessionRowY)
                } else {
                    label.frame = NSRect(x: PreferencesLayout.cardPad, y: sessionRowY, width: labelW - 12, height: PreferencesLayout.rowH)
                    control.frame = NSRect(x: controlX, y: sessionRowY + 6, width: controlW, height: 28)
                }
                sessionRowY -= PreferencesLayout.rowH + PreferencesLayout.rowGap
            }
            y += sessionHeight + PreferencesLayout.hPad
        }

        content.frame = NSRect(x: 0, y: 0, width: width, height: max(y, bounds.height))
    }
}

private struct SSHProxyJumpHopItem {
    let id: UUID?
    let title: String
    let isMissing: Bool
}

private final class SSHProxyJumpEditorView: NSView {
    static let preferredHeight: CGFloat = 62

    var onAddProfile: ((UUID) -> Void)?
    var onRemoveProfile: ((UUID) -> Void)?

    private let chainView = SSHProxyJumpChainView()
    private let addPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    override init(frame: NSRect) {
        super.init(frame: frame)

        chainView.onRemoveHop = { [weak self] hopID in
            self?.onRemoveProfile?(hopID)
        }
        addSubview(chainView)

        addPopup.font = BellithFont.mono(12, weight: .regular)
        addPopup.focusRingType = .none
        addPopup.target = self
        addPopup.action = #selector(handleAddProfile)
        addSubview(addPopup)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        chainView.frame = NSRect(x: 0, y: bounds.height - 28, width: bounds.width, height: 28)
        addPopup.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 28)
    }

    func update(profile: SSHProfile?, availableProfiles allProfiles: [SSHProfile]) {
        guard let profile else {
            chainView.update(hops: [])
            rebuildAddPopup(selectedProfileID: nil, selectedJumpProfileIDs: [], availableProfiles: [])
            return
        }

        let lookup = Dictionary(uniqueKeysWithValues: allProfiles.map { ($0.id, $0) })
        let hops: [SSHProxyJumpHopItem]
        if profile.hasProxyJumpProfileChain {
            hops = profile.proxyJumpProfileIDs.map { profileID in
                if let jumpProfile = lookup[profileID] {
                    return SSHProxyJumpHopItem(
                        id: profileID,
                        title: jumpProfile.displayName.uppercased(),
                        isMissing: false
                    )
                }
                return SSHProxyJumpHopItem(id: profileID, title: "MISSING HOST", isMissing: true)
            }
        } else {
            hops = profile.legacyProxyJumpHops.map {
                SSHProxyJumpHopItem(id: nil, title: $0.uppercased(), isMissing: true)
            }
        }

        chainView.update(hops: hops)
        rebuildAddPopup(
            selectedProfileID: profile.id,
            selectedJumpProfileIDs: Set(profile.proxyJumpProfileIDs),
            availableProfiles: allProfiles
        )
    }

    @objc private func handleAddProfile() {
        defer { addPopup.selectItem(at: 0) }
        guard addPopup.indexOfSelectedItem > 0,
              let jumpProfileID = addPopup.selectedItem?.representedObject as? UUID else { return }
        onAddProfile?(jumpProfileID)
    }

    private func rebuildAddPopup(
        selectedProfileID: UUID?,
        selectedJumpProfileIDs: Set<UUID>,
        availableProfiles: [SSHProfile]
    ) {
        addPopup.removeAllItems()
        addPopup.addItem(withTitle: "Add jump host…")
        addPopup.lastItem?.representedObject = nil

        let eligibleProfiles = availableProfiles.filter { profile in
            guard profile.id != selectedProfileID else { return false }
            return !selectedJumpProfileIDs.contains(profile.id)
        }

        for profile in eligibleProfiles {
            let title = profile.destination.isEmpty
                ? profile.displayName
                : "\(profile.displayName) — \(profile.destination)"
            addPopup.addItem(withTitle: title)
            addPopup.lastItem?.representedObject = profile.id
        }

        addPopup.selectItem(at: 0)
        addPopup.isEnabled = selectedProfileID != nil && !eligibleProfiles.isEmpty
        if !addPopup.isEnabled {
            addPopup.item(at: 0)?.title = selectedProfileID == nil ? "Add jump host…" : "No other saved hosts"
        }
    }
}

private final class SSHProxyJumpChainView: NSView {
    var onRemoveHop: ((UUID) -> Void)?

    private let emptyLabel = NSTextField(labelWithString: "DIRECT CONNECTION")
    private var hopViews: [SSHProxyJumpHopBadgeView] = []
    private var arrowViews: [NSImageView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5

        emptyLabel.font = BellithFont.mono(10, weight: .regular)
        emptyLabel.textColor = Theme.textTertiary
        addSubview(emptyLabel)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.backgroundColor = Theme.frame.cgColor
        layer?.borderColor = Theme.border.cgColor
        emptyLabel.textColor = Theme.textTertiary
        emptyLabel.frame = bounds.insetBy(dx: 10, dy: 7)

        let inset: CGFloat = 8
        let arrowWidth: CGFloat = 14
        let hopHeight = bounds.height - 8
        let maxHopWidth = max(72, (bounds.width - inset * 2 - CGFloat(max(0, hopViews.count - 1)) * arrowWidth) / CGFloat(max(hopViews.count, 1)))

        var x = inset
        for (index, hopView) in hopViews.enumerated() {
            let remainingWidth = max(72, bounds.width - inset - x)
            let width = min(hopView.preferredWidth, maxHopWidth, remainingWidth)
            hopView.frame = NSRect(x: x, y: 4, width: width, height: hopHeight)
            x += width

            if let arrowView = arrowViews[safe: index] {
                arrowView.frame = NSRect(x: x, y: (bounds.height - 12) / 2, width: arrowWidth, height: 12)
                x += arrowWidth
            }
        }
    }

    func update(hops: [SSHProxyJumpHopItem]) {
        hopViews.forEach { $0.removeFromSuperview() }
        arrowViews.forEach { $0.removeFromSuperview() }
        hopViews.removeAll()
        arrowViews.removeAll()

        emptyLabel.isHidden = !hops.isEmpty

        for (index, hop) in hops.enumerated() {
            let hopView = SSHProxyJumpHopBadgeView()
            hopView.update(hop: hop)
            hopView.onRemove = { [weak self] in
                guard let hopID = hop.id else { return }
                self?.onRemoveHop?(hopID)
            }
            addSubview(hopView)
            hopViews.append(hopView)

            if index < hops.count - 1 {
                let arrowView = NSImageView()
                arrowView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
                arrowView.contentTintColor = Theme.textTertiary
                arrowView.imageScaling = .scaleProportionallyDown
                addSubview(arrowView)
                arrowViews.append(arrowView)
            }
        }

        needsLayout = true
    }
}

private final class SSHProxyJumpHopBadgeView: NSView {
    var onRemove: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let removeButton = NSButton()
    private var isMissing = false
    private var showsRemoveButton = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5

        titleLabel.font = BellithFont.mono(10, weight: .regular)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        removeButton.isBordered = false
        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove jump host")
        removeButton.imageScaling = .scaleProportionallyDown
        removeButton.target = self
        removeButton.action = #selector(handleRemove)
        addSubview(removeButton)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    var preferredWidth: CGFloat {
        let measuredWidth = (titleLabel.stringValue as NSString).size(withAttributes: [.font: titleLabel.font as Any]).width
        let removeWidth: CGFloat = showsRemoveButton ? 22 : 0
        return min(160, max(72, measuredWidth + removeWidth + 20))
    }

    override func layout() {
        super.layout()
        refreshAppearance()

        if showsRemoveButton {
            removeButton.frame = NSRect(x: bounds.width - 18, y: (bounds.height - 12) / 2, width: 12, height: 12)
            titleLabel.frame = NSRect(x: 8, y: 4, width: bounds.width - 30, height: bounds.height - 8)
        } else {
            removeButton.frame = .zero
            titleLabel.frame = NSRect(x: 8, y: 4, width: bounds.width - 16, height: bounds.height - 8)
        }
    }

    func update(hop: SSHProxyJumpHopItem) {
        titleLabel.stringValue = hop.title
        isMissing = hop.isMissing
        showsRemoveButton = hop.id != nil
        removeButton.isHidden = !showsRemoveButton
        needsLayout = true
    }

    @objc private func handleRemove() {
        onRemove?()
    }

    private func refreshAppearance() {
        layer?.backgroundColor = (isMissing ? Theme.overlay.withAlphaComponent(0.28) : Theme.chromeElevated).cgColor
        layer?.borderColor = (isMissing ? Theme.border : Theme.chromeHairline).cgColor
        titleLabel.textColor = isMissing ? Theme.textSecondary : Theme.textPrimary
        removeButton.contentTintColor = Theme.textTertiary
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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
