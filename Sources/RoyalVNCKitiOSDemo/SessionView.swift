#if os(iOS)
import SwiftUI
import RoyalVNCKit

enum InputMode: String {
    case direct   // Tap where you want to click
    case trackpad // Drag moves cursor relatively (like a laptop trackpad)
}

struct SessionView: View {
    let hostname: String
    let port: UInt16

    @StateObject private var session = VNCSession()
    @Environment(\.dismiss) private var dismiss

    // Viewport state
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastDragTranslation: CGSize = .zero

    // Cursor position (normalized 0-1)
    @State private var cursorX: CGFloat = 0.5
    @State private var cursorY: CGFloat = 0.5
    @State private var lastMousePosition: (x: UInt16, y: UInt16) = (0, 0)

    // Input mode
    @State private var inputMode: InputMode = .direct

    // UI state
    @State private var showingToolbar = true
    @State private var showingActions = false
    @State private var showingKeyboard = false
    @State private var toolbarAutoHideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let cgImage = session.currentFrame {
                    let frameSize = CGSize(width: cgImage.width, height: cgImage.height)

                    Image(cgImage, scale: 1.0, label: Text("VNC"))
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                        .gesture(
                            SimultaneousGesture(
                                magnificationGesture,
                                dragGesture(in: geometry, frameSize: frameSize)
                            )
                        )
                        .gesture(
                            doubleTapGesture(in: geometry, frameSize: frameSize)
                        )
                        .gesture(
                            singleTapGesture(in: geometry, frameSize: frameSize)
                        )
                        .gesture(
                            longPressGesture(in: geometry, frameSize: frameSize)
                        )

                    // Cursor overlay (always visible in trackpad mode, visible on drag in direct mode)
                    if session.status == .connected {
                        cursorOverlay(viewSize: geometry.size, frameSize: frameSize)
                    }
                }

