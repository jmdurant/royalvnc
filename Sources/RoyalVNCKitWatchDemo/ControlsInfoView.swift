#if os(watchOS)
import SwiftUI

struct ControlsInfoView: View {
    var body: some View {
        List {
            Section("Toolbar") {
                controlRow(icon: "chevron.up", title: "Swipe Up", description: "Open toolbar with keyboard, mode toggle, special keys, and disconnect")
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

            Section("Toolbar Actions") {
                controlRow(icon: "cursorarrow", title: "Pointer / Pan", description: "Toggle input mode")
                controlRow(icon: "keyboard", title: "Keyboard", description: "Open text input")
                controlRow(icon: "escape", title: "Esc", description: "Send Escape key")
                controlRow(icon: "return.left", title: "Return", description: "Send Return key")
                controlRow(icon: "delete.backward", title: "Delete", description: "Send Delete key")
                controlRow(icon: "tab", title: "Tab", description: "Send Tab key")
                controlRow(icon: "power", title: "Ctrl+Alt+Del", description: "Send Ctrl+Alt+Delete")
                controlRow(icon: "xmark.circle", title: "Disconnect", description: "End VNC session")
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
#endif
