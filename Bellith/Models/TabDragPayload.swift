import AppKit
import Foundation

struct TabDragPayload: Codable, Equatable {
    static let pasteboardType = NSPasteboard.PasteboardType("com.rec.bellith.tab")

    let sourceWindowID: UUID
    let tabID: UUID

    private var encodedData: Data? {
        try? JSONEncoder().encode(self)
    }

    func write(to pasteboard: NSPasteboard) {
        guard let encodedData else { return }
        pasteboard.clearContents()
        pasteboard.setData(encodedData, forType: Self.pasteboardType)
    }

    func set(on pasteboardItem: NSPasteboardItem) {
        guard let encodedData else { return }
        pasteboardItem.setData(encodedData, forType: Self.pasteboardType)
    }

    static func read(from pasteboard: NSPasteboard) -> TabDragPayload? {
        guard let data = pasteboard.data(forType: Self.pasteboardType) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
