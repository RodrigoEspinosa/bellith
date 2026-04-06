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

    func testDefaultThemeName() {
        XCTAssertEqual(settings.themeName, "Tokyo Night")
    }

    func testDefaultTabMode() {
        XCTAssertEqual(settings.tabMode, "sidebar")
    }

    func testDefaultShellIsEmpty() {
        XCTAssertEqual(settings.shell, "")
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

    func testDefaultWindowPadding() {
        XCTAssertEqual(settings.windowPaddingX, 10)
        XCTAssertEqual(settings.windowPaddingY, 38)
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

    func testThemeNameRoundtrip() {
        settings.themeName = "Catppuccin Mocha"
        XCTAssertEqual(settings.themeName, "Catppuccin Mocha")
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

    func testResolvedThemeMatchesName() {
        settings.themeName = "Nord"
        let theme = settings.resolvedTheme
        XCTAssertEqual(theme.name, "Nord")
    }

    func testResolvedThemeFallsBackToDefault() {
        settings.themeName = "NonExistentTheme"
        let theme = settings.resolvedTheme
        // Should fallback to first theme (Tokyo Night)
        XCTAssertFalse(theme.name.isEmpty)
    }
}
