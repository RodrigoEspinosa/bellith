import AppKit

enum SettingsOpenMode: Equatable {
    case builtInWindow(String?)
    case editor(URL)
}

enum SettingsNavigation {
    static func openMode(for settings: BellithSettings, selecting paneID: String? = nil) -> SettingsOpenMode {
        guard !settings.builtInSettingsWindowEnabled,
              let settingsFileURL = settings.settingsFileLocation else {
            return .builtInWindow(paneID)
        }

        return .editor(settingsFileURL)
    }

    @discardableResult
    static func open(
        selecting paneID: String? = nil,
        in container: TerminalContainerView? = nil,
        settings: BellithSettings = .shared,
        preferencesWindowController: PreferencesWindowController = .shared,
        createContainer: (() -> TerminalContainerView?)? = nil
    ) -> Bool {
        switch openMode(for: settings, selecting: paneID) {
        case let .builtInWindow(selectedPaneID):
            preferencesWindowController.showWindow(selecting: selectedPaneID)
            return true

        case let .editor(settingsFileURL):
            let targetContainer = container ?? createContainer?()
            guard let targetContainer else {
                preferencesWindowController.showWindow(selecting: paneID)
                return false
            }
            targetContainer.openFileInEditor(settingsFileURL, titleOverride: settingsFileURL.lastPathComponent)
            return true
        }
    }
}
