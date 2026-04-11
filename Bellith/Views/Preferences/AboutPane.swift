import AppKit

// MARK: - About Pane

final class AboutPane: NSView {
    private let appIcon = NSImageView()
    private let overlineLabel = NSTextField(labelWithString: "TERMINAL EMULATOR")
    private let appName = NSTextField(labelWithString: "BELLITH")
    private let versionLabel = NSTextField(labelWithString: "")
    private let buildLabel = NSTextField(labelWithString: "")

    private let systemCard = SettingsCard(title: "System")
    private let osLabel = CardRowLabel("macOS")
    private let osValue = NSTextField(labelWithString: "")
    private let runtimeLabel = CardRowLabel("Architecture")
    private let runtimeValue = NSTextField(labelWithString: "")

    private let creditsCard = SettingsCard(title: "Credits")
    private let ghosttyCredit = NSTextField(labelWithString: "")
    private let authorCredit = NSTextField(labelWithString: "")

    private let linksCard = SettingsCard(title: "Links")
    private let githubBtn = LinkButton(title: "GitHub Repository")
    private let docsBtn = LinkButton(title: "Documentation")

    private let dataCard = SettingsCard(title: "Data")
    private let themeFolderBtn = LinkButton(title: "Open Custom Themes Folder")
    private let copyrightLabel = NSTextField(labelWithString: "")
    private let signalDot = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        appIcon.image = BellithBranding.logoImage(accessibilityDescription: BellithBranding.appName)
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(appIcon)

        overlineLabel.font = BellithFont.mono(10, weight: .regular)
        overlineLabel.alignment = .center
        addSubview(overlineLabel)

        appName.font = BellithFont.display(32)
        appName.alignment = .center
        addSubview(appName)

        let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        versionLabel.stringValue = "VERSION \(ver)"
        versionLabel.font = BellithFont.mono(11, weight: .regular)
        versionLabel.alignment = .center
        addSubview(versionLabel)

        buildLabel.stringValue = "BUILD \(build)"
        buildLabel.font = BellithFont.mono(10, weight: .regular)
        buildLabel.alignment = .center
        addSubview(buildLabel)

        signalDot.wantsLayer = true
        signalDot.layer?.cornerRadius = 3
        addSubview(signalDot)

        addSubview(systemCard)
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion
        osValue.stringValue = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        osValue.font = BellithFont.mono(12, weight: .regular)
        osValue.alignment = .right
        osValue.isEditable = false; osValue.isBezeled = false; osValue.drawsBackground = false
        systemCard.addSubview(osLabel)
        systemCard.addSubview(osValue)

        #if arch(arm64)
        runtimeValue.stringValue = "APPLE SILICON"
        #else
        runtimeValue.stringValue = "INTEL"
        #endif
        runtimeValue.font = BellithFont.mono(12, weight: .regular)
        runtimeValue.alignment = .right
        runtimeValue.isEditable = false; runtimeValue.isBezeled = false; runtimeValue.drawsBackground = false
        systemCard.addSubview(runtimeLabel)
        systemCard.addSubview(runtimeValue)

        addSubview(creditsCard)
        ghosttyCredit.stringValue = "Powered by Ghostty terminal library"
        ghosttyCredit.font = BellithFont.ui(12, weight: .regular)
        ghosttyCredit.isEditable = false; ghosttyCredit.isBezeled = false; ghosttyCredit.drawsBackground = false
        creditsCard.addSubview(ghosttyCredit)

        authorCredit.stringValue = "Designed & built by Rodrigo Espinosa"
        authorCredit.font = BellithFont.ui(12, weight: .regular)
        authorCredit.isEditable = false; authorCredit.isBezeled = false; authorCredit.drawsBackground = false
        creditsCard.addSubview(authorCredit)

        addSubview(linksCard)
        githubBtn.onClick = {
            guard let url = BellithBranding.repoURL else { return }
            NSWorkspace.shared.open(url)
        }
        docsBtn.onClick = {
            guard let url = BellithBranding.docsURL else { return }
            NSWorkspace.shared.open(url)
        }
        linksCard.addSubview(githubBtn)
        linksCard.addSubview(docsBtn)

        addSubview(dataCard)
        themeFolderBtn.onClick = {
            if let dir = CustomThemeLoader.shared.themesDirectory {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                NSWorkspace.shared.open(dir)
            }
        }
        dataCard.addSubview(themeFolderBtn)

