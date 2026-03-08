#if os(tvOS)
import SwiftUI
import RoyalVNCKit
import GameController

struct SessionView: View {
    let hostname: String
    let port: UInt16

    @StateObject private var session = VNCSession()
    @State private var cursorX: CGFloat = 0.5 // Normalized 0-1
    @State private var cursorY: CGFloat = 0.5
    @State private var showingToolbar = false
    @State private var showingKeyboard = false

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

                    // Cursor overlay
                    if session.status == .connected {
                        cursorOverlay(viewSize: geometry.size, frameSize: frameSize)
                    }
                }

                if session.status == .connecting {
                    ProgressView("Connecting...")
                        .font(.title2)
                }

                if let error = session.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                        Text(error)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .sheet(isPresented: $session.showingCredentialPrompt) {
            CredentialPromptView(session: session)
        }
        .sheet(isPresented: $showingToolbar) {
            ToolbarView(session: session, showingKeyboard: $showingKeyboard)
        }
        .sheet(isPresented: $showingKeyboard) {
            KeyboardInputView(session: session)
        }
        .onAppear {
            session.connect(hostname: hostname, port: port)
            setupRemoteInput()
        }
        .onDisappear {
            session.disconnect()
            teardownRemoteInput()
        }
        .onPlayPauseCommand {
            showingToolbar = true
        }
        .focusable()
    }

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

        let originX = (viewSize.width - displayWidth) / 2
        let originY = (viewSize.height - displayHeight) / 2

        let screenX = originX + cursorX * displayWidth
        let screenY = originY + cursorY * displayHeight

        return Circle()
            .fill(.white)
            .frame(width: 12, height: 12)
            .shadow(color: .black, radius: 2)
            .position(x: screenX, y: screenY)
            .allowsHitTesting(false)
    }

    // MARK: - Remote Input

    private func setupRemoteInput() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { notification in
            if let controller = notification.object as? GCController {
                configureController(controller)
            }
        }

        // Configure already-connected controllers
        for controller in GCController.controllers() {
            configureController(controller)
        }
    }

    private func teardownRemoteInput() {
        NotificationCenter.default.removeObserver(self, name: .GCControllerDidConnect, object: nil)
    }

    private func configureController(_ controller: GCController) {
        guard let micro = controller.microGamepad else { return }

        // Trackpad for mouse movement
        micro.dpad.valueChangedHandler = { [self] _, xValue, yValue in
            let baseSensitivity: CGFloat = 0.015
            let sensitivity = baseSensitivity * CGFloat(ConnectionSettings.shared.cursorSensitivity)

            cursorX = max(0, min(1, cursorX + CGFloat(xValue) * sensitivity))
            cursorY = max(0, min(1, cursorY - CGFloat(yValue) * sensitivity))

            if let framebuffer = session.connection?.framebuffer {
                let vncX = UInt16(cursorX * CGFloat(framebuffer.size.width))
                let vncY = UInt16(cursorY * CGFloat(framebuffer.size.height))
                session.connection?.mouseMove(x: vncX, y: vncY)
            }
        }

        // Button A (click/select) = left click
        micro.buttonA.pressedChangedHandler = { [self] _, _, pressed in
            guard let framebuffer = session.connection?.framebuffer else { return }
            let vncX = UInt16(cursorX * CGFloat(framebuffer.size.width))
            let vncY = UInt16(cursorY * CGFloat(framebuffer.size.height))

            if pressed {
                session.connection?.mouseButtonDown(.left, x: vncX, y: vncY)
            } else {
                session.connection?.mouseButtonUp(.left, x: vncX, y: vncY)
            }
        }

        // Button X = right click
        micro.buttonX.pressedChangedHandler = { [self] _, _, pressed in
            guard let framebuffer = session.connection?.framebuffer else { return }
            let vncX = UInt16(cursorX * CGFloat(framebuffer.size.width))
            let vncY = UInt16(cursorY * CGFloat(framebuffer.size.height))

            if pressed {
                session.connection?.mouseButtonDown(.right, x: vncX, y: vncY)
            } else {
                session.connection?.mouseButtonUp(.right, x: vncX, y: vncY)
            }
        }

        // Menu button = toggle toolbar
        micro.buttonMenu.pressedChangedHandler = { [self] _, _, pressed in
            if pressed {
                showingToolbar = true
            }
        }
    }
}

// MARK: - Toolbar

struct ToolbarView: View {
    @ObservedObject var session: VNCSession
    @Binding var showingKeyboard: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    dismiss()
                    showingKeyboard = true
                } label: {
                    Label("Keyboard", systemImage: "keyboard")
                }

                Button {
                    sendKey(.escape)
                    dismiss()
                } label: {
                    Label("Escape", systemImage: "escape")
                }

                Button {
                    sendKey(.return)
                    dismiss()
                } label: {
                    Label("Return", systemImage: "return.left")
                }

                Button {
                    sendKey(.delete)
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "delete.backward")
                }

                Button {
                    sendKey(.tab)
                    dismiss()
                } label: {
                    Label("Tab", systemImage: "tab")
                }

                Button {
                    sendCtrlAltDel()
                    dismiss()
                } label: {
                    Label("Ctrl + Alt + Del", systemImage: "power")
                }

                Button(role: .destructive) {
                    session.disconnect()
                    dismiss()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            }
            .navigationTitle("Actions")
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
    @State private var text = ""
    @State private var previousText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Type text to send to the remote computer")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                TextField("Type here...", text: $text)
                    .onChange(of: text) { newValue in
                        handleTextChange(from: previousText, to: newValue)
                        previousText = newValue
                    }
                    .onSubmit {
                        sendKey(.return)
                    }
            }
            .padding()
            .navigationTitle("Keyboard")
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
