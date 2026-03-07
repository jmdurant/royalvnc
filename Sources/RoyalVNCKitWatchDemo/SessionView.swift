import SwiftUI
import RoyalVNCKit

enum InputMode: String {
    case interact = "Interact"
    case navigate = "Navigate"
}

struct SessionView: View {
    let hostname: String
    let port: UInt16

    @StateObject private var session = VNCSession()
    @State private var inputMode: InputMode = .navigate
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastDragPosition: CGPoint?
    @State private var crownValue: CGFloat = 0.0
    @State private var lastCrownValue: CGFloat = 0.0
    @State private var lastMousePosition: (x: UInt16, y: UInt16) = (0, 0)
    @State private var isZoomedIn = false
    @State private var showingToolbar = false
    @State private var showingKeyboard = false
    @State private var keyboardText = ""
    @State private var lastKeyboardText = ""

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let cgImage = session.currentFrame {
                    let frameSize = CGSize(width: cgImage.width, height: cgImage.height)

                    Image(cgImage, scale: 1.0, label: Text("VNC"))
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                        .gesture(doubleTapGesture(in: geometry, frameSize: frameSize))
                        .gesture(singleTapGesture(in: geometry, frameSize: frameSize))
                        .gesture(longPressGesture(in: geometry, frameSize: frameSize))
                        .gesture(dragGesture(in: geometry, frameSize: frameSize))
                }

                if session.status == .connecting {
                    ProgressView("Connecting...")
                }

