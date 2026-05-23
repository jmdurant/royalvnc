#if os(iOS)
import SwiftUI
import RoyalVNCKit
import CoreGraphics

@MainActor
final class VNCSession: ObservableObject {
    @Published var currentFrame: CGImage?
    @Published var status: VNCConnection.Status = .disconnected
    @Published var errorMessage: String?
    @Published var showingCredentialPrompt = false
    @Published var needsUsername = false

    private(set) var connection: VNCConnection?
    private var refreshTimer: Timer?
    private let delegateHandler = SessionDelegateHandler()
    private var credentialCompletion: (((any VNCCredential)?) -> Void)?
    private(set) var connectHostname: String = ""
    private(set) var connectPort: UInt16 = 5900
    private var triedSavedCredential = false
    private var framebufferNeedsDisplay = false

    func connect(hostname: String, port: UInt16) {
        connectHostname = hostname
        connectPort = port
        triedSavedCredential = false

        let appSettings = ConnectionSettings.shared
        let settings = VNCConnection.Settings(
            isDebugLoggingEnabled: false,
            hostname: hostname,
            port: port,
            isShared: appSettings.isShared,
            isScalingEnabled: appSettings.isScalingEnabled,
            useDisplayLink: false,
            inputMode: .none,
            isClipboardRedirectionEnabled: appSettings.isClipboardRedirectionEnabled,
            colorDepth: appSettings.colorDepth,
            frameEncodings: appSettings.frameEncodings
        )

        let conn = VNCConnection(settings: settings)
        delegateHandler.session = self
        conn.delegate = delegateHandler
        self.connection = conn
        conn.connect()
    }

    func disconnect() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        connection?.disconnect()
        connection = nil
    }

    func submitCredentials(username: String, password: String) {
        showingCredentialPrompt = false

        CredentialStore.save(host: connectHostname, port: connectPort, username: username, password: password)

        guard let completion = credentialCompletion else { return }
        credentialCompletion = nil

        if needsUsername {
            completion(VNCUsernamePasswordCredential(username: username, password: password))
        } else {
            completion(VNCPasswordCredential(password: password))
        }
    }

    func cancelAuthentication() {
        guard let completion = credentialCompletion else { return }
        credentialCompletion = nil
        completion(nil)
        disconnect()
    }

    // MARK: - Delegate handlers

    fileprivate func handleStateChange(_ connectionState: VNCConnection.ConnectionState) {
        status = connectionState.status

        guard let error = connectionState.error else { return }
        let vncError = error as? VNCError

        // If authentication failed while using saved credentials, discard them
        // so the user is prompted again on the next attempt.
        if triedSavedCredential, vncError?.isAuthenticationError == true {
            CredentialStore.delete(host: connectHostname, port: connectPort)
        }

        // Suppress errors the SDK considers non-user-facing (e.g. a normal
        // disconnect or a cancelled connection). Unknown error types are shown.
        if vncError?.shouldDisplayToUser ?? true {
            errorMessage = error.localizedDescription
        }
    }

    fileprivate func handleCredentialRequest(
        authenticationType: VNCAuthenticationType,
        completion: @escaping ((any VNCCredential)?) -> Void
    ) {
        needsUsername = authenticationType.requiresUsername

        if !triedSavedCredential, let saved = CredentialStore.load(host: connectHostname, port: connectPort) {
            triedSavedCredential = true

            if authenticationType.requiresUsername {
                completion(VNCUsernamePasswordCredential(username: saved.username, password: saved.password))
            } else {
                completion(VNCPasswordCredential(password: saved.password))
            }
            return
        }

        credentialCompletion = completion
        showingCredentialPrompt = true
    }

    fileprivate func handleFramebufferCreated(_ framebuffer: VNCFramebuffer) {
        framebufferNeedsDisplay = true
        startRefreshTimer()
    }

    fileprivate func handleFramebufferResized(_ framebuffer: VNCFramebuffer) {
        updateFrame(from: framebuffer)
    }

    fileprivate func handleFramebufferUpdated() {
        framebufferNeedsDisplay = true
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()

        // The timer caps the redraw rate; the dirty flag ensures we only rebuild
        // the CGImage when the framebuffer actually changed, so a static remote
        // screen costs almost nothing.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.framebufferNeedsDisplay,
                      let framebuffer = self.connection?.framebuffer else { return }
                self.framebufferNeedsDisplay = false
                self.updateFrame(from: framebuffer)
            }
        }
    }

    private func updateFrame(from framebuffer: VNCFramebuffer) {
        currentFrame = framebuffer.cgImage
    }
}

private final class SessionDelegateHandler: NSObject, VNCConnectionDelegate {
    weak var session: VNCSession?

    func connection(_ connection: VNCConnection,
                    stateDidChange connectionState: VNCConnection.ConnectionState) {
        let state = connectionState
        Task { @MainActor [weak self] in
            self?.session?.handleStateChange(state)
        }
    }

    func connection(_ connection: VNCConnection,
                    credentialFor authenticationType: VNCAuthenticationType,
                    completion: @escaping ((any VNCCredential)?) -> Void) {
        Task { @MainActor [weak self] in
            self?.session?.handleCredentialRequest(
                authenticationType: authenticationType,
                completion: completion
            )
        }
    }

    func connection(_ connection: VNCConnection,
                    didCreateFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor [weak self] in
            self?.session?.handleFramebufferCreated(framebuffer)
        }
    }

    func connection(_ connection: VNCConnection,
                    didResizeFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor [weak self] in
            self?.session?.handleFramebufferResized(framebuffer)
        }
    }

    func connection(_ connection: VNCConnection,
                    didUpdateFramebuffer framebuffer: VNCFramebuffer,
                    x: UInt16, y: UInt16,
                    width: UInt16, height: UInt16) {
        Task { @MainActor [weak self] in
            self?.session?.handleFramebufferUpdated()
        }
    }

    func connection(_ connection: VNCConnection,
                    didUpdateCursor cursor: VNCCursor) {
    }
}
#endif
