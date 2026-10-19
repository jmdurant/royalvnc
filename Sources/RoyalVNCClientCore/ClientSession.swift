#if canImport(Combine) && canImport(CoreGraphics) && canImport(Security)
import Foundation
import Combine
import RoyalVNCKit
import CoreGraphics

@MainActor
open class ClientSession: ObservableObject {
    @Published public var currentFrame: CGImage?
    @Published public var status: VNCConnection.Status = .disconnected
    @Published public var errorMessage: String?
    @Published public var showingCredentialPrompt = false
    @Published public var needsUsername = false

    public private(set) var connection: VNCConnection?
    private var refreshTimer: Timer?
    private let delegateHandler = SessionDelegateHandler()
    private var credentialRequest: PendingCredentialRequest<any VNCCredential>?
    private var attempt = CredentialAttempt()
    var credentialLoader: (String, UInt16) -> StoredCredential? = CredentialStore.load
    var credentialSaver: (String, UInt16, String, String) -> Void = CredentialStore.save
    var credentialDeleter: (String, UInt16) -> Void = CredentialStore.delete
    private let frameRate: Double
    private let settingsFactory: (String, UInt16) -> VNCConnection.Settings
    public private(set) var connectHostname: String = ""
    public private(set) var connectPort: UInt16 = 5900
    private var framebufferNeedsDisplay = false

    public init(frameRate: Double = 15,
                settings: @escaping (String, UInt16) -> VNCConnection.Settings) {
        self.frameRate = frameRate
        self.settingsFactory = settings
    }

    deinit {
        refreshTimer?.invalidate()
        connection?.disconnect()
    }

    public func connect(hostname: String, port: UInt16) {
        disconnect()
        connectHostname = hostname
        connectPort = port
        errorMessage = nil
        currentFrame = nil
        attempt.reset()
        let settings = settingsFactory(hostname, port)

        let conn = VNCConnection(settings: settings)
        delegateHandler.session = self
        conn.delegate = delegateHandler
        self.connection = conn
        conn.connect()
    }

    public func disconnect() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        framebufferNeedsDisplay = false
        let oldConnection = connection
        connection = nil
        cancelPendingRequest()
        attempt.reset()
        oldConnection?.disconnect()
        status = .disconnected
    }

    public func submitCredentials(username: String, password: String) {
        guard let request = credentialRequest else { return }
        credentialRequest = nil
        showingCredentialPrompt = false
        let credential = StoredCredential(username: username, password: password)
        attempt.submit(credential)
        request.resolve(sdkCredential(credential))
    }

    public func cancelAuthentication() {
        // The sheet also calls this after submitting and dismissing normally.
        guard credentialRequest != nil else { return }
        disconnect()
    }

    private func cancelPendingRequest() {
        let request = credentialRequest
        credentialRequest = nil
        showingCredentialPrompt = false
        request?.resolve(nil)
    }

    private func sdkCredential(_ credential: StoredCredential) -> any VNCCredential {
        if needsUsername {
            return VNCUsernamePasswordCredential(username: credential.username, password: credential.password)
        }
        return VNCPasswordCredential(password: credential.password)
    }

    // MARK: - Delegate handlers

    func handleStateChange(_ connectionState: VNCConnection.ConnectionState) {
        status = connectionState.status

        if connectionState.status == .connected, let credential = attempt.authenticated() {
            credentialSaver(connectHostname, connectPort, credential.username, credential.password)
        }
        if connectionState.status == .disconnected {
            connection = nil
            refreshTimer?.invalidate()
            refreshTimer = nil
            cancelPendingRequest()
        }
        guard let error = connectionState.error else {
            if connectionState.status == .disconnected { attempt.reset() }
            return
        }
        let vncError = error as? VNCError
        if attempt.candidate != nil, vncError?.isAuthenticationError == true {
            credentialDeleter(connectHostname, connectPort)
        }
        attempt.reset()

        // Suppress errors the SDK considers non-user-facing (e.g. a normal
        // disconnect or a cancelled connection). Unknown error types are shown.
        if vncError?.shouldDisplayToUser ?? true {
            errorMessage = error.localizedDescription
        }
    }

    func handleCredentialRequest(
        authenticationType: VNCAuthenticationType,
        completion: @escaping ((any VNCCredential)?) -> Void
    ) {
        needsUsername = authenticationType.requiresUsername

        cancelPendingRequest()
        if !attempt.usedStoredCredential,
           let saved = credentialLoader(connectHostname, connectPort) {
            attempt.submit(saved, stored: true)
            completion(sdkCredential(saved))
            return
        }

        credentialRequest = PendingCredentialRequest(completion)
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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / frameRate, repeats: true) { [weak self] _ in
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
    weak var session: ClientSession?

    func connection(_ connection: VNCConnection,
                    stateDidChange connectionState: VNCConnection.ConnectionState) {
        let state = connectionState
        Task { @MainActor [weak self] in
            guard let session = self?.session, session.connection === connection else { return }
            session.handleStateChange(state)
        }
    }

    func connection(_ connection: VNCConnection,
                    credentialFor authenticationType: VNCAuthenticationType,
                    completion: @escaping ((any VNCCredential)?) -> Void) {
        Task { @MainActor [weak self] in
            guard let session = self?.session, session.connection === connection else {
                completion(nil)
                return
            }
            session.handleCredentialRequest(
                authenticationType: authenticationType,
                completion: completion
            )
        }
    }

    func connection(_ connection: VNCConnection,
                    didCreateFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor [weak self] in
            guard let session = self?.session, session.connection === connection else { return }
            session.handleFramebufferCreated(framebuffer)
        }
    }

    func connection(_ connection: VNCConnection,
                    didResizeFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor [weak self] in
            guard let session = self?.session, session.connection === connection else { return }
            session.handleFramebufferResized(framebuffer)
        }
    }

    func connection(_ connection: VNCConnection,
                    didUpdateFramebuffer framebuffer: VNCFramebuffer,
                    x: UInt16, y: UInt16,
                    width: UInt16, height: UInt16) {
        Task { @MainActor [weak self] in
            guard let session = self?.session, session.connection === connection else { return }
            session.handleFramebufferUpdated()
        }
    }

    func connection(_ connection: VNCConnection,
                    didUpdateCursor cursor: VNCCursor) {
    }
}
#endif
