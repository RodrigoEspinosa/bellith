import AppKit
import Foundation

enum HyperlinkRouter {
    static func open(
        _ rawValue: String,
        using opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) -> Bool {
        guard let url = resolve(rawValue) else { return false }
        return opener(url)
    }

    static func resolve(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return url.isFileURL ? url.standardizedFileURL : url
        }

        guard trimmed.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL
    }
}
