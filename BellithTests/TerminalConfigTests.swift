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
        let path = try? TerminalConfig.writeConfigFile(settings: settings)
        XCTAssertNotNil(path, "Config file write should return a path")
        XCTAssertTrue(path?.hasSuffix("/generated.conf") ?? false, "Generated config should use the runtime generated file name")
    }

    func testWrittenFileContainsExpectedKeys() throws {
        let path = try TerminalConfig.writeConfigFile(settings: settings)
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
        XCTAssertTrue(contents.contains("window-padding-x = 4"), "Config should write the expected horizontal padding")
        XCTAssertTrue(contents.contains("window-padding-y = 8,0"), "Config should write the expected top-heavy vertical padding")
        XCTAssertFalse(contents.contains("window-padding-y = 38,2"), "Config should not include the old typo")
    }

    func testWrittenFileReflectsCurrentSettings() throws {
        settings.fontFamily = "JetBrains Mono"
        settings.fontSize = 18
        settings.terminalTerm = "xterm-256color"
        settings.shellIntegrationCursor = false
        settings.shellIntegrationSSHTerminfo = true

        let path = try TerminalConfig.writeConfigFile(settings: settings)
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

    func testVerticalPaddingKeepsMinimumTopInset() throws {
        settings.windowPaddingY = 2

        let path = try TerminalConfig.writeConfigFile(settings: settings)
        let contents = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(contents.contains("window-padding-y = 8,2"))
    }

    func testVerticalPaddingPreservesLargerSymmetricInset() throws {
        settings.windowPaddingY = 12

        let path = try TerminalConfig.writeConfigFile(settings: settings)
        let contents = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(contents.contains("window-padding-y = 12,12"))
    }

    func testHorizontalPaddingKeepsMinimumInset() throws {
        settings.windowPaddingX = 0

        let path = try TerminalConfig.writeConfigFile(settings: settings)
        let contents = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(contents.contains("window-padding-x = 4"))
    }

    func testHorizontalPaddingPreservesLargerInset() throws {
        settings.windowPaddingX = 9

        let path = try TerminalConfig.writeConfigFile(settings: settings)
        let contents = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(contents.contains("window-padding-x = 9"))
    }

    func testDisabledShellIntegrationWritesNone() throws {
        settings.shellIntegrationEnabled = false

        let path = try TerminalConfig.writeConfigFile(settings: settings)
        let contents = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(contents.contains("shell-integration = none"))
    }

    func testWriteConfigFileThrowsForInvalidDirectory() throws {
        let invalidDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalConfigTests-\(UUID().uuidString).txt")
        try "not a directory".write(to: invalidDirectory, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: invalidDirectory) }

        XCTAssertThrowsError(try TerminalConfig.writeConfigFile(
            settings: settings,
            configurationDirectory: invalidDirectory
        )) { error in
            guard let terminalError = error as? TerminalConfigError else {
                return XCTFail("Expected TerminalConfigError, got \(error)")
            }
            guard case .failedToCreateConfigDirectory(let url, _) = terminalError else {
                return XCTFail("Expected failedToCreateConfigDirectory, got \(terminalError)")
            }
            XCTAssertEqual(url, invalidDirectory)
        }
    }

    func testInitializationCapturesConfigWriteFailures() throws {
        let invalidDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalConfigTests-\(UUID().uuidString).txt")
        try "not a directory".write(to: invalidDirectory, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: invalidDirectory) }

        let config = TerminalConfig(configurationDirectory: invalidDirectory)
        XCTAssertNotNil(config.config, "Ghostty config object should still be created")
        XCTAssertNotNil(config.configurationError, "Initializer should retain the write failure for callers")
        if case .some(.failedToCreateConfigDirectory(let url, _)) = config.configurationError {
            XCTAssertEqual(url, invalidDirectory)
        } else {
            XCTFail("Expected failedToCreateConfigDirectory")
        }
    }

    func testRuntimeConfigurationDirectoryUsesXDGConfigHome() {
        let directory = TerminalConfig.settingsConfigurationDirectory(
            environment: ["XDG_CONFIG_HOME": "/tmp/bellith-xdg-home"]
        )

        XCTAssertEqual(directory, URL(fileURLWithPath: "/tmp/bellith-xdg-home", isDirectory: true)
            .appendingPathComponent("bellith", isDirectory: true))
    }

    func testRuntimeConfigurationDirectoryFallsBackToDotConfigInHomeDirectory() {
        let directory = TerminalConfig.settingsConfigurationDirectory(environment: [:])

        XCTAssertEqual(
            directory,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("bellith", isDirectory: true)
        )
    }

    func testGeneratedConfigPathsUseApplicationSupportDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalConfigTests-\(UUID().uuidString)", isDirectory: true)

        let paths = try TerminalConfig.configPaths(configurationDirectory: directory)

        XCTAssertEqual(paths.directory, directory)
        XCTAssertEqual(paths.generatedConfigFile, directory.appendingPathComponent("generated.conf"))
    }

    func testGeneratedConfigurationDirectoryUsesApplicationSupport() {
        let directory = TerminalConfig.generatedConfigurationDirectory()

        XCTAssertEqual(
            directory,
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("com.rec.bellith", isDirectory: true)
        )
    }
}