                if let error = session.errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                        Text(error)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.red)
                }

                // Mode indicator (bottom right)
                if session.status == .connected {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Label(
                                inputMode == .interact ? "Pointer" : "Pan",
                                systemImage: inputMode == .interact ? "cursorarrow" : "hand.draw"
                            )
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(4)
                    .allowsHitTesting(false)
                }

                // Swipe-up hint (bottom center)
                if session.status == .connected && !showingToolbar {
                    VStack {
                        Spacer()
                        Capsule()
                            .fill(.white.opacity(0.3))
                            .frame(width: 36, height: 4)
                            .padding(.bottom, 2)
                    }
                    .allowsHitTesting(false)
                }

                // Swipe-up toolbar overlay
                if showingToolbar {
                    toolbarOverlay
                }
            }
            .gesture(swipeUpGesture)
        }
        .sheet(isPresented: $session.showingCredentialPrompt) {
            CredentialPromptView(session: session)
        }
        .sheet(isPresented: $showingKeyboard) {
            KeyboardInputView(session: session)
        }
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: -1000,
            through: 1000,
            sensitivity: inputMode == .interact ? .medium : .low,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { newValue in
            let delta = newValue - lastCrownValue
            lastCrownValue = newValue

            if inputMode == .interact {
                if abs(delta) > 0.5 {
                    let wheel: VNCMouseWheel = delta > 0 ? .down : .up
                    session.connection?.mouseWheel(wheel, x: lastMousePosition.x, y: lastMousePosition.y, steps: 1)
                }
            } else {
                let newZoom = max(0.5, min(5.0, zoomScale + delta * 0.05))
                zoomScale = newZoom
                if newZoom <= 1.0 {
                    panOffset = .zero
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            session.connect(hostname: hostname, port: port)
        }
        .onDisappear {
            session.disconnect()
        }
    }

    // MARK: - Toolbar Overlay

    private var toolbarOverlay: some View {
        ZStack {
            // Dismiss background
            Color.black.opacity(0.5)
                .onTapGesture { showingToolbar = false }

            VStack(spacing: 8) {
                Spacer()

                // Toolbar buttons
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        toolbarButton(
                            icon: inputMode == .interact ? "hand.draw" : "cursorarrow",
                            label: inputMode == .interact ? "Pan" : "Pointer"
                        ) {
                            inputMode = inputMode == .interact ? .navigate : .interact
                            showingToolbar = false
                        }

                        toolbarButton(icon: "keyboard", label: "Keyboard") {
                            showingToolbar = false
                            showingKeyboard = true
                        }
                    }

                    HStack(spacing: 8) {
                        toolbarButton(icon: "escape", label: "Esc") {
                            sendKey(.escape)
                            showingToolbar = false
                        }

                        toolbarButton(icon: "return.left", label: "Return") {
                            sendKey(.return)
                            showingToolbar = false
                        }
                    }

                    HStack(spacing: 8) {
                        toolbarButton(icon: "delete.backward", label: "Delete") {
                            sendKey(.delete)
                            showingToolbar = false
                        }

                        toolbarButton(icon: "tab", label: "Tab") {
                            sendKey(.tab)
                            showingToolbar = false
                        }
                    }

                    HStack(spacing: 8) {
                        toolbarButton(icon: "power", label: "Ctrl+Alt+Del") {
                            sendCtrlAltDel()
                            showingToolbar = false
                        }

                        toolbarButton(icon: "xmark.circle", label: "Disconnect") {
                            showingToolbar = false
                            session.disconnect()
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.body)
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Key Sending

    private func sendKey(_ key: VNCKeyCode) {
        session.connection?.keyDown(key)
        session.connection?.keyUp(key)
    }

    private func sendCtrlAltDel() {
        session.connection?.keyDown(.control)
        session.connection?.keyDown(.option)
        session.connection?.keyDown(.forwardDelete)
        session.connection?.keyUp(.forwardDelete)
        session.connection?.keyUp(.option)
        session.connection?.keyUp(.control)
    }

    // MARK: - Gestures

    private var swipeUpGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                if value.translation.height < -30 && abs(value.translation.width) < 50 {
                    showingToolbar = true
                }
            }
    }

    private func doubleTapGesture(in geometry: GeometryProxy, frameSize: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                if inputMode == .interact {
                    let vncPoint = viewToVNC(point: value.location, viewSize: geometry.size, frameSize: frameSize)
                    lastMousePosition = vncPoint
                    session.connection?.mouseButtonDown(.left, x: vncPoint.x, y: vncPoint.y)
                    session.connection?.mouseButtonUp(.left, x: vncPoint.x, y: vncPoint.y)
                    session.connection?.mouseButtonDown(.left, x: vncPoint.x, y: vncPoint.y)
                    session.connection?.mouseButtonUp(.left, x: vncPoint.x, y: vncPoint.y)
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if isZoomedIn {
                            zoomScale = 1.0
                            panOffset = .zero
                            isZoomedIn = false
                        } else {
                            zoomScale = 2.5
                            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            panOffset.width = (center.x - value.location.x) * 1.5
                            panOffset.height = (center.y - value.location.y) * 1.5
                            isZoomedIn = true
                        }
                    }
                }
            }
    }

    private func singleTapGesture(in geometry: GeometryProxy, frameSize: CGSize) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                let vncPoint = viewToVNC(point: value.location, viewSize: geometry.size, frameSize: frameSize)
                lastMousePosition = vncPoint
                session.connection?.mouseButtonDown(.left, x: vncPoint.x, y: vncPoint.y)
                session.connection?.mouseButtonUp(.left, x: vncPoint.x, y: vncPoint.y)
            }
    }

    private func longPressGesture(in geometry: GeometryProxy, frameSize: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: SpatialTapGesture())
            .onEnded { value in
                guard inputMode == .interact else { return }
                switch value {
                case .second(true, let tap):
                    if let tap {
                        let vncPoint = viewToVNC(point: tap.location, viewSize: geometry.size, frameSize: frameSize)
                        lastMousePosition = vncPoint
                        session.connection?.mouseButtonDown(.right, x: vncPoint.x, y: vncPoint.y)
                        session.connection?.mouseButtonUp(.right, x: vncPoint.x, y: vncPoint.y)
                    }
                default:
                    break
                }
            }
    }

    private func dragGesture(in geometry: GeometryProxy, frameSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if inputMode == .interact {
                    let vncPoint = viewToVNC(point: value.location, viewSize: geometry.size, frameSize: frameSize)
                    lastMousePosition = vncPoint
                    session.connection?.mouseMove(x: vncPoint.x, y: vncPoint.y)
                } else {
                    if let lastPos = lastDragPosition {
                        let dx = value.location.x - lastPos.x
                        let dy = value.location.y - lastPos.y
                        panOffset.width += dx
                        panOffset.height += dy
                    }
                }
                lastDragPosition = value.location
            }
            .onEnded { _ in
                lastDragPosition = nil
            }
    }

    // MARK: - Coordinate Mapping

    private func viewToVNC(point: CGPoint, viewSize: CGSize, frameSize: CGSize) -> (x: UInt16, y: UInt16) {
        let imageAspect = frameSize.width / frameSize.height
        let viewAspect = viewSize.width / viewSize.height

        var displayWidth: CGFloat
        var displayHeight: CGFloat

        if imageAspect > viewAspect {
            displayWidth = viewSize.width
            displayHeight = viewSize.width / imageAspect
        } else {
            displayHeight = viewSize.height
            displayWidth = viewSize.height * imageAspect
        }

        displayWidth *= zoomScale
        displayHeight *= zoomScale

        let originX = (viewSize.width - displayWidth) / 2 + panOffset.width
        let originY = (viewSize.height - displayHeight) / 2 + panOffset.height

        let normalizedX = (point.x - originX) / displayWidth
        let normalizedY = (point.y - originY) / displayHeight

        let vncX = UInt16(max(0, min(frameSize.width - 1, normalizedX * frameSize.width)))
        let vncY = UInt16(max(0, min(frameSize.height - 1, normalizedY * frameSize.height)))

        return (vncX, vncY)
    }
}

