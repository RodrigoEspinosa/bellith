import Foundation

struct BellithDependencies {
    let settings: BellithSettings
    let themeManager: ThemeManager
    let commandRegistry: CommandRegistry
    let smartPanelRegistry: SmartPanelRegistry
    let preferencesWindowController: PreferencesWindowController

    static let live = BellithDependencies(
        settings: .shared,
        themeManager: .shared,
        commandRegistry: .shared,
        smartPanelRegistry: .shared,
        preferencesWindowController: .shared
    )
}
