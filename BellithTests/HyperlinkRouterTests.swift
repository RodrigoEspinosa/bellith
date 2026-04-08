import Foundation
import XCTest
@testable import Bellith

final class HyperlinkRouterTests: XCTestCase {
    func testResolveTrimsAndPreservesHTTPSURLs() {
        let url = HyperlinkRouter.resolve("  https://example.com/path?q=1  ")

        XCTAssertEqual(url?.absoluteString, "https://example.com/path?q=1")
    }

    func testResolveStandardizesFileURLs() {
        let url = HyperlinkRouter.resolve("file:///tmp/../tmp/example.swift")

        XCTAssertEqual(url?.path, "/tmp/example.swift")
        XCTAssertTrue(url?.isFileURL ?? false)
    }

    func testResolvePromotesAbsolutePathsToFileURLs() {
        let url = HyperlinkRouter.resolve("/tmp/example.swift")

        XCTAssertEqual(url?.path, "/tmp/example.swift")
        XCTAssertTrue(url?.isFileURL ?? false)
    }

    func testResolveRejectsPlainTextWithoutSchemeOrPath() {
        XCTAssertNil(HyperlinkRouter.resolve("not a url"))
    }

    func testOpenUsesInjectedOpener() {
        var openedURL: URL?

        let didOpen = HyperlinkRouter.open("https://bellith.dev") { url in
            openedURL = url
            return true
        }

        XCTAssertTrue(didOpen)
        XCTAssertEqual(openedURL?.absoluteString, "https://bellith.dev")
    }
}
