#if os(tvOS)
import SwiftUI
import RoyalVNCKit

struct SettingsView: View {
    @ObservedObject var settings = ConnectionSettings.shared

    private var sensitivityLabel: String {
        let pct = Int(settings.cursorSensitivity * 100)
        return "\(pct)%"
    }

    var body: some View {
        Form {
            Section(header: Text("Remote Control"), footer: Text("Adjust how fast the cursor moves when swiping on the Siri Remote.")) {
                HStack {
                    Text("Cursor Speed")
                    Spacer()
                    Text(sensitivityLabel)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Button {
                        settings.cursorSensitivity = max(0.25, settings.cursorSensitivity - 0.25)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .disabled(settings.cursorSensitivity <= 0.25)

                    Spacer()

                    Button {
                        settings.cursorSensitivity = min(3.0, settings.cursorSensitivity + 0.25)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .disabled(settings.cursorSensitivity >= 3.0)
                }
            }

            Section(header: Text("Color Depth")) {
                Picker("Color Depth", selection: $settings.colorDepth) {
                    Text("8-bit (256 Colors)").tag(VNCConnection.Settings.ColorDepth.depth8Bit)
                    Text("16-bit").tag(VNCConnection.Settings.ColorDepth.depth16Bit)
                    Text("24-bit (Full Color)").tag(VNCConnection.Settings.ColorDepth.depth24Bit)
                }
            }

            Section(header: Text("Encodings")) {
                ForEach(allEncodings, id: \.self) { encoding in
                    Toggle(encoding.description, isOn: encodingBinding(for: encoding))
                }
            }

            Section(header: Text("Connection")) {
                Toggle("Shared Session", isOn: $settings.isShared)
                Toggle("Server Scaling", isOn: $settings.isScalingEnabled)
                Toggle("Clipboard Sync", isOn: $settings.isClipboardRedirectionEnabled)
            }

            Section {
                Button("Reset to Defaults") {
                    settings.colorDepth = .depth24Bit
                    settings.isShared = true
                    settings.isScalingEnabled = true
                    settings.isClipboardRedirectionEnabled = false
                    settings.cursorSensitivity = ConnectionSettings.defaultCursorSensitivity
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
                    if settings.frameEncodings.count > 1 {
                        settings.frameEncodings.removeAll { $0 == encoding }
                    }
                }
            }
        )
    }
}
#endif
