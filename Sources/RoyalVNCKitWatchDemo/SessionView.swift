import SwiftUI
import RoyalVNCKit

struct SessionView: View {
    let hostname: String
    let port: UInt16
    let username: String
    let password: String

    @StateObject private var session = VNCSession()
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastDragPosition: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let cgImage = session.currentFrame {
                    let image = Image(cgImage, scale: 1.0, label: Text("VNC"))

                    image
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                        .gesture(dragGesture(in: geometry, frameSize: CGSize(
                            width: cgImage.width,
                            height: cgImage.height
                        )))
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
            }
        }
        .focusable()
        .digitalCrownRotation(
            $zoomScale,
            from: 0.5,
            through: 5.0,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            session.connect(
                hostname: hostname,
                port: port,
                username: username,
                password: password
            )
        }
        .onDisappear {
            session.disconnect()
        }
        .navigationBarBackButtonHidden(session.status == .connecting)
    }

    private func dragGesture(in geometry: GeometryProxy, frameSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if let lastPos = lastDragPosition {
                    // Pan when zoomed in
                    if zoomScale > 1.0 {
                        let dx = value.location.x - lastPos.x
                        let dy = value.location.y - lastPos.y
                        panOffset.width += dx
                        panOffset.height += dy
                    }
                }
                lastDragPosition = value.location

                // Send mouse move to VNC server
                let vncPoint = viewToVNC(
                    point: value.location,
                    viewSize: geometry.size,
                    frameSize: frameSize
                )
                session.connection?.mouseMove(x: vncPoint.x, y: vncPoint.y)
            }
            .onEnded { value in
                // Send tap as click
                let vncPoint = viewToVNC(
                    point: value.location,
                    viewSize: geometry.size,
                    frameSize: frameSize
                )

                let distance = hypot(
                    value.location.x - value.startLocation.x,
                    value.location.y - value.startLocation.y
                )

                if distance < 5 {
                    session.connection?.mouseButtonDown(.left, x: vncPoint.x, y: vncPoint.y)
                    session.connection?.mouseButtonUp(.left, x: vncPoint.x, y: vncPoint.y)
                }

                lastDragPosition = nil
            }
    }

    private func viewToVNC(point: CGPoint, viewSize: CGSize, frameSize: CGSize) -> (x: UInt16, y: UInt16) {
        // Account for aspect-fit scaling, zoom, and pan offset
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