        copyrightLabel.stringValue = "© 2026 BELLITH"
        copyrightLabel.font = BellithFont.mono(10, weight: .regular)
        copyrightLabel.alignment = .center
        addSubview(copyrightLabel)

        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        layer?.backgroundColor = Theme.base.cgColor
        overlineLabel.textColor = Theme.textSecondary
        appName.textColor = Theme.textDisplay
        versionLabel.textColor = Theme.textPrimary
        buildLabel.textColor = Theme.textSecondary
        signalDot.layer?.backgroundColor = Theme.accent.cgColor
        systemCard.refresh()
        creditsCard.refresh()
        linksCard.refresh()
        dataCard.refresh()
        osValue.textColor = Theme.textPrimary
        runtimeValue.textColor = Theme.textPrimary
        ghosttyCredit.textColor = Theme.textPrimary
        authorCredit.textColor = Theme.textPrimary
        copyrightLabel.textColor = Theme.textMuted
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let cardW = width - PreferencesLayout.hPad * 2
        let innerW = cardW - PreferencesLayout.cardPad * 2

        let iconSize: CGFloat = 64
        appIcon.frame = NSRect(x: (width - iconSize) / 2, y: bounds.height - 104, width: iconSize, height: iconSize)
        overlineLabel.frame = NSRect(x: 0, y: appIcon.frame.minY - 20, width: width, height: 14)
        appName.frame = NSRect(x: 0, y: overlineLabel.frame.minY - 36, width: width, height: 32)
        versionLabel.frame = NSRect(x: 0, y: appName.frame.minY - 24, width: width, height: 14)
        buildLabel.frame = NSRect(x: 0, y: versionLabel.frame.minY - 18, width: width, height: 12)
        signalDot.frame = NSRect(x: (width - 6) / 2, y: buildLabel.frame.minY - 18, width: 6, height: 6)

        var y = signalDot.frame.minY - 28

        let systemCardHeight = systemCard.headerHeight + 2 * PreferencesLayout.rowH + PreferencesLayout.rowGap + PreferencesLayout.cardPad
        systemCard.frame = NSRect(x: PreferencesLayout.hPad, y: y - systemCardHeight, width: cardW, height: systemCardHeight)
        let sr0 = systemCardHeight - systemCard.headerHeight - PreferencesLayout.rowH
        osLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sr0, width: 100, height: PreferencesLayout.rowH)
        osValue.frame = NSRect(x: PreferencesLayout.cardPad + 100, y: sr0 + 12, width: innerW - 100, height: 16)
        let sr1 = sr0 - PreferencesLayout.rowH - PreferencesLayout.rowGap
        runtimeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sr1, width: 100, height: PreferencesLayout.rowH)
        runtimeValue.frame = NSRect(x: PreferencesLayout.cardPad + 100, y: sr1 + 12, width: innerW - 100, height: 16)
        y -= systemCardHeight + PreferencesLayout.sectionGap

        let creditsCardHeight = creditsCard.headerHeight + 2 * 24 + PreferencesLayout.cardPad
        creditsCard.frame = NSRect(x: PreferencesLayout.hPad, y: y - creditsCardHeight, width: cardW, height: creditsCardHeight)
        let crTop = creditsCardHeight - creditsCard.headerHeight
        ghosttyCredit.frame = NSRect(x: PreferencesLayout.cardPad, y: crTop - 24, width: innerW, height: 16)
        authorCredit.frame = NSRect(x: PreferencesLayout.cardPad, y: crTop - 48, width: innerW, height: 16)
        y -= creditsCardHeight + PreferencesLayout.sectionGap

        let linksCardHeight = linksCard.headerHeight + 2 * 24 + PreferencesLayout.cardPad
        linksCard.frame = NSRect(x: PreferencesLayout.hPad, y: y - linksCardHeight, width: cardW, height: linksCardHeight)
        let lrTop = linksCardHeight - linksCard.headerHeight
        githubBtn.frame = NSRect(x: PreferencesLayout.cardPad, y: lrTop - 24, width: innerW, height: 16)
        docsBtn.frame = NSRect(x: PreferencesLayout.cardPad, y: lrTop - 48, width: innerW, height: 16)
        y -= linksCardHeight + PreferencesLayout.sectionGap

        let dataCardHeight = dataCard.headerHeight + PreferencesLayout.rowH + PreferencesLayout.cardPad
        dataCard.frame = NSRect(x: PreferencesLayout.hPad, y: y - dataCardHeight, width: cardW, height: dataCardHeight)
        let dr0 = dataCardHeight - dataCard.headerHeight - PreferencesLayout.rowH
        themeFolderBtn.frame = NSRect(x: PreferencesLayout.cardPad, y: dr0 + 12, width: innerW, height: 16)
        y -= dataCardHeight + PreferencesLayout.sectionGap

        copyrightLabel.frame = NSRect(x: 0, y: max(12, y - 10), width: width, height: 12)
    }
}
