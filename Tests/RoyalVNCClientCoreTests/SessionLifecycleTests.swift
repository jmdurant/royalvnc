#if canImport(Combine) && canImport(CoreGraphics) && canImport(Security)
import XCTest
@testable import RoyalVNCKit
@testable import RoyalVNCClientCore

final class SessionLifecycleTests: XCTestCase {
    func testDismissAfterSubmitDoesNotCancelAuthentication() async {
        await MainActor.run {
            let session = ClientSession(settings: { _, _ in fatalError("No network connection expected") })
            session.credentialLoader = { _, _ in nil }
            var replies: [(any VNCCredential)?] = []
            session.handleCredentialRequest(authenticationType: .vnc) { replies.append($0) }
            XCTAssertTrue(session.showingCredentialPrompt)
            session.submitCredentials(username: "", password: "secret")
            XCTAssertFalse(session.showingCredentialPrompt)
            session.status = .connecting
            session.cancelAuthentication() // sheet's onDismiss after submission
            XCTAssertEqual(session.status, .connecting)
            XCTAssertEqual(replies.count, 1)
            XCTAssertNotNil(replies[0])
            session.submitCredentials(username: "", password: "again")
            XCTAssertEqual(replies.count, 1)
        }
    }

    func testCancellationAndDisconnectCompletePromptOnce() async {
        await MainActor.run {
            let session = ClientSession(settings: { _, _ in fatalError("No network connection expected") })
            session.credentialLoader = { _, _ in nil }
            var replies: [(any VNCCredential)?] = []
            session.handleCredentialRequest(authenticationType: .appleRemoteDesktop) { replies.append($0) }
            XCTAssertTrue(session.needsUsername)
            session.cancelAuthentication()
            session.disconnect()
            session.submitCredentials(username: "user", password: "secret")
            XCTAssertFalse(session.showingCredentialPrompt)
            XCTAssertEqual(replies.count, 1)
            XCTAssertNil(replies[0])
        }
    }

    func testSavedCredentialIsTriedOnceBeforePrompting() async {
        await MainActor.run {
            let session = ClientSession(settings: { _, _ in fatalError("No network connection expected") })
            session.credentialLoader = { _, _ in StoredCredential(username: "", password: "secret") }
            var replies: [(any VNCCredential)?] = []
            session.handleCredentialRequest(authenticationType: .appleRemoteDesktop) { replies.append($0) }
            XCTAssertFalse(session.showingCredentialPrompt)
            let saved = replies.first.flatMap { $0 as? VNCUsernamePasswordCredential }
            XCTAssertEqual(saved?.username, "")
            XCTAssertEqual(saved?.password, "secret")
            session.handleCredentialRequest(authenticationType: .appleRemoteDesktop) { replies.append($0) }
            XCTAssertTrue(session.showingCredentialPrompt)
            XCTAssertEqual(replies.count, 1)
            session.disconnect()
            XCTAssertEqual(replies.count, 2)
            XCTAssertNil(replies[1])
        }
    }

    func testCredentialPersistenceWaitsForConnectedState() async {
        await MainActor.run {
            let session = ClientSession(settings: { _, _ in fatalError("No network connection expected") })
            session.credentialLoader = { _, _ in nil }
            var saved: [StoredCredential] = []
            session.credentialSaver = { _, _, username, password in
                saved.append(StoredCredential(username: username, password: password))
            }
            session.handleCredentialRequest(authenticationType: .vnc) { _ in }
            session.submitCredentials(username: "", password: "secret")
            XCTAssertTrue(saved.isEmpty)
            session.handleStateChange(.connecting)
            XCTAssertTrue(saved.isEmpty)
            session.handleStateChange(.connected)
            XCTAssertEqual(saved, [StoredCredential(username: "", password: "secret")])
            session.handleStateChange(.connected)
            XCTAssertEqual(saved.count, 1)
        }
    }

    func testRejectedSavedCredentialsAreDeletedAndNextAttemptPrompts() async {
        await MainActor.run {
            let session = ClientSession(settings: { _, _ in fatalError("No network connection expected") })
            var stored: StoredCredential? = StoredCredential(username: "", password: "rejected")
            var deletions = 0
            var saves = 0
            session.credentialLoader = { _, _ in stored }
            session.credentialDeleter = { _, _ in stored = nil; deletions += 1 }
            session.credentialSaver = { _, _, _, _ in saves += 1 }
            session.handleCredentialRequest(authenticationType: .vnc) { _ in }
            session.handleStateChange(.disconnected(error: VNCError.authentication(.securityHandshakingFailed(reason: "Rejected"))))
            XCTAssertEqual(deletions, 1)
            XCTAssertEqual(saves, 0)
            XCTAssertNil(stored)
            session.handleCredentialRequest(authenticationType: .vnc) { _ in }
            XCTAssertTrue(session.showingCredentialPrompt)
            session.cancelAuthentication()
        }
    }

    func testTerminalStateCancelsPendingPromptWithoutDeletingUnattemptedCredentials() async {
        await MainActor.run {
            let session = ClientSession(settings: { _, _ in fatalError("No network connection expected") })
            session.credentialLoader = { _, _ in nil }
            var deletions = 0
            var replies: [(any VNCCredential)?] = []
            session.credentialDeleter = { _, _ in deletions += 1 }
            session.handleCredentialRequest(authenticationType: .vnc) { replies.append($0) }
            session.handleStateChange(.disconnected(error: VNCError.authentication(.noAuthenticationDataProvided)))
            XCTAssertEqual(replies.count, 1)
            XCTAssertNil(replies[0])
            XCTAssertFalse(session.showingCredentialPrompt)
            XCTAssertEqual(deletions, 0)
        }
    }

    func testSessionReleaseCancelsOutstandingPrompt() async {
        await MainActor.run {
            var replies: [(any VNCCredential)?] = []
            var session: ClientSession? = ClientSession(settings: { _, _ in fatalError("No network connection expected") })
            session?.credentialLoader = { _, _ in nil }
            session?.handleCredentialRequest(authenticationType: .vnc) { replies.append($0) }
            session = nil
            XCTAssertEqual(replies.count, 1)
            XCTAssertNil(replies[0])
        }
    }
}
#endif
