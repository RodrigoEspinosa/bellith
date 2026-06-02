import XCTest
@testable import Bellith

final class UpdaterControllerTests: XCTestCase {
    func testConfigurationWithPlaceholderPublicKeyIsNotUsable() {
        let info: [String: Any] = [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": UpdaterController.placeholderPublicEDKey,
        ]

        XCTAssertFalse(UpdaterController.isUsableConfiguration(infoDictionary: info))
    }

    func testConfigurationWithValidFeedAndPublicKeyIsUsable() {
        let info: [String: Any] = [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "valid-public-key",
        ]

        XCTAssertTrue(UpdaterController.isUsableConfiguration(infoDictionary: info))
    }

    func testConfigurationWithoutHTTPFeedIsNotUsable() {
        let info: [String: Any] = [
            "SUFeedURL": "file:///tmp/appcast.xml",
            "SUPublicEDKey": "valid-public-key",
        ]

        XCTAssertFalse(UpdaterController.isUsableConfiguration(infoDictionary: info))
    }
}
