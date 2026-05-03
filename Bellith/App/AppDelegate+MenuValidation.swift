import AppKit

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(handleToggleStatusBar) {
            menuItem.state = dependencies.settings.showStatusBar ? .on : .off
        }
        return true
    }
}
