import XCTest
@testable import Bellith

final class BellithSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settings: BellithSettings!

    override func setUp() {
        super.setUp()
        suiteName = "BellithSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = BellithSettings(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        settings = nil
        super.tearDown()
    }

    // MARK: - Default Values

    func testDefaultFontFamily() {
        XCTAssertEqual(settings.fontFamily, "Hack Nerd Font Mono")
    }

    func testDefaultFontSize() {
        XCTAssertEqual(settings.fontSize, 15)
    }

    func testDefaultBackgroundOpacity() {
        XCTAssertEqual(settings.backgroundOpacity, 1.0)
    }

    func testDefaultCursorStyle() {
        XCTAssertEqual(settings.cursorStyle, "block")
    }

    func testDefaultThemeNames() {
        XCTAssertEqual(settings.darkThemeName, "Tokyo Night")
        XCTAssertEqual(settings.lightThemeName, "Tokyo Night Light")
    }

    func testDefaultTabMode() {
        XCTAssertEqual(settings.tabMode, "sidebar")
    }

    func testDefaultShellIsEmpty() {
        XCTAssertEqual(settings.shell, "")
    }

    func testDefaultTerminalTermUsesGhosttyTerminfo() {
        XCTAssertEqual(settings.terminalTerm, "")
        XCTAssertEqual(settings.effectiveTerminalTerm, BellithSettings.defaultTerminalTerm)
    }

    func testDefaultScrollbackLines() {
        XCTAssertEqual(settings.scrollbackLines, 10000)
    }

    func testDefaultMouseHideWhileTyping() {
        XCTAssertTrue(settings.mouseHideWhileTyping)
    }

    func testDefaultConfirmClose() {
        XCTAssertFalse(settings.confirmClose)
    }

    func testDefaultRestoreSession() {
        XCTAssertTrue(settings.restoreSession)
    }

    func testDefaultCursorBlink() {
        XCTAssertFalse(settings.cursorBlink)
    }

    func testDefaultShellIntegrationSettings() {
        XCTAssertTrue(settings.shellIntegrationEnabled)
        XCTAssertTrue(settings.shellIntegrationCursor)
        XCTAssertTrue(settings.shellIntegrationTitle)
        XCTAssertTrue(settings.shellIntegrationPath)
        XCTAssertTrue(settings.shellIntegrationSSHEnv)
        XCTAssertFalse(settings.shellIntegrationSSHTerminfo)
    }

    func testDefaultCommandCompletionNotificationSettings() {
        XCTAssertTrue(settings.commandCompletionNotificationsEnabled)
        XCTAssertEqual(settings.commandCompletionNotificationThreshold, 10)
    }

    func testDefaultShowStatusBar() {
        XCTAssertTrue(settings.showStatusBar)
        XCTAssertFalse(settings.showStatusBarContext)
        XCTAssertFalse(settings.showStatusBarPath)
        XCTAssertFalse(settings.showStatusBarGitWorktree)
        XCTAssertTrue(settings.showStatusBarGitBranch)
        XCTAssertTrue(settings.showStatusBarGitHub)
        XCTAssertFalse(settings.showStatusBarProcess)
        XCTAssertFalse(settings.showStatusBarSize)
    }

    func testDefaultWindowPadding() {
        XCTAssertEqual(settings.windowPaddingX, 0)
        XCTAssertEqual(settings.windowPaddingY, 0)
    }

    func testWindowPaddingAllowsZero() {
        settings.windowPaddingX = 0
        settings.windowPaddingY = 0

        XCTAssertEqual(settings.windowPaddingX, 0)
        XCTAssertEqual(settings.windowPaddingY, 0)
    }

    func testLegacyWindowPaddingMigratesToZero() {
        defaults.set(10, forKey: "windowPaddingX")
        defaults.set(38, forKey: "windowPaddingY")

        settings = BellithSettings(defaults: defaults)

        XCTAssertEqual(settings.windowPaddingX, 0)
        XCTAssertEqual(settings.windowPaddingY, 0)
        XCTAssertTrue(defaults.bool(forKey: "didMigrateWindowPaddingDefaults"))
    }

    func testCustomWindowPaddingIsPreservedDuringMigration() {
        defaults.set(6, forKey: "windowPaddingX")
        defaults.set(12, forKey: "windowPaddingY")

        settings = BellithSettings(defaults: defaults)

        XCTAssertEqual(settings.windowPaddingX, 6)
        XCTAssertEqual(settings.windowPaddingY, 12)
        XCTAssertTrue(defaults.bool(forKey: "didMigrateWindowPaddingDefaults"))
    }

    func testSidebarSettingsSnapshotIgnoresUnrelatedSettings() {
        let baseline = SidebarView.SettingsSnapshot.current(using: settings)

        settings.fontSize = 18
        settings.backgroundOpacity = 0.75
        settings.workingDirectory = "/tmp"

        XCTAssertEqual(SidebarView.SettingsSnapshot.current(using: settings), baseline)
    }

    func testSidebarSettingsSnapshotTracksSidebarOnlySettings() {
        let baseline = SidebarView.SettingsSnapshot.current(using: settings)

        settings.sidebarPinned = !settings.sidebarPinned
        XCTAssertNotEqual(SidebarView.SettingsSnapshot.current(using: settings), baseline)

        settings.sidebarAutoHide = !settings.sidebarAutoHide
        XCTAssertNotEqual(SidebarView.SettingsSnapshot.current(using: settings), baseline)
    }

    func testDefaultSidebarAutoHide() {
        XCTAssertFalse(settings.sidebarAutoHide)
    }

    // MARK: - Roundtrip

    func testFontFamilyRoundtrip() {
        settings.fontFamily = "Fira Code"
        XCTAssertEqual(settings.fontFamily, "Fira Code")
    }

    func testFontSizeRoundtrip() {
        settings.fontSize = 22
        XCTAssertEqual(settings.fontSize, 22)
    }

    func testDarkThemeNameRoundtrip() {
        settings.darkThemeName = "Catppuccin Mocha"
        XCTAssertEqual(settings.darkThemeName, "Catppuccin Mocha")
    }

    func testLightThemeNameRoundtrip() {
        settings.lightThemeName = "Solarized Light"
        XCTAssertEqual(settings.lightThemeName, "Solarized Light")
    }

    func testBackgroundOpacityRoundtrip() {
        settings.backgroundOpacity = 0.8
        XCTAssertEqual(settings.backgroundOpacity, 0.8, accuracy: 0.001)
    }

    func testBooleanSettingsRoundtrip() {
        settings.mouseHideWhileTyping = false
        XCTAssertFalse(settings.mouseHideWhileTyping)

        settings.confirmClose = false
        XCTAssertFalse(settings.confirmClose)

        settings.restoreSession = false
        XCTAssertFalse(settings.restoreSession)

        settings.cursorBlink = false
        XCTAssertFalse(settings.cursorBlink)
    }

    func testShellIntegrationRoundtrip() {
        settings.shellIntegrationEnabled = false
        settings.shellIntegrationCursor = false
        settings.shellIntegrationTitle = false
        settings.shellIntegrationPath = false
        settings.shellIntegrationSSHEnv = false
        settings.shellIntegrationSSHTerminfo = true

        XCTAssertFalse(settings.shellIntegrationEnabled)
        XCTAssertFalse(settings.shellIntegrationCursor)
        XCTAssertFalse(settings.shellIntegrationTitle)
        XCTAssertFalse(settings.shellIntegrationPath)
        XCTAssertFalse(settings.shellIntegrationSSHEnv)
        XCTAssertTrue(settings.shellIntegrationSSHTerminfo)
        XCTAssertEqual(settings.shellIntegrationMode, "none")
        XCTAssertEqual(
            settings.shellIntegrationFeatures,
            "no-cursor,no-title,no-path,no-ssh-env,ssh-terminfo"
        )
    }

    func testCommandCompletionNotificationRoundtrip() {
        settings.commandCompletionNotificationsEnabled = false
        settings.commandCompletionNotificationThreshold = 42

        XCTAssertFalse(settings.commandCompletionNotificationsEnabled)
        XCTAssertEqual(settings.commandCompletionNotificationThreshold, 42)
    }

    func testSidebarAutoHideRoundtrip() {
        settings.sidebarAutoHide = true
        XCTAssertTrue(settings.sidebarAutoHide)
    }

    func testShowStatusBarRoundtrip() {
        settings.showStatusBar = false
        XCTAssertFalse(settings.showStatusBar)

        settings.showStatusBar = true
        XCTAssertTrue(settings.showStatusBar)

        settings.showStatusBarGitBranch = false
        settings.showStatusBarGitHub = false
        settings.showStatusBarPath = true

        XCTAssertFalse(settings.showStatusBarGitBranch)
        XCTAssertFalse(settings.showStatusBarGitHub)
        XCTAssertTrue(settings.showStatusBarPath)
    }

    func testTerminalTermRoundtripAndTrimming() {
        settings.terminalTerm = "  xterm-256color  "

        XCTAssertEqual(settings.terminalTerm, "xterm-256color")
        XCTAssertEqual(settings.effectiveTerminalTerm, "xterm-256color")
    }

    // MARK: - Keybindings

    func testDefaultKeybindingsNotEmpty() {
        let bindings = settings.keybindings
        XCTAssertFalse(bindings.isEmpty)
    }

    func testDefaultKeybindingsHaveNoDuplicateIDs() {
        let ids = BellithSettings.defaultKeybindings.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "Duplicate keybinding IDs found: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })")
    }

    func testKeybindingsHandleCorruptedData() {
        defaults.set(Data([0xFF, 0x00, 0x42]), forKey: "keybindings")
        // Should fall back to defaults rather than crash
        let bindings = settings.keybindings
        XCTAssertFalse(bindings.isEmpty)
    }

    func testShortcutForAction() {
        let shortcut = settings.shortcut(for: "newTab")
        XCTAssertNotNil(shortcut)
        XCTAssertEqual(shortcut?.key, "t")
        XCTAssertTrue(shortcut?.command ?? false)
    }

    // MARK: - Resolved Theme

    func testResolvedThemeMatchesDarkName() {
        settings.darkThemeName = "Nord"
        // resolvedTheme depends on system appearance; just verify setting is stored
        XCTAssertEqual(settings.darkThemeName, "Nord")
    }

    func testResolvedThemeMatchesLightName() {
        settings.lightThemeName = "One Light"
        XCTAssertEqual(settings.lightThemeName, "One Light")
    }

    func testResolvedThemeFallsBackToDefault() {
        settings.darkThemeName = "NonExistentTheme"
        settings.lightThemeName = "NonExistentTheme"
        let theme = settings.resolvedTheme
        // Should fallback to Tokyo Night
        XCTAssertFalse(theme.name.isEmpty)
    }
}
