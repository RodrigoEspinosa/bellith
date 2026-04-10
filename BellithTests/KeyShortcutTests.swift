import XCTest
@testable import Bellith

final class KeyShortcutTests: XCTestCase {
    func testDisplayStringIncludesModifiers() {
        let shortcut = KeyShortcut(key: "t", command: true, shift: false, option: false, control: false)
        XCTAssertTrue(shortcut.displayString.contains("\u{2318}"), "Should contain command symbol")
        XCTAssertTrue(shortcut.displayString.uppercased().contains("T"))
    }

    func testDisplayStringAllModifiers() {
        let shortcut = KeyShortcut(key: "x", command: true, shift: true, option: true, control: true)
        let display = shortcut.displayString
        XCTAssertTrue(display.contains("\u{2318}"), "Should contain command")
        XCTAssertTrue(display.contains("\u{21E7}"), "Should contain shift")
        XCTAssertTrue(display.contains("\u{2325}"), "Should contain option")
        XCTAssertTrue(display.contains("\u{2303}"), "Should contain control")
    }

    func testKeycapStringsNotEmpty() {
        let shortcut = KeyShortcut(key: "d", command: true, shift: true, option: false, control: false)
        let keycaps = shortcut.keycapStrings
        XCTAssertFalse(keycaps.isEmpty)
        // Should have at least the key + modifier keycaps
        XCTAssertGreaterThanOrEqual(keycaps.count, 2)
    }

    func testModifierFlagsConversion() {
        let shortcut = KeyShortcut(key: "n", command: true, shift: false, option: true, control: false)
        let flags = shortcut.modifierFlags
        XCTAssertTrue(flags.contains(.command))
        XCTAssertTrue(flags.contains(.option))
        XCTAssertFalse(flags.contains(.shift))
        XCTAssertFalse(flags.contains(.control))
    }

    func testCodableRoundtrip() throws {
        let original = KeyShortcut(key: "k", command: true, shift: true, option: false, control: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyShortcut.self, from: data)
        XCTAssertEqual(decoded.key, original.key)
        XCTAssertEqual(decoded.command, original.command)
        XCTAssertEqual(decoded.shift, original.shift)
        XCTAssertEqual(decoded.option, original.option)
        XCTAssertEqual(decoded.control, original.control)
    }

    func testKeyBindingEntryCodableRoundtrip() throws {
        let entry = KeyBindingEntry(
            id: "test",
            label: "Test Action",
            category: "Test",
            scope: .windowChrome,
            discoverabilityText: "Test shortcut",
            primaryShortcut: KeyShortcut(key: "z", command: true, shift: false, option: false, control: true),
            alternateShortcuts: [
                KeyShortcut(key: "leftArrow", command: true, shift: false, option: true, control: false)
            ]
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(KeyBindingEntry.self, from: data)
        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.label, entry.label)
        XCTAssertEqual(decoded.category, entry.category)
        XCTAssertEqual(decoded.primaryShortcut?.key, entry.primaryShortcut?.key)
        XCTAssertEqual(decoded.alternateShortcuts.first?.key, "leftArrow")
    }

    func testSpecialKeyDisplayUsesSymbols() {
        let shortcut = KeyShortcut(key: "leftArrow", command: true, shift: false, option: true, control: false)

        XCTAssertEqual(shortcut.keycapStrings.last, "←")
        XCTAssertTrue(shortcut.displayString.contains("←"))
    }

    func testLegacyShortcutPayloadDecodesIntoPrimaryShortcut() throws {
        let json = """
        {
          "id": "legacy",
          "label": "Legacy",
          "category": "Test",
          "shortcut": {
            "key": "k",
            "command": true,
            "shift": false,
            "option": false,
            "control": false
          }
        }
        """
        let decoded = try JSONDecoder().decode(KeyBindingEntry.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.primaryShortcut?.key, "k")
        XCTAssertTrue(decoded.alternateShortcuts.isEmpty)
    }
}
