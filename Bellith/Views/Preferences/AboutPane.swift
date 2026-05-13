import AppKit

// MARK: - About Pane

final class AboutPane: NSView {
    private let paneTitleLabel = NSTextField(labelWithString: "About")
    private let paneSubtitleLabel = NSTextField(labelWithString: "Version, credits, links, and local data.")
    private let heroSection = GradientAboutHeroSection()

    private let projectCard = SettingsCard(title: "Project", subtitle: "Credits and public links")
    private let projectIcon = NSImageView()
    private let creditsSectionLabel = SmallLabel("Credits")
    private let linksSectionLabel = SmallLabel("Links")
    private let projectDivider = NSView()
    private let ghosttyCredit = AboutPane.makeBodyLabel()
    private let authorCredit = AboutPane.makeBodyLabel()
    private let githubBtn = LinkButton(title: "GitHub Repository")
    private let docsBtn = LinkButton(title: "Documentation")

    private let dataCard = SettingsCard(title: "Local Data", subtitle: "Settings live in Application Support")
    private let dataIcon = NSImageView()
    private let themeFolderBtn = LinkButton(title: "Open Settings Folder")
    private let themeFolderPathLabel = AboutPane.makePathLabel()
    private let dataFootnote = AboutPane.makeCaptionLabel()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        paneTitleLabel.font = BellithFont.ui(20, weight: .medium)
        addSubview(paneTitleLabel)

        paneSubtitleLabel.font = BellithFont.ui(12, weight: .regular)
        addSubview(paneSubtitleLabel)

        addSubview(heroSection)

        configureHeroSection()
        configureProjectCard()
        configureDataCard()

        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        layer?.backgroundColor = Theme.frame.cgColor
        paneTitleLabel.textColor = Theme.textDisplay
        paneSubtitleLabel.textColor = Theme.textSecondary

        heroSection.refresh()

        projectCard.refresh()
        dataCard.refresh()

        projectIcon.contentTintColor = Theme.accent.withAlphaComponent(0.92)
        dataIcon.contentTintColor = Theme.accent.withAlphaComponent(0.92)
        projectDivider.layer?.backgroundColor = Theme.borderSubtle.cgColor

        [creditsSectionLabel, linksSectionLabel].forEach {
            $0.textColor = Theme.textSecondary
        }
        [ghosttyCredit, authorCredit].forEach {
            $0.textColor = Theme.textPrimary
        }
        themeFolderPathLabel.textColor = Theme.textSecondary
        dataFootnote.textColor = Theme.textMuted

