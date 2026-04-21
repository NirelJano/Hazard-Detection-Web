import SwiftUI
import Vision
import AVFoundation

struct LiveDetectionView: View {
    @ObservedObject var cameraManager: CameraManager
    @EnvironmentObject private var app: AppController
    @Environment(\.dismiss) var dismiss
    @State private var tracker = DetectionTracker()

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen camera + bounding boxes
            CameraView(cameraManager: cameraManager)
                .ignoresSafeArea()

            // Close button
            VStack {
                HStack {
                    Button(action: {
                        cameraManager.stopSession()
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.6))
                            .padding()
                    }
                    Spacer()
                }
                Spacer()
            }

            HUDView(hazardCount: cameraManager.detectedHazards.count, message: app.liveMessage)
        }
        .onAppear  {
            app.locationService.requestPermission()
            Task {
                // Request camera permission on first appear
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                if status == .notDetermined {
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    if granted { cameraManager.startSession() }
                } else if status == .authorized {
                    cameraManager.startSession()
                } else {
                    app.liveMessage = "Camera access is denied. Enable it in Settings."
                }
            }
        }
        .onReceive(cameraManager.$detectedHazards) { hazards in
            handle(hazards)
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .navigationBarHidden(true)
    }

    private func handle(_ hazards: [VNRecognizedObjectObservation]) {
        let candidates = hazards.compactMap { observation -> DetectionCandidate? in
            guard let label = observation.labels.first?.identifier else { return nil }
            return DetectionCandidate(label: label, confidence: observation.confidence, boundingBox: observation.boundingBox)
        }
        if let report = tracker.update(with: candidates) {
            app.submitLiveReport(
                label: report.label,
                boundingBox: report.boundingBox,
                image: cameraManager.snapshotImage()
            )
        }
    }
}

// MARK: - HUD

private struct HUDView: View {
    let hazardCount: Int
    let message: String?

    private var statusColor: Color { hazardCount == 0 ? .appSuccess : .appDanger }

    private var statusText: String {
        hazardCount == 0
            ? "No Hazards Detected"
            : "\(hazardCount) Hazard\(hazardCount > 1 ? "s" : "") Detected"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.8), radius: 6)
                    .animation(.easeInOut(duration: 0.3), value: hazardCount)

                Text(statusText)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(statusColor.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        .padding(.bottom, 48)
    }
}
