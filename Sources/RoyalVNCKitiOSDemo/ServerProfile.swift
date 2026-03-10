#if os(iOS)
import Foundation

struct ServerProfile: Identifiable, Codable, Hashable {
    var id: String { "\(hostname):\(port)" }
    let name: String
    let hostname: String
    let port: UInt16
}

enum ProfileStore {
    private static let key = "saved_profiles_ios"

    static func loadAll() -> [ServerProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profiles = try? JSONDecoder().decode([ServerProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    static func add(_ profile: ServerProfile) {
        var profiles = loadAll()
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        save(profiles)
    }

    static func delete(_ profile: ServerProfile) {
        var profiles = loadAll()
        profiles.removeAll { $0.id == profile.id }
        save(profiles)
    }

    private static func save(_ profiles: [ServerProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
#endif
