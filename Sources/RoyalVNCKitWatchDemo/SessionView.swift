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

                // Mode indicator
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
            }
        }
        .sheet(isPresented: $session.showingCredentialPrompt) {
            CredentialPromptView(session: session)
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
                // Scroll wheel
                if abs(delta) > 0.5 {
                    let wheel: VNCMouseWheel = delta > 0 ? .down : .up
                    session.connection?.mouseWheel(wheel, x: lastMousePosition.x, y: lastMousePosition.y, steps: 1)
                }
            } else {
                // Zoom
                let newZoom = max(0.5, min(5.0, zoomScale + delta * 0.05))
                zoomScale = newZoom
                if newZoom <= 1.0 {
                    panOffset = .zero
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    toggleMode()
                } label: {
                    Image(systemName: inputMode == .interact ? "hand.draw" : "cursorarrow")
                }
            }
        }
        .onAppear {
            session.connect(hostname: hostname, port: port)
        }
        .onDisappear {
            session.disconnect()
        }
        .navigationBarBackButtonHidden(session.status == .connecting)
    }

    private func toggleMode() {
        inputMode = inputMode == .interact ? .navigate : .interact
    }

    // MARK: - Gestures

    // Double tap: interact = double click, navigate = zoom toggle
    private func doubleTapGesture(in geometry: GeometryProxy, frameSize: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                if inputMode == .interact {
                    let vncPoint = viewToVNC(point: value.location, viewSize: geometry.size, frameSize: frameSize)
                    lastMousePosition = vncPoint
                    // Double click
                    session.connection?.mouseButtonDown(.left, x: vncPoint.x, y: vncPoint.y)
                    session.connection?.mouseButtonUp(.left, x: vncPoint.x, y: vncPoint.y)
                    session.connection?.mouseButtonDown(.left, x: vncPoint.x, y: vncPoint.y)
                    session.connection?.mouseButtonUp(.left, x: vncPoint.x, y: vncPoint.y)
                } else {
                    // Zoom toggle
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if isZoomedIn {
                            zoomScale = 1.0
                            panOffset = .zero
                            isZoomedIn = false
                        } else {
                            zoomScale = 2.5
                            // Center zoom on tap point
                            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            panOffset.width = (center.x - value.location.x) * 1.5
                            panOffset.height = (center.y - value.location.y) * 1.5
                            isZoomedIn = true
                        }
                    }
                }
            }
    }

    // Single tap: left click in both modes
    private func singleTapGesture(in geometry: GeometryProxy, frameSize: CGSize) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                let vncPoint = viewToVNC(point: value.location, viewSize: geometry.size, frameSize: frameSize)
                lastMousePosition = vncPoint
                session.connection?.mouseButtonDown(.left, x: vncPoint.x, y: vncPoint.y)
                session.connection?.mouseButtonUp(.left, x: vncPoint.x, y: vncPoint.y)
            }
    }

    // Long press: interact = right click
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

    // Drag: interact = move mouse, navigate = pan viewport
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
