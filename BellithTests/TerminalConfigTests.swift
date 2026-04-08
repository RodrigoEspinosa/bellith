import XCTest
@testable import Bellith

final class TerminalConfigTests: XCTestCase {
    func testWriteConfigFileReturnsPath() {
        let path = TerminalConfig.writeConfigFile()
        XCTAssertNotNil(path, "Config file write should return a path")
    }

    func testWrittenFileContainsExpectedKeys() throws {
        guard let path = TerminalConfig.writeConfigFile() else {
            XCTFail("Config file write returned nil")
            return
        }
        let contents = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(contents.contains("font-family"), "Config should contain font-family")
        XCTAssertTrue(contents.contains("font-size"), "Config should contain font-size")
        XCTAssertTrue(contents.contains("theme"), "Config should contain theme")
        XCTAssertTrue(contents.contains("background-opacity"), "Config should contain background-opacity")
        XCTAssertTrue(contents.contains("cursor-style"), "Config should contain cursor-style")
        XCTAssertTrue(contents.contains("scrollback-limit"), "Config should contain scrollback-limit")
        XCTAssertTrue(contents.contains("link-url = true"), "Config should enable clickable links")
        XCTAssertTrue(contents.contains("keybind = clear"), "Config should clear keybinds")
    }

    func testWrittenFileReflectsCurrentSettings() throws {
        let settings = BellithSettings.shared
        guard let path = TerminalConfig.writeConfigFile() else {
            XCTFail("Config file write returned nil")
            return
        }
        let contents = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(contents.contains("font-family = \(settings.fontFamily)"),
                       "Config should reflect current font family")
        XCTAssertTrue(contents.contains("font-size = \(settings.fontSize)"),
                       "Config should reflect current font size")
    }
}
