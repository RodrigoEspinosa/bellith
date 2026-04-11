import Foundation

enum BellithFeatureFlag: String, CaseIterable {
    case builtInSettingsWindow

    var title: String {
        switch self {
        case .builtInSettingsWindow:
            "Built-in Settings Window"
        }
    }

    var detail: String {
        switch self {
        case .builtInSettingsWindow:
            "When off, Settings and ⌘, open settings.json in your editor instead."
        }
    }

    var defaultValue: Bool {
        switch self {
        case .builtInSettingsWindow:
            false
        }
    }
}
