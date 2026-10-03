import Foundation
import UniformTypeIdentifiers

struct CreativeAsset: Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case audio = "Audio", video = "Video", image = "Images"
        var symbol: String {
            switch self {
            case .audio: return "waveform"
            case .video: return "film"
            case .image: return "photo"
            }
        }
    }

    let id: String
    let name: String
    let kind: Kind
    let url: URL?
    let relativePath: String
    let bytes: Int64

    static func kind(for url: URL) -> Kind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .image) { return .image }
        return nil
    }

    static let examples: [CreativeAsset] = [
        ("01 — After hours.wav", Kind.audio, "Mixes"),
        ("02 — Slow motion.wav", .audio, "Mixes"),
        ("After hours — instrumental.wav", .audio, "Stems"),
        ("After hours — vocals.wav", .audio, "Stems"),
        ("Live session.mov", .video, "Video"),
        ("Sleeve artwork.png", .image, "Artwork"),
    ].map { name, kind, folder in
        CreativeAsset(id: name, name: name, kind: kind, url: nil, relativePath: "\(folder)/\(name)", bytes: 0)
    }
}

enum CreativeProjectFiles {
    /// Skip hidden files, packages, and symlinks; preserve the project's folder structure.
    static func scan(_ root: URL) throws -> [CreativeAsset] {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        guard root.isFileURL, try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw CreativeProjectError.folderRequired
        }
        var scanError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in scanError = error; return false }
        ) else { throw CocoaError(.fileReadUnknown) }
        var assets: [CreativeAsset] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true,
                  let kind = CreativeAsset.kind(for: url) else { continue }
            let canonicalPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            guard canonicalPath.hasPrefix(prefix) else { continue }
            let relative = String(canonicalPath.dropFirst(prefix.count))
            assets.append(CreativeAsset(id: relative, name: url.lastPathComponent, kind: kind,
                                        url: url, relativePath: relative, bytes: Int64(values.fileSize ?? 0)))
        }
        if let scanError { throw scanError }
        return assets.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    /// Each delivery has its own directory; sources are never modified or overwritten.
    static func deliver(_ assets: [CreativeAsset], to parent: URL) throws -> URL {
        let output = parent.appendingPathComponent("Bellith Delivery \(UUID().uuidString)", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: output, withIntermediateDirectories: false)
        do {
            var manifest: [[String: String]] = []
            for asset in assets {
                guard let source = asset.url else { continue }
                let parts = asset.relativePath.split(separator: "/")
                guard !asset.relativePath.hasPrefix("/"), !parts.contains(".."), !parts.isEmpty else {
                    throw CocoaError(.fileWriteInvalidFileName)
                }
                let target = output.appendingPathComponent("Media").appendingPathComponent(asset.relativePath)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: source, to: target)
                manifest.append(["file": "Media/\(asset.relativePath)", "type": asset.kind.rawValue])
            }
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
            return output
        } catch {
            // Only remove the new, incomplete delivery created by this operation.
            try? manager.removeItem(at: output)
            throw error
        }
    }
}

enum CreativeProjectError: LocalizedError {
    case folderRequired
    var errorDescription: String? { "Choose a project folder. This location is not a directory." }
}
