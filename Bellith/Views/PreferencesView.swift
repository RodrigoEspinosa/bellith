import AppKit

/// Zen-style preferences window with sections for appearance and terminal settings.
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.base
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()

        super.init(window: window)
        window.contentView = PreferencesContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Content View

private final class PreferencesContentView: NSView {
    private let settings = BellithSettings.shared
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.base.cgColor

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        addSubview(scrollView)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.edgeInsets = NSEdgeInsets(top: 48, left: 32, bottom: 24, right: 32)

        scrollView.documentView = stackView

        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        // Set the stack view width to match the scroll view's clip view
        let clipWidth = scrollView.contentView.bounds.width
        stackView.setFrameSize(NSSize(width: clipWidth, height: stackView.fittingSize.height))
    }

    private func buildUI() {
        addSection("Appearance")

        // Theme picker
        addRow("Theme") {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            for theme in ThemeColors.allThemes {
                popup.addItem(withTitle: theme.name)
            }
            popup.selectItem(withTitle: settings.themeName)
            popup.target = self
            popup.action = #selector(themeChanged(_:))
            popup.bezelStyle = .roundRect
            return popup
        }

        // Tab mode
        addRow("Tab Style") {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItem(withTitle: "Sidebar")
            popup.addItem(withTitle: "Tab Bar")
            popup.selectItem(withTitle: settings.tabMode == "sidebar" ? "Sidebar" : "Tab Bar")
            popup.target = self
            popup.action = #selector(tabModeChanged(_:))
            popup.bezelStyle = .roundRect
            return popup
        }

        // Background opacity
        addRow("Opacity") {
            let slider = NSSlider(value: settings.backgroundOpacity, minValue: 0.3, maxValue: 1.0,
                                  target: self, action: #selector(opacityChanged(_:)))
            slider.setFrameSize(NSSize(width: 180, height: 21))
            return slider
        }

        addSpacer()
        addSection("Terminal")

        // Font family
        addRow("Font") {
            let field = NSTextField(string: settings.fontFamily)
            field.font = .systemFont(ofSize: 13)
            field.textColor = Theme.textPrimary
            field.backgroundColor = Theme.surface
            field.isBordered = true
            field.bezelStyle = .roundedBezel
            field.setFrameSize(NSSize(width: 200, height: 24))
            field.target = self
            field.action = #selector(fontChanged(_:))
            return field
        }

        // Font size
        addRow("Size") {
            let stepper = NSStepper()
            stepper.minValue = 8
            stepper.maxValue = 36
            stepper.integerValue = settings.fontSize
            stepper.target = self
            stepper.action = #selector(fontSizeStepperChanged(_:))

            let label = NSTextField(labelWithString: "\(settings.fontSize)")
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            label.textColor = Theme.textPrimary
            label.tag = 100

            let row = NSStackView(views: [label, stepper])
            row.spacing = 6
            return row
        }

        // Cursor style
        addRow("Cursor") {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            for style in ["block", "bar", "underline"] {
                popup.addItem(withTitle: style.capitalized)
            }
            popup.selectItem(withTitle: settings.cursorStyle.capitalized)
            popup.target = self
            popup.action = #selector(cursorChanged(_:))
            popup.bezelStyle = .roundRect
            return popup
        }

        addSpacer()
        addNote("Changes take effect for new terminals. Restart for full effect.")
    }

    // MARK: - UI Helpers

    private func addSection(_ title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = Theme.textMuted
        stackView.addArrangedSubview(label)
        stackView.setCustomSpacing(12, after: label)
    }

    private func addRow(_ title: String, control: () -> NSView) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = Theme.textSecondary
        label.setFrameSize(NSSize(width: 90, height: 21))

        let row = NSStackView(views: [label, control()])
        row.alignment = .centerY
        row.spacing = 12
        stackView.addArrangedSubview(row)
    }

    private func addSpacer() {
        let spacer = NSView()
        spacer.setFrameSize(NSSize(width: 1, height: 16))
        stackView.addArrangedSubview(spacer)
    }

    private func addNote(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = Theme.textMuted
        stackView.addArrangedSubview(label)
    }

    // MARK: - Actions

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        guard let name = sender.titleOfSelectedItem,
              let theme = ThemeColors.allThemes.first(where: { $0.name == name }) else { return }
        settings.themeName = name
        ThemeManager.shared.apply(theme)

        // Update this window's own background
        layer?.backgroundColor = Theme.base.cgColor
        window?.backgroundColor = Theme.base
    }

    @objc private func tabModeChanged(_ sender: NSPopUpButton) {
        let mode = sender.titleOfSelectedItem == "Sidebar" ? "sidebar" : "tabbar"
        settings.tabMode = mode
        // The container will observe this change
        if let window = NSApp.windows.first(where: { $0.contentView is TerminalContainerView }),
           let container = window.contentView as? TerminalContainerView {
            container.applyTabMode()
        }
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        settings.backgroundOpacity = sender.doubleValue
    }

    @objc private func fontChanged(_ sender: NSTextField) {
        settings.fontFamily = sender.stringValue
    }

    @objc private func fontSizeStepperChanged(_ sender: NSStepper) {
        settings.fontSize = sender.integerValue
        // Update the label next to the stepper
        if let row = sender.superview as? NSStackView,
           let label = row.views.first(where: { $0.tag == 100 }) as? NSTextField {
            label.stringValue = "\(sender.integerValue)"
        }
    }

    @objc private func cursorChanged(_ sender: NSPopUpButton) {
        if let title = sender.titleOfSelectedItem {
            settings.cursorStyle = title.lowercased()
        }
    }
}
