import Foundation
import RoyalVNCKit

final class ConnectionSettings: ObservableObject {
    static let shared = ConnectionSettings()

    @Published var colorDepth: VNCConnection.Settings.ColorDepth {
        didSet { save() }
    }
    @Published var isShared: Bool {
        didSet { save() }
    }
    @Published var isScalingEnabled: Bool {
        didSet { save() }
    }
    @Published var isClipboardRedirectionEnabled: Bool {
        didSet { save() }
    }
    @Published var frameEncodings: [VNCFrameEncodingType] {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private let prefix = "vnc_settings_"

    private init() {
        let depth = defaults.integer(forKey: prefix + "colorDepth")
        self.colorDepth = VNCConnection.Settings.ColorDepth(rawValue: UInt8(depth)) ?? .depth24Bit
        self.isShared = defaults.object(forKey: prefix + "isShared") as? Bool ?? true
        self.isScalingEnabled = defaults.object(forKey: prefix + "isScalingEnabled") as? Bool ?? true
        self.isClipboardRedirectionEnabled = defaults.object(forKey: prefix + "clipboard") as? Bool ?? false

        if let saved = defaults.stringArray(forKey: prefix + "frameEncodings") {
            self.frameEncodings = [VNCFrameEncodingType].decode(saved)
        } else {
            self.frameEncodings = .default
        }
    }

    private func save() {
        defaults.set(Int(colorDepth.rawValue), forKey: prefix + "colorDepth")
        defaults.set(isShared, forKey: prefix + "isShared")
        defaults.set(isScalingEnabled, forKey: prefix + "isScalingEnabled")
        defaults.set(isClipboardRedirectionEnabled, forKey: prefix + "clipboard")
        defaults.set(frameEncodings.encode(), forKey: prefix + "frameEncodings")
    }
}
