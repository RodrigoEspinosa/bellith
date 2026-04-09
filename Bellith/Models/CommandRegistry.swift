import AppKit

struct CommandPlugin {
    typealias Handler = (TerminalContainerView, String) -> Bool

    let id: String
    let title: String
    let description: String
    let iconName: String
    let shortcutID: String?
    let aliases: [String]
    let perform: Handler

    init(
        id: String,
        title: String,
        description: String,
        iconName: String,
        shortcutID: String? = nil,
        aliases: [String] = [],
        perform: @escaping Handler
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.iconName = iconName
        self.shortcutID = shortcutID
        self.aliases = aliases
        self.perform = perform
    }

    fileprivate func matches(_ normalizedCommand: String) -> Bool {
        if CommandRegistry.normalize(id) == normalizedCommand { return true }
        if CommandRegistry.normalize(title) == normalizedCommand { return true }
        return aliases.contains { CommandRegistry.normalize($0) == normalizedCommand }
    }
}

final class CommandRegistry {
    static let shared = CommandRegistry()

    private var orderedCommandIDs: [String] = []
    private var commandsByID: [String: CommandPlugin] = [:]
    private let smartPanelRegistry: SmartPanelRegistry
    private let sshProfileStore: SSHProfileStore
    private let preferencesWindowController: PreferencesWindowController

    init(
        smartPanelRegistry: SmartPanelRegistry = .shared,
        sshProfileStore: SSHProfileStore = .shared,
        preferencesWindowController: PreferencesWindowController = .shared
    ) {
        self.smartPanelRegistry = smartPanelRegistry
        self.sshProfileStore = sshProfileStore
        self.preferencesWindowController = preferencesWindowController
        registerBuiltIns()
    }

    var allCommands: [CommandPlugin] {
        orderedCommandIDs.compactMap { commandsByID[$0] } + smartPanelCommands + sshProfileCommands
    }

    func command(matching text: String) -> CommandPlugin? {
        let normalized = Self.normalize(text)
        return allCommands.first { $0.matches(normalized) }
    }

    static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private var smartPanelCommands: [CommandPlugin] {
        smartPanelRegistry.allPlugins.map { plugin in
            CommandPlugin(
                id: plugin.id,
                title: plugin.title,
                description: plugin.commandDescription,
                iconName: plugin.iconName,
                aliases: plugin.commandAliases
            ) { container, _ in
                container.openOrSwitchToTool(plugin.id)
                return true
            }
        }
    }

    private var sshProfileCommands: [CommandPlugin] {
        sshProfileStore.profiles.map { profile in
            CommandPlugin(
                id: "sshProfile-\(profile.id.uuidString)",
                title: "Connect \(profile.displayName)",
                description: "Open \(profile.destination) in a new SSH tab",
                iconName: "point.3.connected.trianglepath.dotted",
                aliases: [profile.host, profile.destination, profile.displayName]
            ) { container, _ in
                container.connectSSHProfile(id: profile.id)
                return true
            }
        }
    }

    private func register(_ command: CommandPlugin) {
        guard commandsByID[command.id] == nil else { return }
        orderedCommandIDs.append(command.id)
        commandsByID[command.id] = command
    }