// MARK: - Keyboard Input

struct KeyboardInputView: View {
    @ObservedObject var session: VNCSession
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            TextField("Type here...", text: $text)
                .focused($isFocused)
                .disableAutocorrection(true)
                .onChange(of: text) { newValue in
                    sendNewCharacters(old: String(text.dropLast(max(0, newValue.count - text.count + 1))), new: newValue)
                }
                .onSubmit {
                    sendKey(.return)
                }

            HStack(spacing: 8) {
                Button("Esc") { sendKey(.escape) }
                    .font(.caption)
                Button("Tab") { sendKey(.tab) }
                    .font(.caption)
                Button("Del") { sendKey(.delete) }
                    .font(.caption)
            }
        }
        .padding()
        .onAppear {
            isFocused = true
        }
    }

    private func sendNewCharacters(old: String, new: String) {
        if new.count < old.count {
            // Characters were deleted
            let deletions = old.count - new.count
            for _ in 0..<deletions {
                sendKey(.delete)
            }
        } else if new.count > old.count {
            // Characters were added
            let addedChars = new.suffix(new.count - old.count)
            for char in addedChars {
                let keyCodes = VNCKeyCode.withCharacter(char)
                for keyCode in keyCodes {
                    session.connection?.keyDown(keyCode)
                    session.connection?.keyUp(keyCode)
                }
            }
        }
    }

    private func sendKey(_ key: VNCKeyCode) {
        session.connection?.keyDown(key)
        session.connection?.keyUp(key)
    }
}

// MARK: - Credential Prompt

struct CredentialPromptView: View {
    @ObservedObject var session: VNCSession
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        Form {
            if session.needsUsername {
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
            }

            Section {
                SecureField("Password", text: $password)
            }

            Button("Sign In") {
                session.submitCredentials(username: username, password: password)
            }
            .disabled(password.isEmpty || (session.needsUsername && username.isEmpty))
        }
        .navigationTitle("Sign In")
        .onAppear {
            if let saved = CredentialStore.load(host: session.connectHostname, port: session.connectPort) {
                username = saved.username
            }
        }
    }
}
