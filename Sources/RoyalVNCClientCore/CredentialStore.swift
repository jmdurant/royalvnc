#if canImport(Security)
import Foundation
import Security

public enum CredentialStore {
    // Profile editors may stage credentials, but only a successful session saves them.
    private static var staged: [String: StoredCredential] = [:]
    private static let lock = NSLock()

    private static func account(host: String, port: UInt16) -> String { "\(host):\(port)" }

    private static func query(host: String, port: UInt16) -> [String: Any] {
        #if os(iOS)
        // Keep existing iOS keychain addresses so upgrades retain saved passwords.
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.royalapps.royalvnc.ios.\(account(host: host, port: port))"]
        #else
        // tvOS historically used the watch service too; preserve that address.
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.royalapps.royalvnc.watch",
                kSecAttrAccount as String: account(host: host, port: port)]
        #endif
    }

    public static func stage(host: String, port: UInt16, username: String, password: String) {
        lock.lock()
        defer { lock.unlock() }
        staged[account(host: host, port: port)] = StoredCredential(username: username, password: password)
    }

    public static func save(host: String, port: UInt16, username: String, password: String) {
        guard let data = try? CredentialCodec.encode(StoredCredential(username: username, password: password)) else { return }
        let key = query(host: host, port: port)
        let status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = key
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(insert as CFDictionary, nil)
        }
        lock.lock()
        staged.removeValue(forKey: account(host: host, port: port))
        lock.unlock()
    }

    public static func load(host: String, port: UInt16) -> StoredCredential? {
        lock.lock()
        let pending = staged[account(host: host, port: port)]
        lock.unlock()
        if let pending { return pending }

        var key = query(host: host, port: port)
        key[kSecReturnData as String] = true
        key[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(key as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        // Legacy entries are rewritten only after successful authentication.
        return CredentialCodec.decode(data)
    }

    public static func delete(host: String, port: UInt16) {
        lock.lock()
        staged.removeValue(forKey: account(host: host, port: port))
        lock.unlock()
        SecItemDelete(query(host: host, port: port) as CFDictionary)
    }
}
#endif