                if session.status == .connecting {
                    ProgressView("Connecting...")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

                if let error = session.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                        Text(error)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Button("Dismiss") { dismiss() }
                            .buttonStyle(.bordered)
                    }
                    .foregroundStyle(.red)
                }

                // Floating toolbar (top)
                if showingToolbar && session.status == .connected {
                    VStack {
                        floatingToolbar
                        Spacer()
                        modeIndicator
                    }
                }

                // Swipe-up grab bar hint (bottom center)
                if session.status == .connected && !showingToolbar {
                    VStack {
                        Spacer()
                        Capsule()
                            .fill(.white.opacity(0.4))
                            .frame(width: 40, height: 5)
                            .padding(.bottom, 10)
                    }
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(swipeUpGesture)
            .onTapGesture(count: 3) {
                withAnimation { showingToolbar.toggle() }
                scheduleToolbarHide()
            }
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .sheet(isPresented: $session.showingCredentialPrompt) {
            CredentialPromptView(session: session)
        }
        .sheet(isPresented: $showingKeyboard) {
            KeyboardInputView(session: session)
        }
        .sheet(isPresented: $showingActions) {
            ActionsSheet(session: session, showingKeyboard: $showingKeyboard)
                .presentationDetents([.medium])
        }
        .onAppear {
            session.connect(hostname: hostname, port: port)
            scheduleToolbarHide()
        }
        .onDisappear {
            session.disconnect()
        }
    }

    // MARK: - Floating Toolbar

    private var floatingToolbar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
            }

            Spacer()

            // Input mode toggle
            Button {
                inputMode = inputMode == .direct ? .trackpad : .direct
            } label: {
                Image(systemName: inputMode == .direct ? "hand.tap" : "cursorarrow")
                    .font(.title3)
            }

            Button { showingKeyboard = true } label: {
                Image(systemName: "keyboard")
                    .font(.title3)
            }

            // More actions
            Button { showingActions = true } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 60)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var modeIndicator: some View {
        Text(inputMode == .direct ? "Direct Touch" : "Trackpad")
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .foregroundStyle(.white)
            .padding(.bottom, 40)
            .transition(.opacity)
    }

    private func scheduleToolbarHide() {
        toolbarAutoHideTask?.cancel()
        toolbarAutoHideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                withAnimation { showingToolbar = false }
            }
        }
    }

    // MARK: - Cursor Overlay

    private func cursorOverlay(viewSize: CGSize, frameSize: CGSize) -> some View {
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

        let screenX = originX + cursorX * displayWidth
        let screenY = originY + cursorY * displayHeight

        return Circle()
            .fill(.white)
            .frame(width: 10, height: 10)
            .shadow(color: .black, radius: 2)
            .position(x: screenX, y: screenY)
            .opacity(inputMode == .trackpad ? 1.0 : 0.5)
            .allowsHitTesting(false)
    }

    // MARK: - Gestures

    // Swipe up from bottom to show actions
    private var swipeUpGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                if value.translation.height < -50 && abs(value.translation.width) < 80 {
                    showingActions = true
                }
            }
    }

    // Pinch to zoom
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomScale = max(0.5, min(5.0, value))
            }
            .onEnded { _ in
                if zoomScale < 1.0 {
                    withAnimation { zoomScale = 1.0; panOffset = .zero }
                }
            }
    }

    // Drag: behavior depends on input mode and zoom level
    private func dragGesture(in geometry: GeometryProxy, frameSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if zoomScale > 1.05 && inputMode == .direct {
                    // Pan the viewport when zoomed in direct mode
                    let delta = CGSize(
                        width: value.translation.width - lastDragTranslation.width,
                        height: value.translation.height - lastDragTranslation.height
                    )
                    panOffset.width += delta.width
                    panOffset.height += delta.height
                    lastDragTranslation = value.translation
                } else {
                    // Move cursor relatively (trackpad style)
                    let delta = CGSize(
                        width: value.translation.width - lastDragTranslation.width,
                        height: value.translation.height - lastDragTranslation.height
                    )
                    lastDragTranslation = value.translation

                    let imageAspect = frameSize.width / frameSize.height
                    let viewAspect = geometry.size.width / geometry.size.height
                    let displayWidth: CGFloat
                    let displayHeight: CGFloat

                    if imageAspect > viewAspect {
                        displayWidth = geometry.size.width
                        displayHeight = geometry.size.width / imageAspect
                    } else {
                        displayHeight = geometry.size.height
                        displayWidth = geometry.size.height * imageAspect
                    }

                    // In trackpad mode, drag always moves cursor
                    // In direct mode (not zoomed), drag also moves cursor for precision
                    cursorX = max(0, min(1, cursorX + delta.width / (displayWidth * zoomScale)))
                    cursorY = max(0, min(1, cursorY + delta.height / (displayHeight * zoomScale)))

                    if let framebuffer = session.connection?.framebuffer {
                        let vncX = UInt16(cursorX * CGFloat(framebuffer.size.width))
                        let vncY = UInt16(cursorY * CGFloat(framebuffer.size.height))
                        lastMousePosition = (vncX, vncY)
                        session.connection?.mouseMove(x: vncX, y: vncY)
                    }
                }
            }
            .onEnded { _ in
                lastDragTranslation = .zero
            }
    }

    // Double tap: zoom toggle in direct mode, double-click in trackpad mode
    private func doubleTapGesture(in geometry: GeometryProxy, frameSize: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                if inputMode == .trackpad {
                    // Double click at cursor position
                    session.connection?.mouseButtonDown(.left, x: lastMousePosition.x, y: lastMousePosition.y)
                    session.connection?.mouseButtonUp(.left, x: lastMousePosition.x, y: lastMousePosition.y)
                    session.connection?.mouseButtonDown(.left, x: lastMousePosition.x, y: lastMousePosition.y)
                    session.connection?.mouseButtonUp(.left, x: lastMousePosition.x, y: lastMousePosition.y)
                } else {
                    // Zoom toggle
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if zoomScale > 1.05 {
                            zoomScale = 1.0
                            panOffset = .zero
                        } else {
                            zoomScale = 2.5
                            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            panOffset.width = (center.x - value.location.x) * 1.5
                            panOffset.height = (center.y - value.location.y) * 1.5
                        }
                    }
                }
            }
    }

    // Single tap: click
    private func singleTapGesture(in geometry: GeometryProxy, frameSize: CGSize) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                if inputMode == .direct {
                    // Click at tap location
                    let vncPoint = viewToVNC(point: value.location, viewSize: geometry.size, frameSize: frameSize)
                    lastMousePosition = vncPoint
                    cursorX = CGFloat(vncPoint.x) / frameSize.width
                    cursorY = CGFloat(vncPoint.y) / frameSize.height
                    session.connection?.mouseButtonDown(.left, x: vncPoint.x, y: vncPoint.y)
                    session.connection?.mouseButtonUp(.left, x: vncPoint.x, y: vncPoint.y)
                } else {
                    // Click at cursor position (trackpad mode)
                    session.connection?.mouseButtonDown(.left, x: lastMousePosition.x, y: lastMousePosition.y)
                    session.connection?.mouseButtonUp(.left, x: lastMousePosition.x, y: lastMousePosition.y)
                }
            }
    }

    // Long press = right click
    private func longPressGesture(in geometry: GeometryProxy, frameSize: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: SpatialTapGesture())
            .onEnded { value in
                if case let .second(_, tap) = value, let tap = tap {
                    if inputMode == .direct {
                        let vncPoint = viewToVNC(point: tap.location, viewSize: geometry.size, frameSize: frameSize)
                        lastMousePosition = vncPoint
                        session.connection?.mouseButtonDown(.right, x: vncPoint.x, y: vncPoint.y)
                        session.connection?.mouseButtonUp(.right, x: vncPoint.x, y: vncPoint.y)
                    } else {
                        session.connection?.mouseButtonDown(.right, x: lastMousePosition.x, y: lastMousePosition.y)
                        session.connection?.mouseButtonUp(.right, x: lastMousePosition.x, y: lastMousePosition.y)
                    }
                }
            }
    }

    // MARK: - Coordinate Conversion

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

        let clampedX = max(0, min(1, normalizedX))
        let clampedY = max(0, min(1, normalizedY))

        return (
            UInt16(clampedX * frameSize.width),
            UInt16(clampedY * frameSize.height)
        )
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
}

