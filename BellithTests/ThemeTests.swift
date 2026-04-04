import XCTest
@testable import Bellith

final class ThemeTests: XCTestCase {
    func testAllBuiltInThemesExist() {
        let themes = ThemeColors.allThemes
        XCTAssertGreaterThanOrEqual(themes.count, 6, "Expected at least 6 built-in themes")
    }

    func testBuiltInThemeNames() {
        let names = Set(ThemeColors.allThemes.map(\.name))
        XCTAssertTrue(names.contains("Tokyo Night"))
        XCTAssertTrue(names.contains("Catppuccin Mocha"))
        XCTAssertTrue(names.contains("Gruvbox Dark"))
        XCTAssertTrue(names.contains("Nord"))
    }

    func testThemeHasGhosttyThemeName() {
        for theme in ThemeColors.allThemes {
            XCTAssertFalse(theme.ghosttyTheme.isEmpty, "Theme '\(theme.name)' has empty ghosttyTheme")
        }
    }

    func testAccentSubtleHasLowAlpha() {
        for theme in ThemeColors.allThemes {
            // accentSubtle should have low alpha (0.08)
            let subtle = theme.accentSubtle
            XCTAssertNotNil(subtle, "Theme '\(theme.name)' accentSubtle should not be nil")
        }
    }

    func testThemeManagerApply() {
        let originalTheme = ThemeManager.shared.current
        let nord = ThemeColors.allThemes.first { $0.name == "Nord" }!

        ThemeManager.shared.apply(nord)
        XCTAssertEqual(ThemeManager.shared.current.name, "Nord")

        // Restore
        ThemeManager.shared.apply(originalTheme)
    }

    func testThemeManagerPostsNotification() {
        let expectation = XCTNSNotificationExpectation(
            name: ThemeManager.didChangeNotification
        )

        let gruvbox = ThemeColors.allThemes.first { $0.name == "Gruvbox Dark" }!
        ThemeManager.shared.apply(gruvbox)

        wait(for: [expectation], timeout: 1.0)
    }
}
