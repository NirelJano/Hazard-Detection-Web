import SwiftUI
import Vision
import AVFoundation

struct LiveDetectionView: View {
    @ObservedObject var cameraManager: CameraManager
    @EnvironmentObject private var app: AppController
    @State private var tracker = DetectionTracker()
    @State private var isDetecting = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen camera + bounding boxes
            CameraView(cameraManager: cameraManager)
                .ignoresSafeArea()

            VStack {
                Spacer()
                
                // HUD
                EnhancedHUDView(
                    isDetecting: isDetecting,
                    hazardCount: cameraManager.detectedHazards.count,
                    message: app.liveMessage,
                    location: app.locationService.currentCoordinate != nil ? "GPS Active" : "Searching GPS..."
                )
                
                // Controls
                HStack(spacing: 24) {
                    Button(action: {
                        toggleDetection()
                    }) {
                        Text(isDetecting ? "Stop Detection" : "Start Detection")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 24)
                            .background(isDetecting ? Color.appDanger : Color.appSuccess)
                            .clipShape(Capsule())
                            .shadow(radius: 4)
                    }
                }
                .padding(.bottom, 24)
            }
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
            if isDetecting {
                handle(hazards)
            }
        }
        .onDisappear {
            isDetecting = false
            cameraManager.stopSession()
        }
        .preferredColorScheme(.dark)
    }

    private func toggleDetection() {
        isDetecting.toggle()
        if isDetecting {
            app.liveMessage = "Detection started."
        } else {
            app.liveMessage = "Detection stopped."
        }
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

private struct EnhancedHUDView: View {
    let isDetecting: Bool
    let hazardCount: Int
    let message: String?
    let location: String

    private var statusColor: Color { 
        if !isDetecting { return .appDark400 }
        return hazardCount == 0 ? .appSuccess : .appDanger 
    }

    private var statusText: String {
        if !isDetecting { return "Standby" }
        return hazardCount == 0
            ? "No Hazards"
            : "\(hazardCount) Hazard\(hazardCount > 1 ? "s" : "")"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                // Status Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor.opacity(0.8), radius: 4)

                    Text(statusText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
                
                Divider()
                    .frame(height: 12)
                    .background(Color.white.opacity(0.3))
                
                // Location Indicator
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10))
                        .foregroundColor(location == "GPS Active" ? .appPrimary : .appWarning)
                    Text(location)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
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
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .padding(.bottom, 16)
    }
}
