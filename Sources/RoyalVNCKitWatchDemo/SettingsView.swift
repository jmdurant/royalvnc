import SwiftUI
import RoyalVNCKit

struct SettingsView: View {
    @ObservedObject var settings = ConnectionSettings.shared

    var body: some View {
        Form {
            Section("Color Depth") {
                Picker("Color Depth", selection: $settings.colorDepth) {
                    Text("8-bit (256 Colors)").tag(VNCConnection.Settings.ColorDepth.depth8Bit)
                    Text("16-bit").tag(VNCConnection.Settings.ColorDepth.depth16Bit)
                    Text("24-bit (Full Color)").tag(VNCConnection.Settings.ColorDepth.depth24Bit)
                }
            }

            Section("Encodings") {
                ForEach(allEncodings, id: \.self) { encoding in
                    Toggle(encoding.description, isOn: encodingBinding(for: encoding))
                }
            }

            Section("Connection") {
                Toggle("Shared Session", isOn: $settings.isShared)
                Toggle("Server Scaling", isOn: $settings.isScalingEnabled)
                Toggle("Clipboard Sync", isOn: $settings.isClipboardRedirectionEnabled)
            }

            Section {
                Button("Reset to Defaults") {
                    settings.colorDepth = .depth16Bit
                    settings.isShared = true
                    settings.isScalingEnabled = true
                    settings.isClipboardRedirectionEnabled = false
                    settings.frameEncodings = .default
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var allEncodings: [VNCFrameEncodingType] {
        [.tight, .zlib, .zrle, .hextile, .coRRE, .rre]
    }

    private func encodingBinding(for encoding: VNCFrameEncodingType) -> Binding<Bool> {
        Binding(
            get: { settings.frameEncodings.contains(encoding) },
            set: { enabled in
                if enabled {
                    if !settings.frameEncodings.contains(encoding) {
                        settings.frameEncodings.append(encoding)
                    }
                } else {
                    // Keep at least one encoding enabled
                    if settings.frameEncodings.count > 1 {
                        settings.frameEncodings.removeAll { $0 == encoding }
                    }
                }
            }
        )
    }
}
