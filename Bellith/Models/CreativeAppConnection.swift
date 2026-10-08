import Foundation

struct CreativeAppConnection: Codable, Identifiable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case notInstalled, notRunning, permissionRequired, dialogOpen, windowObserved, noWindow, unavailable
        var label: String {
            switch self {
            case .notInstalled: return "Not installed"
            case .notRunning: return "Installed · not running"
            case .permissionRequired: return "Running · Bellith needs Accessibility access"
            case .dialogOpen: return "Running · resolve the app’s dialog first"
            case .windowObserved: return "Window observed · editing control unverified"
            case .noWindow: return "Running · no project window observed"
            case .unavailable: return "Running · window inspection unavailable"
            }
        }
    }
    let id: String
    let name: String
    let version: String?
    let state: State
    let windowTitle: String?
    let inspectedAt: Date
}
