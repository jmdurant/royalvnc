#if os(iOS)
import Foundation
import Security

struct SavedCredential {
    let username: String
    let password: String
}

enum CredentialStore {
    private static func service(host: String, port: UInt16) -> String {
        "com.royalapps.royalvnc.ios.\(host):\(port)"
    }

    static func save(host: String, port: UInt16, username: String, password: String) {
        let service = service(host: host, port: port)
        let data = "\(username)\n\(password)".data(using: .utf8)!

        delete(host: host, port: port)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(host: String, port: UInt16) -> SavedCredential? {
        let service = service(host: host, port: port)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }

        let parts = str.split(separator: "\n", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        return SavedCredential(username: String(parts[0]), password: String(parts[1]))
    }

    static func delete(host: String, port: UInt16) {
        let service = service(host: host, port: port)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
#endif
