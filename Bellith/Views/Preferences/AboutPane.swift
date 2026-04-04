import AppKit

// MARK: - About Pane

final class AboutPane: NSView {
    private let appIcon = NSImageView()
    private let appName = NSTextField(labelWithString: "Bellith")
    private let appTagline = NSTextField(labelWithString: "A modern terminal emulator")
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
    private let accentDot = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        // App icon
        if let icon = NSApp.applicationIconImage {
            appIcon.image = icon
        } else {
            appIcon.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Bellith")
            appIcon.contentTintColor = Theme.accent
        }
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(appIcon)

        // Accent dot
        accentDot.wantsLayer = true
        accentDot.layer?.cornerRadius = 3
        accentDot.layer?.backgroundColor = Theme.accent.cgColor
        addSubview(accentDot)

        // App name
        appName.font = .systemFont(ofSize: 28, weight: .bold)
        appName.textColor = Theme.textPrimary
        appName.alignment = .center
        addSubview(appName)

        // Tagline
        appTagline.font = .systemFont(ofSize: 13)
        appTagline.textColor = Theme.textMuted
        appTagline.alignment = .center
        addSubview(appTagline)

        // Version
        let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        versionLabel.stringValue = "Version \(ver)"
        versionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        versionLabel.textColor = Theme.textSecondary
        versionLabel.alignment = .center
        addSubview(versionLabel)

        buildLabel.stringValue = "Build \(build)"
        buildLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        buildLabel.textColor = Theme.textMuted
        buildLabel.alignment = .center
        addSubview(buildLabel)

        // System card
        addSubview(systemCard)
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion
        osValue.stringValue = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        osValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        osValue.textColor = Theme.textSecondary
        osValue.alignment = .right
        osValue.isEditable = false; osValue.isBezeled = false; osValue.drawsBackground = false
        systemCard.addSubview(osLabel)
        systemCard.addSubview(osValue)

        #if arch(arm64)
        let arch = "Apple Silicon"
        #else
        let arch = "Intel"
        #endif
        runtimeValue.stringValue = arch
        runtimeValue.font = .systemFont(ofSize: 12, weight: .medium)
        runtimeValue.textColor = Theme.textSecondary
        runtimeValue.alignment = .right
        runtimeValue.isEditable = false; runtimeValue.isBezeled = false; runtimeValue.drawsBackground = false
        systemCard.addSubview(runtimeLabel)
        systemCard.addSubview(runtimeValue)

        // Credits card
        addSubview(creditsCard)
        ghosttyCredit.stringValue = "Powered by Ghostty terminal library"
        ghosttyCredit.font = .systemFont(ofSize: 12)
        ghosttyCredit.textColor = Theme.textSecondary
        ghosttyCredit.isEditable = false; ghosttyCredit.isBezeled = false; ghosttyCredit.drawsBackground = false
        creditsCard.addSubview(ghosttyCredit)

        authorCredit.stringValue = "Designed & built by Rodrigo Espinosa"
        authorCredit.font = .systemFont(ofSize: 12)
        authorCredit.textColor = Theme.textSecondary
        authorCredit.isEditable = false; authorCredit.isBezeled = false; authorCredit.drawsBackground = false
        creditsCard.addSubview(authorCredit)

        // Links card
        addSubview(linksCard)
        githubBtn.onClick = {
            if let url = URL(string: "https://github.com/RodrigoEspinosa/bellith") {
                NSWorkspace.shared.open(url)
            }
        }
        linksCard.addSubview(githubBtn)
        docsBtn.onClick = {
            if let url = URL(string: "https://github.com/RodrigoEspinosa/bellith#readme") {
                NSWorkspace.shared.open(url)
            }
        }
        linksCard.addSubview(docsBtn)

        // Data card
        addSubview(dataCard)
        themeFolderBtn.onClick = {
            if let dir = CustomThemeLoader.shared.themesDirectory {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                NSWorkspace.shared.open(dir)
            }
        }
        dataCard.addSubview(themeFolderBtn)

        // Copyright
        copyrightLabel.stringValue = "\u{00A9} 2026 Bellith. All rights reserved."
        copyrightLabel.font = .systemFont(ofSize: 10)
        copyrightLabel.textColor = Theme.textMuted
        copyrightLabel.alignment = .center
        addSubview(copyrightLabel)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        appName.textColor = Theme.textPrimary
        appTagline.textColor = Theme.textMuted
        versionLabel.textColor = Theme.textSecondary
        buildLabel.textColor = Theme.textMuted
        accentDot.layer?.backgroundColor = Theme.accent.cgColor
        systemCard.refresh()
        creditsCard.refresh()
        linksCard.refresh()
        dataCard.refresh()
        osValue.textColor = Theme.textSecondary
        runtimeValue.textColor = Theme.textSecondary
        ghosttyCredit.textColor = Theme.textSecondary
        authorCredit.textColor = Theme.textSecondary
        copyrightLabel.textColor = Theme.textMuted
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let cardW = w - PreferencesLayout.hPad * 2
        let innerW = cardW - PreferencesLayout.cardPad * 2

