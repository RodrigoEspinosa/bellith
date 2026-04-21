import AppKit
import Sparkle

/// Owns Sparkle's `SPUStandardUpdaterController` so AppDelegate doesn't have to
/// import Sparkle directly and so the controller has a single, app-long owner.
///
/// `startingUpdater: true` triggers the first-launch "Would you like to enable
/// auto-update?" prompt Sparkle's default UI expects. All feed URL, public key,
/// and scheduled-check interval configuration is read from Info.plist.
final class UpdaterController {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    /// Target for the "Check for Updates…" menu item. Sparkle's controller
    /// responds to `checkForUpdates(_:)` directly.
    var menuTarget: AnyObject { controller }
    var menuAction: Selector { #selector(SPUStandardUpdaterController.checkForUpdates(_:)) }
}
