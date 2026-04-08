import XCTest
@testable import Bellith

final class TerminalConfigTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settings: BellithSettings!

    override func setUp() {
        super.setUp()
        suiteName = "TerminalConfigTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = BellithSettings(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        settings = nil
        super.tearDown()
    }

    func testWriteConfigFileReturnsPath() {
        let path = TerminalConfig.writeConfigFile(settings: settings)
        XCTAssertNotNil(path, "Config file write should return a path")
    }

    func testWrittenFileContainsExpectedKeys() throws {
        guard let path = TerminalConfig.writeConfigFile(settings: settings) else {
            XCTFail("Config file write returned nil")
            return
        }
        let contents = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(contents.contains("font-family"), "Config should contain font-family")
        XCTAssertTrue(contents.contains("font-size"), "Config should contain font-size")
        XCTAssertTrue(contents.contains("theme"), "Config should contain theme")
        XCTAssertTrue(contents.contains("term = xterm-ghostty"), "Config should set Ghostty's default TERM explicitly")
        XCTAssertTrue(contents.contains("background-opacity"), "Config should contain background-opacity")
        XCTAssertTrue(contents.contains("cursor-style"), "Config should contain cursor-style")
        XCTAssertTrue(contents.contains("scrollback-limit"), "Config should contain scrollback-limit")
        XCTAssertTrue(contents.contains("shell-integration = detect"), "Config should enable shell integration by default")
        XCTAssertTrue(contents.contains("shell-integration-features"), "Config should declare shell integration features")
        XCTAssertTrue(contents.contains("link-url = true"), "Config should enable clickable links")
        XCTAssertTrue(contents.contains("keybind = clear"), "Config should clear keybinds")
    }

    func testWrittenFileReflectsCurrentSettings() throws {
        settings.fontFamily = "JetBrains Mono"
        settings.fontSize = 18
        settings.terminalTerm = "xterm-256color"
        settings.shellIntegrationCursor = false
        settings.shellIntegrationSSHTerminfo = true

        guard let path = TerminalConfig.writeConfigFile(settings: settings) else {
            XCTFail("Config file write returned nil")
            return
        }
        let contents = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(contents.contains("font-family = \(settings.fontFamily)"),
                       "Config should reflect current font family")
        XCTAssertTrue(contents.contains("font-size = \(settings.fontSize)"),
                       "Config should reflect current font size")
        XCTAssertTrue(contents.contains("term = xterm-256color"),
                      "Config should reflect the TERM override")
        XCTAssertTrue(
            contents.contains("shell-integration-features = no-cursor,title,path,ssh-env,ssh-terminfo"),
            "Config should reflect shell integration feature toggles"
        )
    }

    func testDisabledShellIntegrationWritesNone() throws {
        settings.shellIntegrationEnabled = false

        guard let path = TerminalConfig.writeConfigFile(settings: settings) else {
            XCTFail("Config file write returned nil")
            return
        }
        let contents = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(contents.contains("shell-integration = none"))
    }
}
