import Foundation

public struct ServerProfile: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var hostname: String
    public var port: UInt16

    public init(name: String, hostname: String, port: UInt16) {
        #if os(iOS)
        self.id = "\(hostname):\(port)"
        #else
        self.id = UUID().uuidString
        #endif
        self.name = name
        self.hostname = hostname
        self.port = port
    }

    private enum CodingKeys: String, CodingKey { case id, name, hostname, port }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        hostname = try values.decode(String.self, forKey: .hostname)
        port = try values.decode(UInt16.self, forKey: .port)
        // Original iOS profiles omitted the computed endpoint identity; watch/tv
        // profiles stored UUID strings. Both formats remain readable.
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? "\(hostname):\(port)"
    }
}

public enum ProfileStore {
    private static var key: String {
        #if os(iOS)
        "saved_profiles_ios"
        #else
        "com.royalapps.royalvnc.watch.profiles"
        #endif
    }

    public static func loadAll() -> [ServerProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profiles = try? JSONDecoder().decode([ServerProfile].self, from: data) else { return [] }
        return profiles
    }

    public static func saveAll(_ profiles: [ServerProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    public static func add(_ profile: ServerProfile) {
        var profiles = loadAll()
        #if os(iOS)
        profiles.removeAll { $0.id == profile.id }
        #endif
        profiles.append(profile)
        saveAll(profiles)
    }

    public static func delete(_ profile: ServerProfile) {
        saveAll(loadAll().filter { $0.id != profile.id })
        #if canImport(Security)
        CredentialStore.delete(host: profile.hostname, port: profile.port)
        #endif
    }

    public static func update(_ profile: ServerProfile) {
        var profiles = loadAll()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        saveAll(profiles)
    }
}
