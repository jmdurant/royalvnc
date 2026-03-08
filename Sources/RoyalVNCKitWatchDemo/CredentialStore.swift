#if os(watchOS)
import Foundation
import Security

struct StoredCredential {
    let username: String
    let password: String
}

enum CredentialStore {
    static func save(host: String, port: UInt16, username: String, password: String) {
        let account = "\(host):\(port)"

        // Store password
        delete(host: host, port: port)

        let value = "\(username)\n\(password)"
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.royalapps.royalvnc.watch",
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(host: String, port: UInt16) -> StoredCredential? {
        let account = "\(host):\(port)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.royalapps.royalvnc.watch",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        let parts = value.split(separator: "\n", maxSplits: 1)
        guard parts.count == 2 else {
            // Password only (no username)
            return StoredCredential(username: "", password: value)
        }

        return StoredCredential(username: String(parts[0]), password: String(parts[1]))
    }

    static func delete(host: String, port: UInt16) {
        let account = "\(host):\(port)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.royalapps.royalvnc.watch",
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
#endif
