#if os(watchOS)
import RoyalVNCKit
import RoyalVNCClientCore

@MainActor
final class VNCSession: ClientSession {
    init() {
        super.init(frameRate: 15) { hostname, port in
            let appSettings = ConnectionSettings.shared
            return VNCConnection.Settings(
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

        }
    }
}
#endif
