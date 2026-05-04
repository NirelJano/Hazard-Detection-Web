import SwiftUI
import AVFoundation
import os
import Vision

private let previewLogger = Logger(subsystem: "com.hazarddetection", category: "CameraPreview")

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraView: View {
    @ObservedObject var cameraManager: CameraManager
    var overlays: [TrackedOverlay]? = nil
    var debugMode: Bool = false
    /// Called with the normalized AVCapture point (0–1 range) when the user taps the preview.
    var onTapToFocus: ((CGPoint) -> Void)? = nil

    @State private var focusIndicatorPoint: CGPoint? = nil
    @State private var focusIndicatorVisible: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: cameraManager.captureSession) { angle in
                    cameraManager.setOutputRotationAngle(angle)
                }
                .ignoresSafeArea()
                .zIndex(0)
                .onTapGesture { location in
                    handleTap(at: location, containerSize: geo.size)
                }

                BoundingBoxOverlay(
                    overlays: overlays ?? cameraManager.detectedHazards.enumerated().map { index, hazard in
                        TrackedOverlay(
                            id: index,
                            label: hazard.label,
                            state: .confirmed,
                            age: 0,
                            currentBoundingBox: hazard.boundingBox,
                            targetBoundingBox: hazard.boundingBox,
                            confidence: hazard.confidence,
                            isFresh: true
                        )
                    },
                    imageSize: cameraManager.latestFrameSize,
                    debugMode: debugMode
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(1)

                if focusIndicatorVisible, let point = focusIndicatorPoint {
                    FocusIndicatorView()
                        .position(point)
                        .allowsHitTesting(false)
                        .zIndex(2)
                }
            }
        }
    }

    private func handleTap(at screenPoint: CGPoint, containerSize: CGSize) {
        guard containerSize.width > 0, containerSize.height > 0 else { return }
        // Convert screen coordinates to normalized AVCapture coordinates.
        // videoGravity is .resizeAspectFill and videoRotationAngle=90 is enforced,
        // so portrait screen (x,y) maps directly to capture (x,y) normalized.
        let avPoint = CGPoint(
            x: screenPoint.x / containerSize.width,
            y: screenPoint.y / containerSize.height
        )
        focusIndicatorPoint = screenPoint
        withAnimation(.easeIn(duration: 0.1)) { focusIndicatorVisible = true }
        withAnimation(.easeOut(duration: 0.4).delay(1.2)) { focusIndicatorVisible = false }
        onTapToFocus?(avPoint)
    }
}

// MARK: - Focus Indicator

struct FocusIndicatorView: View {
    @State private var scale: CGFloat = 1.3

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 60, height: 60)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { scale = 1.0 }
            }
    }
}

// MARK: - UIViewRepresentable wrapper

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onRotationAngleChange: ((CGFloat) -> Void)? = nil

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.onRotationAngleChange = onRotationAngleChange
        view.setSession(session)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onRotationAngleChange = onRotationAngleChange
        uiView.setSession(session)
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var onRotationAngleChange: ((CGFloat) -> Void)?
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    func setSession(_ session: AVCaptureSession) {
        if previewLayer.session !== session {
            previewLayer.session = session
            previewLogger.info(
                "Preview layer attached session: \(self.previewLayer.session != nil, privacy: .public), inputs: \(session.inputs.count, privacy: .public), outputs: \(session.outputs.count, privacy: .public), running: \(session.isRunning, privacy: .public)"
            )
        }
        previewLayer.videoGravity = .resizeAspectFill
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        previewLogger.info(
            "Preview moved to window: \(self.window != nil, privacy: .public), session attached: \(self.previewLayer.session != nil, privacy: .public), connection attached: \(self.previewLayer.connection != nil, privacy: .public)"
        )
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        let angle = interfaceRotationAngle()
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
            previewLogger.debug("Preview rotation angle set: \(angle, privacy: .public)")
        } else {
            previewLogger.debug(
                "Preview connection unavailable or unsupported. session attached: \(self.previewLayer.session != nil, privacy: .public), bounds: \(String(describing: self.bounds), privacy: .public)"
            )
        }
        // Notify CameraManager so the video output delivers frames in the same
        // orientation as the preview.  Called on every layout pass (initial +
        // every device rotation), keeping both connections in lockstep.
        onRotationAngleChange?(angle)
    }

    // Maps the current interface orientation to the AVCapture rotation angle.
    // Using interface orientation avoids the faceUp/faceDown/unknown cases of
    // UIDeviceOrientation and correctly handles the landscapeLeft ↔ Right inversion.
    private func interfaceRotationAngle() -> CGFloat {
        guard let scene = window?.windowScene ?? UIApplication.shared.connectedScenes
            .first(where: { $0 is UIWindowScene }) as? UIWindowScene else { return 90 }
        switch scene.interfaceOrientation {
        case .portrait:           return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft:      return 180
        case .landscapeRight:     return 0
        case .unknown:            return 90
        @unknown default:         return 90
        }
    }
}

// MARK: - Bounding Box Overlay

struct BoundingBoxOverlay: View {
    let overlays: [TrackedOverlay]
    let imageSize: CGSize?
    var debugMode: Bool = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ForEach(overlays) { hazard in
                let sourceSize = imageSize ?? CGSize(width: 720, height: 1280)
                let rect = DetectionGeometry.visionRectToAspectFillRect(
                    hazard.currentBoundingBox,
                    imageSize: sourceSize,
                    containerSize: size
                )
                let label = hazard.displayLabel
                let pct   = String(format: "%.0f%%", hazard.confidence * 100)
                let color = hazard.color
                let badgeText = debugMode && !hazard.isFresh
                    ? "\(label) \(pct) [\(hazard.age)]"
                    : "\(label) \(pct)"

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .stroke(color, lineWidth: 2.5)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    // Label badge above the box
                    Text(badgeText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(color)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(
                            x: rect.minX + badgeWidth(badgeText) / 2,
                            y: max(rect.minY - 12, 8)
                        )
                }
            }
        }
    }

    private func badgeWidth(_ text: String) -> CGFloat {
        CGFloat(text.count) * 7 + 10
    }
}
