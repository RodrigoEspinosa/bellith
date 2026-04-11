import AppKit

enum BellithBranding {
    static let appName = "Bellith"
    static let repoURL = URL(string: "https://github.com/RodrigoEspinosa/bellith")
    static let docsURL = URL(string: "https://github.com/RodrigoEspinosa/bellith#readme")
    private static let logoAssetName = NSImage.Name("BellithLogo")

    static func logoImage(accessibilityDescription: String? = nil) -> NSImage {
        if let assetImage = NSImage(named: logoAssetName)?.copy() as? NSImage {
            assetImage.accessibilityDescription = accessibilityDescription
            return assetImage
        }

        if let appIcon = NSApp.applicationIconImage.copy() as? NSImage {
            appIcon.accessibilityDescription = accessibilityDescription
            return appIcon
        }

        let fallback = NSImage(systemSymbolName: "terminal", accessibilityDescription: accessibilityDescription) ?? NSImage()
        fallback.accessibilityDescription = accessibilityDescription
        return fallback
    }

    static func aboutPanelOptions() -> [NSApplication.AboutPanelOptionKey: Any] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 4

        let credits = NSAttributedString(
            string: "A native macOS terminal powered by GhosttyKit.\nDesigned & built by Rodrigo Espinosa.",
            attributes: [
                .paragraphStyle: paragraph,
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        return [
            .applicationName: appName,
            .applicationVersion: version,
            .version: build,
            .applicationIcon: logoImage(accessibilityDescription: appName),
            .credits: credits
        ]
    }
}