        // Center the app icon area
        let iconSize: CGFloat = 64
        appIcon.frame = NSRect(x: (w - iconSize) / 2, y: bounds.height - PreferencesLayout.hPad - iconSize - 10, width: iconSize, height: iconSize)

        var y = appIcon.frame.minY - 8
        accentDot.frame = NSRect(x: (w - 6) / 2, y: y - 6, width: 6, height: 6)
        y -= 16

        appName.frame = NSRect(x: 0, y: y - 30, width: w, height: 30)
        y -= 38
        appTagline.frame = NSRect(x: 0, y: y - 16, width: w, height: 16)
        y -= 26
        versionLabel.frame = NSRect(x: 0, y: y - 16, width: w, height: 16)
        y -= 18
        buildLabel.frame = NSRect(x: 0, y: y - 14, width: w, height: 14)
        y -= 30

        // System card
        let sysCardH: CGFloat = systemCard.headerHeight + 2 * PreferencesLayout.rowH + PreferencesLayout.rowGap + PreferencesLayout.cardPad
        systemCard.frame = NSRect(x: PreferencesLayout.hPad, y: y - sysCardH, width: cardW, height: sysCardH)
        let sysTop = sysCardH - systemCard.headerHeight
        osLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sysTop - PreferencesLayout.rowH + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        osValue.frame = NSRect(x: PreferencesLayout.cardPad + 80, y: sysTop - PreferencesLayout.rowH + (PreferencesLayout.rowH - 16) / 2, width: innerW - 80, height: 16)
        runtimeLabel.frame = NSRect(x: PreferencesLayout.cardPad, y: sysTop - 2 * PreferencesLayout.rowH - PreferencesLayout.rowGap + (PreferencesLayout.rowH - 16) / 2, width: 80, height: 16)
        runtimeValue.frame = NSRect(x: PreferencesLayout.cardPad + 80, y: sysTop - 2 * PreferencesLayout.rowH - PreferencesLayout.rowGap + (PreferencesLayout.rowH - 16) / 2, width: innerW - 80, height: 16)

        y -= sysCardH + PreferencesLayout.sectionGap

        // Credits card
        let creditsCardH: CGFloat = creditsCard.headerHeight + 2 * 24 + PreferencesLayout.cardPad
        creditsCard.frame = NSRect(x: PreferencesLayout.hPad, y: y - creditsCardH, width: cardW, height: creditsCardH)
        let credTop = creditsCardH - creditsCard.headerHeight
        ghosttyCredit.frame = NSRect(x: PreferencesLayout.cardPad, y: credTop - 24, width: innerW, height: 16)
        authorCredit.frame = NSRect(x: PreferencesLayout.cardPad, y: credTop - 48, width: innerW, height: 16)

        y -= creditsCardH + PreferencesLayout.sectionGap

        // Links card
        let linksCardH: CGFloat = linksCard.headerHeight + 2 * 24 + PreferencesLayout.cardPad
        linksCard.frame = NSRect(x: PreferencesLayout.hPad, y: y - linksCardH, width: cardW, height: linksCardH)
        let linksTop = linksCardH - linksCard.headerHeight
        githubBtn.frame = NSRect(x: PreferencesLayout.cardPad, y: linksTop - 24, width: innerW, height: 16)
        docsBtn.frame = NSRect(x: PreferencesLayout.cardPad, y: linksTop - 48, width: innerW, height: 16)
        y -= linksCardH + PreferencesLayout.sectionGap

        // Data card
        let dataCardH: CGFloat = dataCard.headerHeight + PreferencesLayout.rowH + PreferencesLayout.cardPad
        dataCard.frame = NSRect(x: PreferencesLayout.hPad, y: y - dataCardH, width: cardW, height: dataCardH)
        let dataTop = dataCardH - dataCard.headerHeight
        themeFolderBtn.frame = NSRect(x: PreferencesLayout.cardPad, y: dataTop - PreferencesLayout.rowH + (PreferencesLayout.rowH - 16) / 2, width: innerW, height: 16)
        y -= dataCardH + PreferencesLayout.sectionGap

        // Copyright
        copyrightLabel.frame = NSRect(x: 0, y: max(12, y - 20), width: w, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Subtle radial gradient from accent at top
        let center = NSPoint(x: bounds.midX, y: bounds.height - 20)
        let radius = bounds.width * 0.6
        let gradient = NSGradient(colors: [
            Theme.accent.withAlphaComponent(0.04),
            NSColor.clear,
        ])
        gradient?.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
    }
}