        updateThemeFolderPath()
    }

    override func layout() {
        super.layout()

        let sideInset = PreferencesLayout.hPad
        let topInset = PreferencesLayout.hPad
        let bottomInset: CGFloat = 24
        let contentWidth = bounds.width - sideInset * 2
        let cardGap: CGFloat = 18
        let heroOverlap: CGFloat = 18

        paneTitleLabel.frame = NSRect(x: sideInset, y: bounds.height - topInset - 24, width: 280, height: 24)
        paneSubtitleLabel.frame = NSRect(x: sideInset, y: bounds.height - topInset - 46, width: contentWidth, height: 16)

        let cardsHeight = max(168, min(210, bounds.height * 0.29))
        let cardsY = bottomInset
        let heroTop = paneSubtitleLabel.frame.minY - 18
        let heroBottom = cardsY + cardsHeight - heroOverlap
        let heroHeight = max(250, heroTop - heroBottom)

        heroSection.frame = NSRect(x: sideInset, y: heroBottom, width: contentWidth, height: heroHeight)

        let dataCardWidth = max(176, min(212, floor(contentWidth * 0.34)))
        let projectCardWidth = contentWidth - dataCardWidth - cardGap
        projectCard.frame = NSRect(x: sideInset, y: cardsY, width: projectCardWidth, height: cardsHeight)
        dataCard.frame = NSRect(x: projectCard.frame.maxX + cardGap, y: cardsY, width: dataCardWidth, height: cardsHeight)

        layoutProjectCard()
        layoutDataCard()
    }

    private func configureHeroSection() {
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion
        let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        #if arch(arm64)
        let runtime = "Apple Silicon"
        #else
        let runtime = "Intel"
        #endif

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        heroSection.configure(version: version, build: build, osVersion: osVersionString, runtime: runtime)
    }

    private func configureProjectCard() {
        projectIcon.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        projectIcon.imageScaling = .scaleProportionallyDown
        projectCard.addSubview(projectIcon)

        projectDivider.wantsLayer = true
        projectCard.addSubview(projectDivider)

        ghosttyCredit.stringValue = "Powered by Ghostty terminal library"
        authorCredit.stringValue = "Designed and built by Rodrigo Espinosa"

        githubBtn.onClick = {
            guard let url = BellithBranding.repoURL else { return }
            NSWorkspace.shared.open(url)
        }
        docsBtn.onClick = {
            guard let url = BellithBranding.docsURL else { return }
            NSWorkspace.shared.open(url)
        }

        [
            creditsSectionLabel,
            ghosttyCredit,
            authorCredit,
            linksSectionLabel,
            githubBtn,
            docsBtn,
        ].forEach {
            projectCard.addSubview($0)
        }
    }

    private func configureDataCard() {
        dataIcon.image = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: nil)
        dataIcon.imageScaling = .scaleProportionallyDown
        dataCard.addSubview(dataIcon)

        themeFolderBtn.onClick = {
            if let dir = TerminalConfig.settingsConfigurationDirectory() {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                NSWorkspace.shared.open(dir)
            }
        }

        dataFootnote.stringValue = "Bellith stores generated terminal appearance files alongside settings."

        [themeFolderBtn, themeFolderPathLabel, dataFootnote].forEach {
            dataCard.addSubview($0)
        }

        updateThemeFolderPath()
    }

    private func updateThemeFolderPath() {
        let path = TerminalConfig.settingsConfigurationDirectory()?.path ?? "Unavailable"
        themeFolderPathLabel.stringValue = path
        themeFolderPathLabel.toolTip = path
    }

    private func layoutProjectCard() {
        let pad = PreferencesLayout.cardPad
        let innerWidth = projectCard.bounds.width - pad * 2
        let startY = projectCard.bounds.height - projectCard.headerHeight - 18

        projectIcon.frame = NSRect(x: projectCard.bounds.width - pad - 14, y: projectCard.bounds.height - 31, width: 14, height: 14)

        creditsSectionLabel.frame = NSRect(x: pad, y: startY, width: innerWidth, height: 12)
        ghosttyCredit.frame = NSRect(x: pad, y: startY - 24, width: innerWidth, height: 18)
        authorCredit.frame = NSRect(x: pad, y: startY - 48, width: innerWidth, height: 18)

        projectDivider.frame = NSRect(x: pad, y: startY - 66, width: innerWidth, height: 1)

        linksSectionLabel.frame = NSRect(x: pad, y: startY - 88, width: innerWidth, height: 12)
        githubBtn.frame = NSRect(x: pad, y: startY - 112, width: innerWidth, height: 18)
        docsBtn.frame = NSRect(x: pad, y: startY - 136, width: innerWidth, height: 18)
    }

    private func layoutDataCard() {
        let pad = PreferencesLayout.cardPad
        let innerWidth = dataCard.bounds.width - pad * 2
        let startY = dataCard.bounds.height - dataCard.headerHeight - 18

        dataIcon.frame = NSRect(x: dataCard.bounds.width - pad - 14, y: dataCard.bounds.height - 31, width: 14, height: 14)
        themeFolderBtn.frame = NSRect(x: pad, y: startY - 2, width: innerWidth, height: 18)
        themeFolderPathLabel.frame = NSRect(x: pad, y: startY - 36, width: innerWidth, height: 36)
        dataFootnote.frame = NSRect(x: pad, y: 18, width: innerWidth, height: 30)
    }

    private static func makeBodyLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = BellithFont.ui(12, weight: .regular)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        if let cell = label.cell as? NSTextFieldCell {
            cell.lineBreakMode = .byTruncatingTail
            cell.usesSingleLineMode = true
        }
        return label
    }

    private static func makeCaptionLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = BellithFont.mono(10, weight: .regular)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }

    private static func makePathLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = BellithFont.mono(10, weight: .regular)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }
}

