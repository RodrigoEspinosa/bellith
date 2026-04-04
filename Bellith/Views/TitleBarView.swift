import AppKit

/// Breadcrumb-style title bar showing the current working directory path.
/// Sits in the window's title area with a folder icon prefix.
final class TitleBarView: NSView {
    private let folderIcon = NSImageView()
    private var breadcrumbViews: [NSView] = []
    private var currentPath: String = "~"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        folderIcon.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        folderIcon.contentTintColor = Theme.textMuted.withAlphaComponent(0.5)
        folderIcon.imageScaling = .scaleProportionallyDown
        addSubview(folderIcon)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func updatePath(_ path: String?) {
        let raw = path ?? "~"
        let home = NSHomeDirectory()
        var display = raw
        if display.hasPrefix(home) {
            display = "~" + display.dropFirst(home.count)
        }
        guard display != currentPath else { return }
        currentPath = display
        rebuildBreadcrumbs()
    }

    private func rebuildBreadcrumbs() {
        breadcrumbViews.forEach { $0.removeFromSuperview() }
        breadcrumbViews.removeAll()

        let components = currentPath.split(separator: "/", omittingEmptySubsequences: true)
        let allParts: [String]
        if currentPath.hasPrefix("~") {
            if components.count <= 1 {
                allParts = ["~"]
            } else {
                allParts = ["~"] + components.dropFirst().map(String.init)
            }
        } else {
            allParts = ["/"] + components.map(String.init)
        }

        for (i, part) in allParts.enumerated() {
            let isLast = i == allParts.count - 1

            // Chevron separator
            if i > 0 {
                let chevron = NSImageView()
                chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
                chevron.contentTintColor = Theme.textMuted.withAlphaComponent(0.3)
                chevron.imageScaling = .scaleProportionallyDown
                addSubview(chevron)
                breadcrumbViews.append(chevron)
            }

            let label = NSTextField(labelWithString: part)
            label.font = .systemFont(ofSize: 12.5, weight: isLast ? .medium : .regular)
            label.textColor = isLast ? Theme.textSecondary : Theme.textMuted.withAlphaComponent(0.5)
            label.isEditable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
            breadcrumbViews.append(label)
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let iconSize: CGFloat = 12
        var x: CGFloat = 0
        let gap: CGFloat = 4

        folderIcon.frame = NSRect(x: x, y: (h - iconSize) / 2, width: iconSize, height: iconSize)
        x += iconSize + gap + 2

        for view in breadcrumbViews {
            if let imageView = view as? NSImageView {
                let size: CGFloat = 9
                imageView.frame = NSRect(x: x, y: (h - size) / 2, width: size, height: size)
                x += size + gap
            } else if let label = view as? NSTextField {
                let textW = min(150, label.attributedStringValue.size().width + 4)
                label.frame = NSRect(x: x, y: (h - 15) / 2, width: textW, height: 15)
                x += textW + gap
            }
        }
    }

    func refreshTheme() {
        folderIcon.contentTintColor = Theme.textMuted.withAlphaComponent(0.5)
        rebuildBreadcrumbs()
    }
}
