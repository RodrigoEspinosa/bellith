import AppKit

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(handleToggleStatusBar) {
            menuItem.state = dependencies.settings.showStatusBar ? .on : .off
        }
        let terminalOnlyActions: Set<Selector?> = [
            #selector(handleJumpToPreviousPrompt),
            #selector(handleJumpToNextPrompt),
            #selector(handleSelectCommandOutput),
            #selector(handleCopyCommandOutput),
        ]
        if terminalOnlyActions.contains(menuItem.action) {
            // Leave ⌘↑ and friends to text fields when Studio has focus.
            return !isCreativeWorkspaceActive
        }
        return true
    }
}
