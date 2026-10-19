import XCTest
@testable import RoyalVNCClientCore

final class CredentialTests: XCTestCase {
    func testJSONPreservesEmptyFieldsAndNewlines() throws {
        for credential in [
            StoredCredential(username: "", password: "secret"),
            StoredCredential(username: "user", password: ""),
            StoredCredential(username: "", password: ""),
            StoredCredential(username: "a\nb", password: "\n秘密\n")
        ] {
            XCTAssertEqual(CredentialCodec.decode(try CredentialCodec.encode(credential)), credential)
        }
    }

    func testLegacyMigrationPreservesEmptyFields() {
        XCTAssertEqual(CredentialCodec.decode(Data("\npassword".utf8)), StoredCredential(username: "", password: "password"))
        XCTAssertEqual(CredentialCodec.decode(Data("user\n".utf8)), StoredCredential(username: "user", password: ""))
        XCTAssertEqual(CredentialCodec.decode(Data("\n".utf8)), StoredCredential(username: "", password: ""))
        XCTAssertEqual(CredentialCodec.decode(Data("user\na\nb".utf8)), StoredCredential(username: "user", password: "a\nb"))
    }

    func testCorruptAndUnsupportedValuesAreNotTreatedAsPasswords() {
        XCTAssertNil(CredentialCodec.decode(Data([0xff])))
        XCTAssertNil(CredentialCodec.decode(Data("ambiguous password".utf8)))
        XCTAssertNil(CredentialCodec.decode(Data("{\ncorrupt".utf8)))
        XCTAssertNil(CredentialCodec.decode(Data(#"{"version":2,"credential":{"username":"a","password":"b"}}"#.utf8)))
    }

    func testAttemptOnlyProducesCandidateAfterAuthentication() {
        let credential = StoredCredential(username: "", password: "secret")
        var attempt = CredentialAttempt()
        attempt.submit(credential)
        XCTAssertEqual(attempt.candidate, credential)
        attempt.reset() // failure/cancellation discards input
        XCTAssertNil(attempt.authenticated())
        attempt.submit(credential, stored: true)
        XCTAssertTrue(attempt.usedStoredCredential)
        XCTAssertEqual(attempt.authenticated(), credential)
        XCTAssertNil(attempt.authenticated())
        attempt.reset()
        XCTAssertFalse(attempt.usedStoredCredential)
    }

    func testPendingRequestResolvesExactlyOnceAndCancelsOnRelease() {
        var values: [String?] = []
        var request: PendingCredentialRequest<String>? = PendingCredentialRequest { values.append($0) }
        request?.resolve("password")
        request?.resolve(nil)
        request = nil
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0], "password")
        request = PendingCredentialRequest { values.append($0) }
        request = nil
        XCTAssertEqual(values.count, 2)
        XCTAssertNil(values[1])
    }

    func testProfilesDecodeBothExistingFormats() throws {
        let oldIOS = Data(#"{"name":"Mac","hostname":"mac.local","port":5900}"#.utf8)
        let ios = try JSONDecoder().decode(ServerProfile.self, from: oldIOS)
        XCTAssertEqual(ios.id, "mac.local:5900")
        let oldWatch = Data(#"{"id":"A80C56CF-C7E0-4934-BFC4-2DF929AD87D8","name":"Mac","hostname":"mac.local","port":5900}"#.utf8)
        let watch = try JSONDecoder().decode(ServerProfile.self, from: oldWatch)
        XCTAssertEqual(watch.id, "A80C56CF-C7E0-4934-BFC4-2DF929AD87D8")
        XCTAssertEqual(try JSONDecoder().decode(ServerProfile.self, from: JSONEncoder().encode(watch)), watch)
    }
}
