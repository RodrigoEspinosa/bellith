import Foundation
import XCTest
@testable import Bellith

final class TerminalSurfaceViewTests: XCTestCase {
    func testTemporaryDropDirectoryURLLivesUnderSystemTempDirectory() {
        let baseDirectory = URL(fileURLWithPath: "/tmp/test-base", isDirectory: true)

        let directory = TerminalSurfaceView.temporaryDropDirectoryURL(baseDirectory: baseDirectory)

        XCTAssertEqual(directory.deletingLastPathComponent().deletingLastPathComponent(), baseDirectory)
        XCTAssertEqual(directory.deletingLastPathComponent().lastPathComponent, "BellithDrops")
    }

    func testTemporaryDropImageURLUsesRequestedExtension() {
        let directory = URL(fileURLWithPath: "/tmp/BellithDrops/session", isDirectory: true)

        let url = TerminalSurfaceView.temporaryDropImageURL(in: directory, fileExtension: "png")

        XCTAssertEqual(url.deletingLastPathComponent(), directory)
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("image-"))
    }

    func testCleanupTemporaryDropDirectoryRemovesDirectoryTree() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BellithTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nestedFile = directory.appendingPathComponent("image.png")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x00, 0x01, 0x02]).write(to: nestedFile)

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedFile.path))

        TerminalSurfaceView.cleanupTemporaryDropDirectory(at: directory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
