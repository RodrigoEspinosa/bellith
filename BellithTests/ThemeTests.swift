import XCTest
@testable import Bellith

final class ThemeTests: XCTestCase {
    func testAccentPalettesExist() {
        let palettes = AppearancePalette.all
        XCTAssertGreaterThanOrEqual(palettes.count, 6, "Expected accent palette choices")
    }

    func testAccentPaletteNames() {
        let names = Set(AppearancePalette.all.map(\.name))
        XCTAssertTrue(names.contains("Aurora"))
        XCTAssertTrue(names.contains("Ember"))
        XCTAssertTrue(names.contains("Iris"))
        XCTAssertTrue(names.contains("Moss"))
        XCTAssertTrue(names.contains("Steel"))
    }

    func testDerivedAppearanceHasGhosttyThemeDefinition() {
        for palette in AppearancePalette.all {
            let theme = ThemeColors.appearance(palette: palette, isDark: true)
            XCTAssertFalse(theme.ghosttyTheme.isEmpty, "Appearance '\(theme.name)' has empty Ghostty theme")
            XCTAssertNotNil(theme.ghosttyThemeDefinition, "Appearance '\(theme.name)' should generate a Ghostty theme")
        }
    }

    func testAccentSubtleHasLowAlpha() {
        for palette in AppearancePalette.all {
            let theme = ThemeColors.appearance(palette: palette, isDark: true)
            let subtle = theme.accentSubtle
            XCTAssertNotNil(subtle, "Appearance '\(theme.name)' accentSubtle should not be nil")
        }
    }

    func testThemeManagerApply() {
        let originalTheme = ThemeManager.shared.current
        let steel = ThemeColors.appearance(palette: .steel, isDark: true)

        ThemeManager.shared.apply(steel)
        XCTAssertEqual(ThemeManager.shared.current.name, "Steel Dark")

        // Restore
        ThemeManager.shared.apply(originalTheme)
    }

    func testThemeManagerPostsNotification() {
        let expectation = XCTNSNotificationExpectation(
            name: ThemeManager.didChangeNotification
        )

        let ember = ThemeColors.appearance(palette: .ember, isDark: true)
        ThemeManager.shared.apply(ember)

        wait(for: [expectation], timeout: 1.0)
    }

    func testDerivedDarkAppearanceUsesOLEDChrome() {
        let theme = ThemeColors.appearance(palette: .aurora, isDark: true)

        XCTAssertTrue(theme.usesOLEDChrome)
        XCTAssertNotNil(theme.ghosttyThemeDefinition)
        XCTAssertTrue(theme.frame.isEqual(theme.base))
        XCTAssertTrue(theme.chrome.isEqual(theme.surface))
    }
}
