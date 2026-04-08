import Foundation
import os

final class SSHProfileStore {
    static let shared = SSHProfileStore()
    static let didChangeNotification = Notification.Name("SSHProfileStoreDidChange")

    private let defaults: UserDefaults
    private let storageKey = "sshProfiles"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var profiles: [SSHProfile] {
        loadProfiles()
    }

    func profile(id: UUID) -> SSHProfile? {
        profiles.first { $0.id == id }
    }

    func save(_ profiles: [SSHProfile]) {
        let sanitized = profiles.map { $0.sanitized() }
        do {
            let data = try JSONEncoder().encode(sanitized)
            defaults.set(data, forKey: storageKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        } catch {
            Logger.config.error("Failed to persist SSH profiles: \(error.localizedDescription)")
        }
    }

    func upsert(_ profile: SSHProfile) {
        var next = profiles
        let sanitized = profile.sanitized()
        if let index = next.firstIndex(where: { $0.id == sanitized.id }) {
            next[index] = sanitized
        } else {
            next.append(sanitized)
        }
        save(next)
    }

    func deleteProfile(id: UUID) {
        save(profiles.filter { $0.id != id })
    }

    private func loadProfiles() -> [SSHProfile] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        do {
            return try JSONDecoder().decode([SSHProfile].self, from: data)
        } catch {
            Logger.config.error("Failed to decode SSH profiles: \(error.localizedDescription)")
            return []
        }
    }
}
