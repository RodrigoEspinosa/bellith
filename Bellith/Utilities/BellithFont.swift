import AppKit

enum BellithFont {
    static func ui(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let candidates: [String]
        switch weight {
        case .medium, .semibold, .bold, .heavy, .black:
            candidates = ["Space Grotesk Medium", "SpaceGrotesk-Medium", "Space Grotesk"]
        default:
            candidates = ["Space Grotesk Regular", "SpaceGrotesk-Regular", "Space Grotesk"]
        }
        return resolveFont(candidates: candidates, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let candidates: [String]
        switch weight {
        case .medium, .semibold, .bold, .heavy, .black:
            candidates = ["Space Mono Bold", "SpaceMono-Bold", "Space Mono"]
        default:
            candidates = ["Space Mono Regular", "SpaceMono-Regular", "Space Mono"]
        }
        return resolveFont(candidates: candidates, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func display(_ size: CGFloat) -> NSFont {
        resolveFont(candidates: ["Doto Regular", "Doto", "Space Mono"], size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func resolveFont(candidates: [String], size: CGFloat) -> NSFont? {
        for name in candidates {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return nil
    }
}
