import AppKit
import os
import Sparkle

/// Owns Sparkle's `SPUStandardUpdaterController` so AppDelegate doesn't have to
/// import Sparkle directly and so the controller has a single, app-long owner.
///
/// `startingUpdater: true` triggers the first-launch "Would you like to enable
/// auto-update?" prompt Sparkle's default UI expects. All feed URL, public key,
/// and scheduled-check interval configuration is read from Info.plist.
final class UpdaterController {
    static let placeholderPublicEDKey = "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"

    private let controller: SPUStandardUpdaterController?

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        guard Self.isUsableConfiguration(infoDictionary: infoDictionary) else {
            Logger.app.info("Sparkle updater disabled because its Info.plist configuration is incomplete")
            controller = nil
            return
        }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var isAvailable: Bool { controller != nil }

    /// Target for the "Check for Updates…" menu item. Sparkle's controller
    /// responds to `checkForUpdates(_:)` directly.
    var menuTarget: AnyObject? { controller }
    var menuAction: Selector { #selector(SPUStandardUpdaterController.checkForUpdates(_:)) }

    static func isUsableConfiguration(infoDictionary: [String: Any]) -> Bool {
        guard
            let feedURLString = infoDictionary["SUFeedURL"] as? String,
            let feedURL = URL(string: feedURLString),
            let scheme = feedURL.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else {
            return false
        }

        guard let publicKey = infoDictionary["SUPublicEDKey"] as? String else {
            return false
        }

        let trimmedPublicKey = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedPublicKey.isEmpty && trimmedPublicKey != placeholderPublicEDKey
    }
}
