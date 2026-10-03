import XCTest
@testable import Bellith

final class CreativeProjectTests: XCTestCase {
    func testScanRejectsAFileInsteadOfInventingAnEmptyProject() throws {
        let file = root.appendingPathComponent("fixture.wav")
        try Data().write(to: file)
        XCTAssertThrowsError(try CreativeProjectFiles.scan(file))
    }
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testScanKeepsRelativePathsAndIgnoresHiddenFilesAndLinks() throws {
        let nested = root.appendingPathComponent("Stems")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: nested.appendingPathComponent("Vocal.WAV"))
        try Data().write(to: root.appendingPathComponent("notes.txt"))
        try Data().write(to: root.appendingPathComponent(".hidden.wav"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.wav"),
                                                   withDestinationURL: nested.appendingPathComponent("Vocal.WAV"))
        let assets = try CreativeProjectFiles.scan(root)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets.first?.relativePath, "Stems/Vocal.WAV")
        XCTAssertEqual(assets.first?.kind, .audio)
        XCTAssertEqual(assets.first?.bytes, 3)
    }

    func testDeliveryPreservesDuplicateNamesInDifferentFoldersAndSources() throws {
        for folder in ["Mixes", "Stems"] {
            let path = root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try Data(folder.utf8).write(to: path.appendingPathComponent("track.wav"))
        }
        let assets = try CreativeProjectFiles.scan(root)
        let delivery = try CreativeProjectFiles.deliver(assets, to: root)
        for asset in assets {
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(asset.url)),
                           try Data(contentsOf: delivery.appendingPathComponent("Media/\(asset.relativePath)")))
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: delivery.appendingPathComponent("manifest.json"))) as? [[String: String]]
        XCTAssertEqual(manifest?.count, 2)
        let second = try CreativeProjectFiles.deliver(assets, to: root)
        XCTAssertNotEqual(delivery, second)
    }

    func testDeliveryRejectsTraversalAndRemovesIncompletePackage() throws {
        let source = root.appendingPathComponent("original.wav")
        try Data([1]).write(to: source)
        let asset = CreativeAsset(id: "bad", name: "bad", kind: .audio, url: source, relativePath: "../escape.wav", bytes: 1)
        XCTAssertThrowsError(try CreativeProjectFiles.deliver([asset], to: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["original.wav"])
    }
}
