import SwiftUI

struct ControlsInfoView: View {
    var body: some View {
        List {
            Section {
                Text("Toggle between modes using the toolbar button. On Apple Watch Ultra, use the Action Button.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Pointer Mode") {
                controlRow(icon: "cursorarrow", title: "Mode", description: "Control the remote desktop")
                controlRow(icon: "hand.tap", title: "Tap", description: "Left click")
                controlRow(icon: "hand.tap", title: "Double Tap", description: "Double click")
                controlRow(icon: "hand.tap.fill", title: "Long Press", description: "Right click")
                controlRow(icon: "hand.draw", title: "Drag", description: "Move mouse cursor")
                controlRow(icon: "digitalcrown.arrow.clockwise", title: "Digital Crown", description: "Scroll wheel")
            }

            Section("Pan Mode") {
                controlRow(icon: "hand.draw", title: "Mode", description: "Navigate your view, tap to click")
                controlRow(icon: "hand.tap", title: "Tap", description: "Left click")
                controlRow(icon: "hand.tap", title: "Double Tap", description: "Zoom in / zoom out")
                controlRow(icon: "hand.draw", title: "Drag", description: "Pan the viewport")
                controlRow(icon: "digitalcrown.arrow.clockwise", title: "Digital Crown", description: "Fine zoom control")
            }

            Section("General") {
                controlRow(icon: "chevron.left", title: "Back", description: "Swipe right to disconnect")
            }
        }
        .navigationTitle("Controls")
    }

    private func controlRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
