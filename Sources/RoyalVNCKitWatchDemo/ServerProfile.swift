#if os(watchOS)
import Foundation

struct ServerProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var hostname: String
    var port: UInt16

    init(name: String, hostname: String, port: UInt16) {
        self.id = UUID()
        self.name = name
        self.hostname = hostname
        self.port = port
    }
}

enum ProfileStore {
    private static let key = "com.royalapps.royalvnc.watch.profiles"

    static func loadAll() -> [ServerProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profiles = try? JSONDecoder().decode([ServerProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    static func saveAll(_ profiles: [ServerProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func add(_ profile: ServerProfile) {
        var profiles = loadAll()
        profiles.append(profile)
        saveAll(profiles)
    }

    static func delete(_ profile: ServerProfile) {
        var profiles = loadAll()
        profiles.removeAll { $0.id == profile.id }
        saveAll(profiles)
        CredentialStore.delete(host: profile.hostname, port: profile.port)
    }

    static func update(_ profile: ServerProfile) {
        var profiles = loadAll()
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        }
        saveAll(profiles)
    }
}
#endif
