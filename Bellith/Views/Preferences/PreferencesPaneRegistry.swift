import AppKit

enum PreferencesPanePlacement {
    case main
    case footer
}

struct PreferencesPanePlugin {
    typealias PaneFactory = () -> NSView

    let id: String
    let title: String
    let iconName: String
    let placement: PreferencesPanePlacement
    let makePane: PaneFactory

    init(
        id: String,
        title: String,
        iconName: String,
        placement: PreferencesPanePlacement = .main,
        makePane: @escaping PaneFactory
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.placement = placement
        self.makePane = makePane
    }
}

protocol PreferencesPaneRefreshable: AnyObject {
    func refreshPreferencesPane()
}

final class PreferencesPaneRegistry {
    static let shared = PreferencesPaneRegistry()

    private var orderedPaneIDs: [String] = []
    private var panesByID: [String: PreferencesPanePlugin] = [:]

    private init() {
        register(PreferencesPanePlugin(id: "appearance", title: "Appearance", iconName: "paintbrush.pointed") {
            AppearancePane()
        })
        register(PreferencesPanePlugin(id: "terminal", title: "Terminal", iconName: "terminal") {
            TerminalPane()
        })
        register(PreferencesPanePlugin(id: "ssh", title: "SSH", iconName: "server.rack") {
            SSHPane()
        })
        register(PreferencesPanePlugin(id: "sidebar", title: "Sidebar", iconName: "sidebar.left") {
            SidebarPane()
        })
        register(PreferencesPanePlugin(id: "keybindings", title: "Keybindings", iconName: "keyboard") {
            KeybindingsPane()
        })
        register(PreferencesPanePlugin(id: "quickterm", title: "Quick Terminal", iconName: "rectangle.bottomhalf.inset.filled") {
            QuickTerminalPane()
        })
        register(PreferencesPanePlugin(id: "about", title: "About", iconName: "info.circle", placement: .footer) {
            AboutPane()
        })
    }

    var allPlugins: [PreferencesPanePlugin] {
        orderedPaneIDs.compactMap { panesByID[$0] }
    }

    var mainPlugins: [PreferencesPanePlugin] {
        allPlugins.filter { $0.placement == .main }
    }

    var footerPlugins: [PreferencesPanePlugin] {
        allPlugins.filter { $0.placement == .footer }
    }

    func plugin(for id: String) -> PreferencesPanePlugin? {
        panesByID[id]
    }

    private func register(_ plugin: PreferencesPanePlugin) {
        guard panesByID[plugin.id] == nil else { return }
        orderedPaneIDs.append(plugin.id)
        panesByID[plugin.id] = plugin
    }
}

extension AboutPane: PreferencesPaneRefreshable {
    func refreshPreferencesPane() { refresh() }
}
