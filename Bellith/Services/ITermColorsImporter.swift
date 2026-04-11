import AppKit

/// Imports iTerm2 `.itermcolors` color schemes and converts them into
/// Bellith `CustomThemeDef` JSON files stored alongside user themes.
///
/// The `.itermcolors` format is a binary or XML plist whose top-level dict has
/// keys like `Ansi 0 Color`, `Background Color`, `Foreground Color`,
/// `Cursor Color`, `Selection Color`. Each value is a nested dict with
/// `Red Component`, `Green Component`, `Blue Component` as Double in 0…1.
enum ITermColorsImporter {
    enum ImportError: LocalizedError {
        case unreadable
        case malformed
        case missingRequiredKeys
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Unable to read the selected file."
            case .malformed: return "File is not a valid iTerm2 .itermcolors plist."
            case .missingRequiredKeys: return "File is missing required color keys (Background, Foreground, or ANSI palette)."
            case .writeFailed(let reason): return "Could not save theme: \(reason)"
            }
        }
    }

    /// Parse an `.itermcolors` file into a `CustomThemeDef`, deriving Bellith's
    /// semantic palette slots from the iTerm2 colors.
    ///
    /// - Mapping:
    ///   - `base` ← Background Color
    ///   - `surface` ← Background mixed lightly toward Foreground
    ///   - `overlay` ← Background mixed further toward Foreground
    ///   - `accent` ← Ansi 4 Color (blue) — same default iTerm2 uses for hyperlinks
    ///   - `textPrimary` ← Foreground Color
    ///   - `textSecondary`/`textMuted` ← Foreground mixed toward Background
    static func parse(url: URL) throws -> CustomThemeDef {
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ImportError.malformed
        }

        func color(_ key: String) -> NSColor? {
            guard let dict = plist[key] as? [String: Any],
                  let r = dict["Red Component"] as? Double,
                  let g = dict["Green Component"] as? Double,
                  let b = dict["Blue Component"] as? Double else { return nil }
            return NSColor(
                red: CGFloat(max(0, min(1, r))),
                green: CGFloat(max(0, min(1, g))),
                blue: CGFloat(max(0, min(1, b))),
                alpha: 1.0
            )
        }

        guard let background = color("Background Color"),
              let foreground = color("Foreground Color"),
              let ansiBlue = color("Ansi 4 Color") else {
            throw ImportError.missingRequiredKeys
        }

        let surface = background.blended(withFraction: 0.05, of: foreground) ?? background
        let overlay = background.blended(withFraction: 0.12, of: foreground) ?? background
        let textSecondary = foreground.blended(withFraction: 0.25, of: background) ?? foreground
        let textMuted = foreground.blended(withFraction: 0.45, of: background) ?? foreground

        let stem = url.deletingPathExtension().lastPathComponent
        return CustomThemeDef(
            name: stem,
            ghosttyTheme: "Bellith \(stem)",
            base: background.hexString,
            surface: surface.hexString,
            overlay: overlay.hexString,
            accent: ansiBlue.hexString,
            textPrimary: foreground.hexString,
            textSecondary: textSecondary.hexString,
            textMuted: textMuted.hexString,
            border: nil,
            borderSubtle: nil
        )
    }

    /// Parse + write to `~/Library/Application Support/com.rec.bellith/themes/<name>.json`
    /// and reload the custom theme registry.
    @discardableResult
    static func importFile(url: URL) throws -> CustomThemeDef {
        let def = try parse(url: url)
        guard let dir = CustomThemeLoader.shared.themesDirectory else {
            throw ImportError.writeFailed("themes directory unavailable")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let safeName = def.name.replacingOccurrences(of: "/", with: "-")
        let destination = dir.appendingPathComponent("\(safeName).json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(def)
            try data.write(to: destination, options: .atomic)
        } catch {
            throw ImportError.writeFailed(error.localizedDescription)
        }

        CustomThemeLoader.shared.reload()
        return def
    }
}

private extension NSColor {
    var hexString: String {
        let rgb = usingColorSpace(.sRGB) ?? self
        let r = Int(round(max(0, min(1, rgb.redComponent)) * 255))
        let g = Int(round(max(0, min(1, rgb.greenComponent)) * 255))
        let b = Int(round(max(0, min(1, rgb.blueComponent)) * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
