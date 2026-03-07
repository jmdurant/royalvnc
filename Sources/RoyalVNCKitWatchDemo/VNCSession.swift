import SwiftUI
import RoyalVNCKit
import CoreGraphics

@MainActor
final class VNCSession: ObservableObject {
    @Published var currentFrame: CGImage?
    @Published var status: VNCConnection.Status = .disconnected
    @Published var errorMessage: String?

    private(set) var connection: VNCConnection?
    private var storedUsername: String = ""
    private var storedPassword: String = ""
    private var refreshTimer: Timer?
    private let delegateHandler = SessionDelegateHandler()

    func connect(hostname: String, port: UInt16, username: String, password: String) {
        storedUsername = username
        storedPassword = password

        let settings = VNCConnection.Settings(
            isDebugLoggingEnabled: false,
            hostname: hostname,
            port: port,
            isShared: true,
            isScalingEnabled: true,
            useDisplayLink: false,
            inputMode: .none,
            isClipboardRedirectionEnabled: false,
            colorDepth: .depth24Bit,
            frameEncodings: .default
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

    fileprivate func handleStateChange(_ connectionState: VNCConnection.ConnectionState) {
        status = connectionState.status
        if let error = connectionState.error {
            errorMessage = error.localizedDescription
        }
    }

    fileprivate func handleCredentialRequest(
        authenticationType: VNCAuthenticationType,
        completion: @escaping ((any VNCCredential)?) -> Void
    ) {
        if authenticationType.requiresUsername && authenticationType.requiresPassword {
            completion(VNCUsernamePasswordCredential(username: storedUsername, password: storedPassword))
        } else if authenticationType.requiresPassword {
            completion(VNCPasswordCredential(password: storedPassword))
        } else {
            completion(nil)
        }
    }

    fileprivate func handleFramebufferCreated(_ framebuffer: VNCFramebuffer) {
        startRefreshTimer(framebuffer: framebuffer)
    }

    fileprivate func handleFramebufferResized(_ framebuffer: VNCFramebuffer) {
        updateFrame(from: framebuffer)
    }

    private func startRefreshTimer(framebuffer: VNCFramebuffer) {
        refreshTimer?.invalidate()

        // Refresh at ~15 FPS to balance performance and battery
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let framebuffer = self.connection?.framebuffer else { return }
                self.updateFrame(from: framebuffer)
            }
        }
    }

    private func updateFrame(from framebuffer: VNCFramebuffer) {
        currentFrame = framebuffer.cgImage
    }
}

// Non-isolated delegate handler to bridge VNCConnectionDelegate callbacks to @MainActor
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
        // Frame updates are batched via the refresh timer
    }

    func connection(_ connection: VNCConnection,
                    didUpdateCursor cursor: VNCCursor) {
        // Cursor not rendered on watchOS
    }
}
