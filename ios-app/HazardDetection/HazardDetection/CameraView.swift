import SwiftUI
import AVFoundation
import Vision

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraView: View {
    @ObservedObject var cameraManager: CameraManager
    var overlays: [TrackedOverlay]? = nil

    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.captureSession)
                .ignoresSafeArea()

            BoundingBoxOverlay(
                overlays: overlays ?? cameraManager.detectedHazards.enumerated().map { index, hazard in
                    TrackedOverlay(
                        id: index,
                        label: hazard.label,
                        state: .confirmed,
                        age: 0,
                        currentBoundingBox: hazard.boundingBox,
                        targetBoundingBox: hazard.boundingBox,
                        confidence: hazard.confidence
                    )
                },
                imageSize: cameraManager.latestFrameSize
            )
                .ignoresSafeArea()
        }
    }
}

// MARK: - UIViewRepresentable wrapper

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        return view
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    var session: AVCaptureSession? {
        get { previewLayer.session }
        set {
            previewLayer.session = newValue
            previewLayer.videoGravity = .resizeAspectFill
        }
    }
}

// MARK: - Bounding Box Overlay

struct BoundingBoxOverlay: View {
    let overlays: [TrackedOverlay]
    let imageSize: CGSize?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ForEach(overlays) { hazard in
                let sourceSize = imageSize ?? CGSize(width: 480, height: 640)
                let rect = DetectionGeometry.visionRectToAspectFillRect(
                    hazard.currentBoundingBox,
                    imageSize: sourceSize,
                    containerSize: size
                )
                let label = hazard.displayLabel
                let pct   = String(format: "%.0f%%", hazard.confidence * 100)
                let color = hazard.color

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .stroke(color, lineWidth: 2.5)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    // Label badge above the box
                    Text("\(label) \(pct)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(color)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(
                            x: rect.minX + badgeWidth(label, pct) / 2,
                            y: max(rect.minY - 12, 8)
                        )
                }
            }
        }
    }

    private func badgeWidth(_ label: String, _ pct: String) -> CGFloat {
        CGFloat("\(label) \(pct)".count) * 7 + 10
    }
}