// MARK: - Actions Sheet

struct ActionsSheet: View {
    @ObservedObject var session: VNCSession
    @Binding var showingKeyboard: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Special Keys") {
                    actionRow(icon: "escape", title: "Escape") {
                        sendKey(.escape)
                        dismiss()
                    }
                    actionRow(icon: "return.left", title: "Return") {
                        sendKey(.return)
                        dismiss()
                    }
                    actionRow(icon: "delete.backward", title: "Delete") {
                        sendKey(.delete)
                        dismiss()
                    }
                    actionRow(icon: "tab", title: "Tab") {
                        sendKey(.tab)
                        dismiss()
                    }
                    actionRow(icon: "space", title: "Space") {
                        sendKey(.space)
                        dismiss()
                    }
                }

                Section("Combinations") {
                    actionRow(icon: "power", title: "Ctrl + Alt + Del") {
                        sendCtrlAltDel()
                        dismiss()
                    }
                }

                Section {
                    Button(role: .destructive) {
                        session.disconnect()
                        dismiss()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
            }
            .navigationTitle("Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func actionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
    }

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
}

// MARK: - Keyboard Input

struct KeyboardInputView: View {
    @ObservedObject var session: VNCSession
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var previousText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Type text to send to the remote computer")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                TextField("Type here...", text: $text)
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: text) { newValue in
                        handleTextChange(from: previousText, to: newValue)
                        previousText = newValue
                    }
                    .onSubmit {
                        sendKey(.return)
                    }

                HStack(spacing: 12) {
                    Button("Esc") { sendKey(.escape) }
                        .buttonStyle(.bordered)
                    Button("Tab") { sendKey(.tab) }
                        .buttonStyle(.bordered)
                    Button("Del") { sendKey(.delete) }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle("Keyboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private func handleTextChange(from old: String, to new: String) {
        if new.count < old.count {
            let deletions = old.count - new.count
            for _ in 0..<deletions {
                sendKey(.delete)
            }
        } else if new.count > old.count {
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
        NavigationStack {
            Form {
                if session.needsUsername {
                    Section("Username") {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section("Password") {
                    SecureField("Password", text: $password)
                }

                Section {
                    Button("Sign In") {
                        session.submitCredentials(username: username, password: password)
                    }
                    .disabled(password.isEmpty || (session.needsUsername && username.isEmpty))
                }
            }
            .navigationTitle("Sign In")
            .onAppear {
                if let saved = CredentialStore.load(host: session.connectHostname, port: session.connectPort) {
                    username = saved.username
                }
            }
        }
    }
}
#endif
