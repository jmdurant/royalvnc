import Foundation

public struct StoredCredential: Codable, Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// A versioned format preserves empty fields, Unicode and embedded newlines.
public enum CredentialCodec {
    private struct Envelope: Codable {
        let version: Int
        let credential: StoredCredential
    }

    public static func encode(_ credential: StoredCredential) throws -> Data {
        try JSONEncoder().encode(Envelope(version: 1, credential: credential))
    }

    public static func decode(_ data: Data) -> StoredCredential? {
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            return envelope.version == 1 ? envelope.credential : nil
        }
        // Only the old delimiter format can be migrated unambiguously. Do not
        // reinterpret corrupt/unsupported JSON or separator-free values as passwords.
        guard let legacy = String(data: data, encoding: .utf8),
              !legacy.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
              let separator = legacy.firstIndex(of: "\n") else { return nil }
        return StoredCredential(username: String(legacy[..<separator]),
                                password: String(legacy[legacy.index(after: separator)...]))
    }
}

/// Keeps unverified input in memory until the connection authenticates.
struct CredentialAttempt {
    private(set) var candidate: StoredCredential?
    private(set) var usedStoredCredential = false

    mutating func submit(_ credential: StoredCredential, stored: Bool = false) {
        candidate = credential
        usedStoredCredential = usedStoredCredential || stored
    }

    mutating func authenticated() -> StoredCredential? {
        defer { candidate = nil }
        return candidate
    }

    mutating func reset() {
        candidate = nil
        usedStoredCredential = false
    }
}

/// Owns the SDK completion and guarantees every request is completed once.
final class PendingCredentialRequest<Value> {
    private var completion: ((Value?) -> Void)?

    init(_ completion: @escaping (Value?) -> Void) { self.completion = completion }

    func resolve(_ value: Value?) {
        let callback = completion
        completion = nil
        callback?(value)
    }

    deinit { completion?(nil) }
}