    private func registerBuiltIns() {
        register(CommandPlugin(
            id: "connectHost",
            title: "Connect Host",
            description: "Open an SSH profile or manage saved hosts",
            iconName: "point.3.connected.trianglepath.dotted",
            aliases: ["ssh", "connect ssh", "host"]
        ) { container, _ in
            let profiles = self.sshProfileStore.profiles
            if profiles.count == 1, let profile = profiles.first {
                container.connectSSHProfile(id: profile.id)
            } else {
                self.preferencesWindowController.showWindow(selecting: "ssh")
            }
            return true
        })

        register(CommandPlugin(
            id: "newTab",
            title: "New Tab",
            description: "Open a new terminal tab",
            iconName: "plus.square",
            shortcutID: "newTab",
            aliases: ["tab", "new"]
        ) { container, _ in
            container.createTab()
            return true
        })

        register(CommandPlugin(
            id: "closeTab",
            title: "Close Tab",
            description: "Close the current tab",
            iconName: "xmark.square",
            shortcutID: "closeTab",
            aliases: ["close"]
        ) { container, _ in
            container.closeCurrentTab()
            return true
        })

        register(CommandPlugin(
            id: "reopenTab",
            title: "Reopen Closed Tab",
            description: "Restore last closed tab",
            iconName: "arrow.uturn.left",
            shortcutID: "reopenTab",
            aliases: ["reopentab", "reopen"]
        ) { container, _ in
            container.reopenClosedTab()
            return true
        })

        register(CommandPlugin(
            id: "splitRight",
            title: "Split Right",
            description: "Split pane to the right",
            iconName: "rectangle.split.1x2",
            shortcutID: "splitRight",
            aliases: ["split", "split right", "vsplit"]
        ) { container, _ in
            container.splitPane(direction: .vertical)
            return true
        })

        register(CommandPlugin(
            id: "splitDown",
            title: "Split Down",
            description: "Split pane downward",
            iconName: "rectangle.split.2x1",
            shortcutID: "splitDown",
            aliases: ["split down", "hsplit"]
        ) { container, _ in
            container.splitPane(direction: .horizontal)
            return true
        })

        register(CommandPlugin(
            id: "closePane",
            title: "Close Pane",
            description: "Close the current pane",
            iconName: "xmark.rectangle",
            shortcutID: "closePane",
            aliases: ["close pane", "closepane"]
        ) { container, _ in
            container.closePane()
            return true
        })

        register(CommandPlugin(
            id: "zoomPane",
            title: "Zoom Pane",
            description: "Toggle pane zoom",
            iconName: "arrow.up.left.and.arrow.down.right",
            shortcutID: "zoomPane",
            aliases: ["zoom", "maximize"]
        ) { container, _ in
            container.togglePaneZoom()
            return true
        })

        register(CommandPlugin(
            id: "equalizePanes",
            title: "Equalize Panes",
            description: "Reset all pane sizes",
            iconName: "equal.square",
            shortcutID: "equalizePanes",
            aliases: ["equalize", "equal"]
        ) { container, _ in
            container.equalizeAllPanes()
            return true
        })

        register(CommandPlugin(
            id: "navLeft",
            title: "Focus Left Pane",
            description: "Move focus left",
            iconName: "arrow.left.square",
            shortcutID: "navLeft",
            aliases: ["focus left"]
        ) { container, _ in
            container.focusPane(.left)
            return true
        })

        register(CommandPlugin(
            id: "navRight",
            title: "Focus Right Pane",
            description: "Move focus right",
            iconName: "arrow.right.square",
            shortcutID: "navRight",
            aliases: ["focus right"]
        ) { container, _ in
            container.focusPane(.right)
            return true
        })

        register(CommandPlugin(
            id: "navUp",
            title: "Focus Up Pane",
            description: "Move focus up",
            iconName: "arrow.up.square",
            shortcutID: "navUp",
            aliases: ["focus up"]
        ) { container, _ in
            container.focusPane(.up)
            return true
        })

        register(CommandPlugin(
            id: "navDown",
            title: "Focus Down Pane",
            description: "Move focus down",
            iconName: "arrow.down.square",
            shortcutID: "navDown",
            aliases: ["focus down"]
        ) { container, _ in
            container.focusPane(.down)
            return true
        })

        register(CommandPlugin(
            id: "toggleSidebar",
            title: "Toggle Sidebar",
            description: "Show or hide the sidebar",
            iconName: "sidebar.left",
            shortcutID: "toggleSidebar",
            aliases: ["sidebar"]
        ) { container, _ in
            container.toggleSidebarVisibility()
            return true
        })

        register(CommandPlugin(
            id: "toggleTabMode",
            title: "Toggle Tab Mode",
            description: "Switch between sidebar and tab bar",
            iconName: "rectangle.3.group",
            aliases: ["tab bar", "tabbar"]
        ) { container, _ in
            container.toggleTabMode()
            return true
        })

        register(CommandPlugin(
            id: "toggleBroadcast",
            title: "Broadcast Mode",
            description: "Send input to all panes",
            iconName: "antenna.radiowaves.left.and.right",
            shortcutID: "broadcastInput",
            aliases: ["broadcast"]
        ) { container, _ in
            container.toggleBroadcastMode()
            return true
        })

        register(CommandPlugin(
            id: "find",
            title: "Find",
            description: "Search in terminal",
            iconName: "magnifyingglass",
            shortcutID: "search",
            aliases: ["search"]
        ) { container, _ in
            container.showSearch()
            return true
        })

        register(CommandPlugin(
            id: "sshProfiles",
            title: "SSH Profiles",
            description: "Open SSH profile settings",
            iconName: "server.rack",
            aliases: ["ssh settings", "hosts", "ssh profiles"]
        ) { _, _ in
            PreferencesWindowController.shared.showWindow(selecting: "ssh")
            return true
        })

        register(CommandPlugin(
            id: "preferences",
            title: "Settings",
            description: "Open preferences window",
            iconName: "gear",
            aliases: ["settings", "preferences"]
        ) { _, _ in
            PreferencesWindowController.shared.showWindow()
            return true
        })

        register(CommandPlugin(
            id: "reloadConfig",
            title: "Reload Config",
            description: "Reload terminal configuration",
            iconName: "arrow.clockwise",
            shortcutID: "reloadConfig",
            aliases: ["reload", "reload config"]
        ) { container, _ in
            container.reloadConfig()
            return true
        })

        register(CommandPlugin(
            id: "increaseFontSize",
            title: "Increase Font Size",
            description: "Make text larger",
            iconName: "textformat.size.larger",
            shortcutID: "fontSizeUp",
            aliases: ["font+", "bigger"]
        ) { container, _ in
            container.adjustFontSizePublic(delta: 1)
            return true
        })

        register(CommandPlugin(
            id: "decreaseFontSize",
            title: "Decrease Font Size",
            description: "Make text smaller",
            iconName: "textformat.size.smaller",
            shortcutID: "fontSizeDown",
            aliases: ["font-", "smaller"]
        ) { container, _ in
            container.adjustFontSizePublic(delta: -1)
            return true
        })

        register(CommandPlugin(
            id: "resetFontSize",
            title: "Reset Font Size",
            description: "Reset to default size",
            iconName: "textformat.size",
            shortcutID: "fontSizeReset"
        ) { container, _ in
            container.resetFontSizePublic()
            return true
        })

        register(CommandPlugin(
            id: "clearBuffer",
            title: "Clear Buffer",
            description: "Clear terminal output",
            iconName: "trash",
            shortcutID: "clearBuffer",
            aliases: ["clearbuffer", "clear"]
        ) { container, _ in
            container.clearBuffer()
            return true
        })

        register(CommandPlugin(
            id: "fullscreen",
            title: "Toggle Fullscreen",
            description: "Enter or exit fullscreen",
            iconName: "arrow.up.backward.and.arrow.down.forward",
            shortcutID: "toggleFullscreen"
        ) { container, _ in
            container.toggleFullscreenMode()
            return true
        })

        register(CommandPlugin(
            id: "copySelection",
            title: "Copy",
            description: "Copy selected text",
            iconName: "doc.on.doc",
            shortcutID: "copy",
            aliases: ["copy", "copyselection"]
        ) { container, _ in
            container.copySelection()
            return true
        })

        register(CommandPlugin(
            id: "pasteClipboard",
            title: "Paste",
            description: "Paste from clipboard",
            iconName: "doc.on.clipboard",
            shortcutID: "paste",
            aliases: ["paste", "pasteclipboard"]
        ) { container, _ in
            container.pasteClipboard()
            return true
        })

        register(CommandPlugin(
            id: "newWindow",
            title: "New Window",
            description: "Open a new window",
            iconName: "macwindow.badge.plus",
            shortcutID: "newWindow",
            aliases: ["new window", "newwindow"]
        ) { container, _ in
            container.openNewWindow()
            return true
        })

        register(CommandPlugin(
            id: "selectAll",
            title: "Select All",
            description: "Select all text",
            iconName: "selection.pin.in.out",
            shortcutID: "selectAll",
            aliases: ["select all", "selectall"]
        ) { container, _ in
            container.selectAllText()
            return true
        })

        register(CommandPlugin(
            id: "ghOpenInBrowser",
            title: "GitHub: Open in Browser",
            description: "Open current repo on GitHub",
            iconName: "safari",
            aliases: ["github open", "open repo", "gh browse"]
        ) { container, _ in
            let cwd = container.activeCwd
            guard let gh = GitHubService.ghPath() else { return false }
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gh)
                process.arguments = ["browse"]
                process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
            }
            return true
        })
    }
}