private final class GradientAboutHeroSection: NSView {
    private let gradientLayer = CAGradientLayer()
    private let glowLayer = CAGradientLayer()
    private let sheenLayer = CAGradientLayer()

    private let watermarkHalo = NSView()
    private let watermarkLogo = NSImageView()

    private let iconPlate = NSView()
    private let appIcon = NSImageView()
    private let overlineLabel = NSTextField(labelWithString: "BELLITH")
    private let titleLabel = NSTextField(labelWithString: "A premium terminal for macOS")
    private let subtitleLabel = NSTextField(labelWithString: "Native windowing, crisp typography, and Ghostty performance in a calmer desktop shell.")

    private let versionPill = AboutPillView(emphasized: true)
    private let buildPill = AboutPillView()
    private let runtimePill = AboutPillView()

    private let infoPlate = NSView()
    private let versionKeyLabel = SmallLabel("Version")
    private let versionValueLabel = GradientAboutHeroSection.makeValueLabel()
    private let buildKeyLabel = SmallLabel("Build")
    private let buildValueLabel = GradientAboutHeroSection.makeValueLabel()
    private let osKeyLabel = SmallLabel("macOS")
    private let osValueLabel = GradientAboutHeroSection.makeValueLabel()
    private let runtimeKeyLabel = SmallLabel("Architecture")
    private let runtimeValueLabel = GradientAboutHeroSection.makeValueLabel()
    private let rowDividerOne = NSView()
    private let rowDividerTwo = NSView()
    private let rowDividerThree = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 28
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradientLayer)

        glowLayer.startPoint = CGPoint(x: 1, y: 0.2)
        glowLayer.endPoint = CGPoint(x: 0.2, y: 1)
        layer?.addSublayer(glowLayer)

        sheenLayer.startPoint = CGPoint(x: 0, y: 1)
        sheenLayer.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(sheenLayer)

        watermarkHalo.wantsLayer = true
        addSubview(watermarkHalo)

        watermarkLogo.image = BellithBranding.logoImage(accessibilityDescription: BellithBranding.appName)
        watermarkLogo.imageScaling = .scaleProportionallyUpOrDown
        addSubview(watermarkLogo)

        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 18
        iconPlate.layer?.cornerCurve = .continuous
        iconPlate.layer?.borderWidth = 0.8
        addSubview(iconPlate)

        appIcon.image = BellithBranding.logoImage(accessibilityDescription: BellithBranding.appName)
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        iconPlate.addSubview(appIcon)

        overlineLabel.font = BellithFont.mono(10, weight: .regular)
        titleLabel.font = BellithFont.ui(28, weight: .medium)
        subtitleLabel.font = BellithFont.ui(12, weight: .regular)
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.lineBreakMode = .byWordWrapping

        [overlineLabel, titleLabel, subtitleLabel, versionPill, buildPill, runtimePill].forEach {
            addSubview($0)
        }

        infoPlate.wantsLayer = true
        infoPlate.layer?.cornerRadius = 18
        infoPlate.layer?.cornerCurve = .continuous
        infoPlate.layer?.borderWidth = 0.8
        addSubview(infoPlate)

        [rowDividerOne, rowDividerTwo, rowDividerThree].forEach {
            $0.wantsLayer = true
            infoPlate.addSubview($0)
        }

        [
            versionKeyLabel,
            versionValueLabel,
            buildKeyLabel,
            buildValueLabel,
            osKeyLabel,
            osValueLabel,
            runtimeKeyLabel,
            runtimeValueLabel,
        ].forEach {
            infoPlate.addSubview($0)
        }

        refresh()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func configure(version: String, build: String, osVersion: String, runtime: String) {
        versionPill.text = "VERSION \(version)"
        buildPill.text = "BUILD \(build)"
        runtimePill.text = runtime.uppercased()

        versionValueLabel.stringValue = version
        buildValueLabel.stringValue = build
        osValueLabel.stringValue = osVersion
        runtimeValueLabel.stringValue = runtime.uppercased()
        needsLayout = true
    }

    func refresh() {
        let topLeft = Theme.chromePanel.blended(withFraction: 0.42, of: Theme.accent) ?? Theme.chromePanel
        let middle = Theme.surface.blended(withFraction: 0.18, of: Theme.accent) ?? Theme.surface
        let bottomRight = Theme.frame.blended(withFraction: 0.08, of: Theme.accent) ?? Theme.frame

        gradientLayer.colors = [topLeft.cgColor, middle.cgColor, bottomRight.cgColor]
        gradientLayer.locations = [0, 0.48, 1]

        glowLayer.colors = [Theme.accent.withAlphaComponent(0.22).cgColor, NSColor.clear.cgColor]
        glowLayer.locations = [0, 1]

        sheenLayer.colors = [
            NSColor.white.withAlphaComponent(Theme.colors.isLight ? 0.14 : 0.08).cgColor,
            NSColor.clear.cgColor,
        ]
        sheenLayer.locations = [0, 0.72]

        watermarkHalo.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.12).cgColor
        watermarkHalo.layer?.cornerRadius = 110

        watermarkLogo.alphaValue = Theme.colors.isLight ? 0.22 : 0.14

        iconPlate.layer?.backgroundColor = Theme.frame.withAlphaComponent(0.22).cgColor
        iconPlate.layer?.borderColor = Theme.accent.withAlphaComponent(0.18).cgColor
        appIcon.alphaValue = 1

        overlineLabel.textColor = Theme.textSecondary
        titleLabel.textColor = Theme.textDisplay
        subtitleLabel.textColor = Theme.textPrimary

        infoPlate.layer?.backgroundColor = Theme.frame.withAlphaComponent(0.18).cgColor
        infoPlate.layer?.borderColor = Theme.accent.withAlphaComponent(0.16).cgColor
        [versionKeyLabel, buildKeyLabel, osKeyLabel, runtimeKeyLabel].forEach {
            $0.textColor = Theme.textSecondary
        }
        [versionValueLabel, buildValueLabel, osValueLabel, runtimeValueLabel].forEach {
            $0.textColor = Theme.textDisplay
        }
        [rowDividerOne, rowDividerTwo, rowDividerThree].forEach {
            $0.layer?.backgroundColor = Theme.borderSubtle.withAlphaComponent(0.8).cgColor
        }

        versionPill.refresh()
        buildPill.refresh()
        runtimePill.refresh()
    }

    override func layout() {
        super.layout()

        gradientLayer.frame = bounds
        glowLayer.frame = bounds
        sheenLayer.frame = bounds

        let pad: CGFloat = 26
        let infoWidth = max(170, min(206, bounds.width * 0.4))
        let leftWidth = bounds.width - infoWidth - pad * 3

        watermarkHalo.frame = NSRect(x: bounds.width - 220, y: bounds.height - 212, width: 220, height: 220)
        watermarkLogo.frame = NSRect(x: bounds.width - 214, y: bounds.height - 204, width: 204, height: 204)

        iconPlate.frame = NSRect(x: pad, y: bounds.height - pad - 60, width: 60, height: 60)
        appIcon.frame = iconPlate.bounds.insetBy(dx: 12, dy: 12)

        let textX = iconPlate.frame.maxX + 16
        overlineLabel.frame = NSRect(x: textX, y: bounds.height - pad - 15, width: leftWidth - 76, height: 14)
        titleLabel.frame = NSRect(x: textX, y: bounds.height - pad - 48, width: leftWidth - 32, height: 34)
        subtitleLabel.frame = NSRect(x: pad, y: bounds.height - pad - 108, width: leftWidth, height: 40)

        let pillY: CGFloat = 28
        let versionWidth = versionPill.width(forHeight: 28)
        let buildWidth = buildPill.width(forHeight: 28)
        let runtimeWidth = min(runtimePill.width(forHeight: 28), max(92, leftWidth - versionWidth - buildWidth - 20))

        versionPill.frame = NSRect(x: pad, y: pillY, width: versionWidth, height: 28)
        buildPill.frame = NSRect(x: versionPill.frame.maxX + 8, y: pillY, width: buildWidth, height: 28)
        runtimePill.frame = NSRect(x: buildPill.frame.maxX + 8, y: pillY, width: runtimeWidth, height: 28)

        infoPlate.frame = NSRect(x: bounds.width - pad - infoWidth, y: 26, width: infoWidth, height: min(154, bounds.height - 52))
        layoutInfoPlate()
    }

    private func layoutInfoPlate() {
        let pad: CGFloat = 16
        let rowHeight: CGFloat = 30
        let rowGap: CGFloat = 8
        let width = infoPlate.bounds.width - pad * 2
        let startY = infoPlate.bounds.height - pad - rowHeight

        layoutInfoRow(key: versionKeyLabel, value: versionValueLabel, y: startY, width: width)
        rowDividerOne.frame = NSRect(x: pad, y: startY - 6, width: width, height: 1)

        layoutInfoRow(key: buildKeyLabel, value: buildValueLabel, y: startY - (rowHeight + rowGap), width: width)
        rowDividerTwo.frame = NSRect(x: pad, y: startY - (rowHeight + rowGap) - 6, width: width, height: 1)

        layoutInfoRow(key: osKeyLabel, value: osValueLabel, y: startY - (rowHeight + rowGap) * 2, width: width)
        rowDividerThree.frame = NSRect(x: pad, y: startY - (rowHeight + rowGap) * 2 - 6, width: width, height: 1)

        layoutInfoRow(key: runtimeKeyLabel, value: runtimeValueLabel, y: startY - (rowHeight + rowGap) * 3, width: width)
    }

    private func layoutInfoRow(key: NSTextField, value: NSTextField, y: CGFloat, width: CGFloat) {
        let x: CGFloat = 16
        key.frame = NSRect(x: x, y: y + 14, width: width, height: 12)
        value.frame = NSRect(x: x, y: y - 1, width: width, height: 18)
    }

    private static func makeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = BellithFont.mono(12, weight: .regular)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        if let cell = label.cell as? NSTextFieldCell {
            cell.lineBreakMode = .byTruncatingMiddle
            cell.usesSingleLineMode = true
        }
        return label
    }
}

private final class AboutPillView: NSView {
    var text: String = "" {
        didSet {
            label.stringValue = text
            needsLayout = true
        }
    }

    private let emphasized: Bool
    private let label = NSTextField(labelWithString: "")

    init(emphasized: Bool = false) {
        self.emphasized = emphasized
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.8

        label.font = BellithFont.mono(10, weight: .regular)
        label.alignment = .center
        addSubview(label)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        if emphasized {
            layer?.backgroundColor = Theme.textDisplay.withAlphaComponent(0.12).cgColor
            layer?.borderColor = Theme.textDisplay.withAlphaComponent(0.16).cgColor
            label.textColor = Theme.textDisplay
        } else {
            layer?.backgroundColor = Theme.frame.withAlphaComponent(0.18).cgColor
            layer?.borderColor = Theme.borderSubtle.cgColor
            label.textColor = Theme.textSecondary
        }
    }

    func width(forHeight height: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: label.font as Any]
        let textWidth = ceil((text as NSString).size(withAttributes: attrs).width)
        return max(height + 8, textWidth + 22)
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 10, y: (bounds.height - 14) / 2, width: bounds.width - 20, height: 14)
    }
}
