import SwiftUI
import AVFoundation
import Vision

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraView: View {
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.captureSession)
                .ignoresSafeArea()

            BoundingBoxOverlay(hazards: cameraManager.detectedHazards)
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
    let hazards: [VNRecognizedObjectObservation]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ForEach(Array(hazards.enumerated()), id: \.offset) { _, hazard in
                let rect = visionRectToScreen(hazard.boundingBox, size: size)
                let label = hazard.labels.first?.identifier ?? "Hazard"
                let pct   = String(format: "%.0f%%", hazard.confidence * 100)

                ZStack(alignment: .topLeading) {
                    // Green bounding box
                    Rectangle()
                        .stroke(Color.green, lineWidth: 2.5)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    // Label badge above the box
                    Text("\(label) \(pct)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(
                            x: rect.minX + badgeWidth(label, pct) / 2,
                            y: max(rect.minY - 12, 8)
                        )
                }
            }
        }
    }

    /// Converts Vision normalised rect (origin = bottom-left) to SwiftUI screen coords (origin = top-left)
    private func visionRectToScreen(_ vRect: CGRect, size: CGSize) -> CGRect {
        CGRect(
            x:      vRect.minX * size.width,
            y:      (1 - vRect.maxY) * size.height,
            width:  vRect.width  * size.width,
            height: vRect.height * size.height
        )
    }

    private func badgeWidth(_ label: String, _ pct: String) -> CGFloat {
        CGFloat("\(label) \(pct)".count) * 7 + 10
    }
}
