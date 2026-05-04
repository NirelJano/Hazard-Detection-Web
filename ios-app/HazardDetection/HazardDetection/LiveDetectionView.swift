import AVFoundation
import os
import Photos
import SwiftUI
import Vision

private let liveLogger = Logger(subsystem: "com.hazarddetection", category: "LiveDetection")

struct LiveDetectionView: View {
    @ObservedObject var cameraManager: CameraManager
    @EnvironmentObject private var app: AppController
    @StateObject private var autoReporter = LiveAutoReportCoordinator()
    @State private var tracker = DetectionTracker()
    @State private var isDetecting = false
    @State private var useTracking = false
    @State private var overlays: [TrackedOverlay] = []
    @State private var previousHazardCount = 0
    @State private var isSavingCapture = false
    @State private var captureFlash = false
    @State private var pipSourceView: UIView? = nil
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen camera + bounding boxes + tap-to-focus
            CameraView(
                cameraManager: cameraManager,
                overlays: overlays,
                debugMode: useTracking,
                onTapToFocus: { normalizedPoint in
                    cameraManager.setFocusAndExposure(at: normalizedPoint)
                    app.roadAttentionService.update(
                        userTap: normalizedPoint,
                        frameSize: cameraManager.latestFrameSize ?? CGSize(width: 720, height: 1280),
                        pitch: app.motionService.pitch,
                        roll: app.motionService.roll,
                        stableDetections: cameraManager.detectedHazards
                    )
                }
            )
            .overlay(
                PiPSourceViewCapture { view in pipSourceView = view }
                    .frame(width: 0, height: 0),
                alignment: .topLeading
            )
            .ignoresSafeArea()
            .zIndex(0)

            // White flash overlay on capture
            if captureFlash {
                Color.white.opacity(0.6)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(2)
            }

            VStack {
                Spacer()

                // Quality hint banner
                if let hint = app.pipeline.qualityHint {
                    QualityHintBanner(hint: hint)
                        .padding(.horizontal, 20)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                EnhancedHUDView(
                    isDetecting: isDetecting,
                    hazardCount: cameraManager.detectedHazards.count,
                    message: liveStatusMessage,
                    location: app.locationService.currentCoordinate != nil ? "GPS Active" : "Searching GPS...",
                    speedKmh: speedKmh,
                    fps: cameraManager.fps,
                    autoSaveEnabled: autoReporter.isAutoSaveEnabled,
                    autoState: autoReporter.state,
                    currentCandidate: autoReporter.currentCandidate,
                    reportsSavedCount: autoReporter.reportsSavedCount
                )

                // Lens switcher — only shown when multiple cameras are available
                if cameraManager.availableLenses.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(cameraManager.availableLenses) { lens in
                            Button { cameraManager.switchLens(to: lens) } label: {
                                Text(lens.rawValue)
                                    .font(.system(size: 13, weight: cameraManager.currentLens == lens ? .bold : .regular))
                                    .foregroundColor(cameraManager.currentLens == lens ? .black : .white)
                                    .frame(width: 44, height: 44)
                                    .background(cameraManager.currentLens == lens ? Color.yellow : Color.black.opacity(0.55))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: cameraManager.currentLens)
                    .padding(.bottom, 6)
                }

                VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        // Raw/Track toggle — switches between direct model output and tracker
                        Button {
                            useTracking.toggle()
                            overlays = []
                            tracker.reset()
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: useTracking ? "eye.fill" : "eye.slash.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text(useTracking ? "Track" : "Raw")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(useTracking ? Color.appPrimary.opacity(0.8) : Color.appDark900)
                            .clipShape(Circle())
                        }

                        // Capture button — saves current frame as a report (manual override)
                        Button(action: captureSnapshot) {
                            Image(systemName: isSavingCapture ? "arrow.clockwise" : "camera.shutter.button")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(canCapture ? .white : .white.opacity(0.3))
                                .frame(width: 50, height: 50)
                                .background(canCapture ? Color.appPrimary : Color.appDark900)
                                .clipShape(Circle())
                                .shadow(radius: canCapture ? 6 : 0)
                        }
                        .disabled(!canCapture || isSavingCapture)

                        // PiP toggle
                        if app.pipManager.isPiPSupported {
                            Button {
                                if app.pipManager.isPiPActive { app.pipManager.stopPiP() }
                                else { app.pipManager.startPiP() }
                            } label: {
                                Image(systemName: app.pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(app.pipManager.isPiPActive ? Color.appPrimary.opacity(0.8) : Color.appDark900)
                                    .clipShape(Circle())
                            }
                        }

                        // Auto-save to Photos toggle
                        Button { app.autoSaveSnapshotsEnabled.toggle() } label: {
                            Image(systemName: app.autoSaveSnapshotsEnabled ? "photo.badge.checkmark.fill" : "photo")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(app.autoSaveSnapshotsEnabled ? .appSuccess : .white)
                                .frame(width: 50, height: 50)
                                .background(Color.appDark900)
                                .clipShape(Circle())
                        }

                        Button { autoReporter.isAutoSaveEnabled.toggle() } label: {
                            Image(systemName: autoReporter.isAutoSaveEnabled ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(autoReporter.isAutoSaveEnabled ? .appSuccess : .white)
                                .frame(width: 50, height: 50)
                                .background(Color.appDark900)
                                .clipShape(Circle())
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: toggleDetection) {
                        Text(isDetecting ? "Stop Detection" : "Start Detection")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: 260)
                            .frame(height: 48)
                            .background(isDetecting ? Color.appDanger : Color.appSuccess)
                            .clipShape(Capsule())
                            .shadow(radius: 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .zIndex(1)
        }
        .onAppear {
            app.locationService.requestPermission()
            app.motionService.start()
            haptic.prepare()
            Task {
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                liveLogger.info("Live tab appeared. Camera permission: \(String(describing: status), privacy: .public), session running: \(cameraManager.captureSession.isRunning, privacy: .public)")
                if status == .notDetermined {
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    liveLogger.info("Camera permission request completed. granted: \(granted, privacy: .public)")
                    if granted { cameraManager.startSession() }
                } else if status == .authorized {
                    cameraManager.startSession()
                } else {
                    app.liveMessage = "Camera access is denied. Enable it in Settings."
                    liveLogger.error("Camera permission is not authorized for live detection")
                }
                // PiP setup requires the session to be running and a source view to be ready.
                // Delay slightly to let the layout pass create the PiPSourceViewCapture view.
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let sourceView = pipSourceView {
                    app.pipManager.setup(captureSession: cameraManager.captureSession, sourceView: sourceView)
                }
            }
        }
        .onReceive(cameraManager.$detectedHazards) { hazards in
            guard isDetecting else { return }
            handle(hazards)
            if hazards.count > previousHazardCount {
                haptic.impactOccurred()
            }
            previousHazardCount = hazards.count
        }
        // 60 fps smoothing task — only runs while tracking is active.
        // Replacing a constant autoconnect() timer that fired on main thread
        // unconditionally, even when detection was paused.
        .task(id: isDetecting && useTracking) {
            guard isDetecting, useTracking else { return }
            while !Task.isCancelled {
                smoothOverlayBoxes()
                try? await Task.sleep(nanoseconds: 16_666_666)
            }
        }
        .onDisappear {
            // Keep session alive when PiP is active — camera continues detecting in the PiP window.
            guard !app.pipManager.isPiPActive else { return }
            isDetecting = false
            overlays = []
            tracker.reset()
            autoReporter.stop()
            cameraManager.stopSession()
            app.motionService.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopLiveCameraSession)) { _ in
            isDetecting = false
            overlays = []
            tracker.reset()
            autoReporter.stop()
            cameraManager.stopSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startLiveCameraSession)) { _ in
            Task { @MainActor in
                if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                    cameraManager.startSession()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: app.pipeline.qualityHint?.rawValue)
        .preferredColorScheme(.dark)
    }

    // MARK: - Computed

    private var speedKmh: Double? {
        guard let speed = app.locationService.currentLocation?.speed, speed >= 0 else { return nil }
        return speed * 3.6
    }

    private var canCapture: Bool {
        isDetecting &&
        !cameraManager.detectedHazards.isEmpty &&
        app.locationService.currentCoordinate != nil
    }

    private var liveStatusMessage: String? {
        if let hint = app.pipeline.qualityHint { return hint.rawValue }
        return app.liveMessage ?? (isDetecting ? app.pipeline.status.rawValue : nil)
    }

    // MARK: - Actions

    private func toggleDetection() {
        isDetecting.toggle()
        if isDetecting {
            overlays = []
            tracker.reset()
            previousHazardCount = 0
            autoReporter.resetSession()
            app.locationService.requestPermission()
            cameraManager.startSession()
            app.liveMessage = nil
        } else {
            overlays = []
            tracker.reset()
            autoReporter.stop()
            app.liveMessage = "Detection paused"
        }
    }

    private func captureSnapshot() {
        guard
            let image = cameraManager.snapshotImage(),
            let coordinate = app.locationService.currentCoordinate,
            !cameraManager.detectedHazards.isEmpty
        else { return }

        let detections = cameraManager.detectedHazards
        let labels = Array(NSOrderedSet(array: detections.map(\.label))) as? [String] ?? []
        let hazardType = labels.joined(separator: ", ")

        withAnimation(.easeIn(duration: 0.08)) { captureFlash = true }
        withAnimation(.easeOut(duration: 0.25).delay(0.08)) { captureFlash = false }
        haptic.impactOccurred(intensity: 1.0)

        if app.autoSaveSnapshotsEnabled {
            Task { await saveToPhotoLibrary(image) }
        }

        isSavingCapture = true
        app.liveMessage = "Saving snapshot..."

        Task {
            let address = (try? await GeocodingService.shared.reverseGeocode(coordinate: coordinate)) ?? ""
            await MainActor.run {
                app.createUploadedReport(
                    image: image,
                    hazardType: hazardType,
                    coordinate: coordinate,
                    address: address,
                    detections: detections
                )
                isSavingCapture = false
            }
        }
    }

    // MARK: - Detection handling

    private func handle(_ candidates: [DetectionCandidate]) {
        let speed = max(app.locationService.currentLocation?.speed ?? 0, 0)
        cameraManager.updateConfidenceThreshold(forSpeed: speed)

        // Keep PiP status label in sync with current detection state
        let pipText = candidates.isEmpty ? "Scanning..." : "\(candidates.count) Hazard\(candidates.count > 1 ? "s" : "")"
        app.pipManager.updateStatus(pipText)

        // Update road attention service each frame (no user tap here — taps handled in CameraView callback)
        app.roadAttentionService.update(
            userTap: nil,
            frameSize: cameraManager.latestFrameSize ?? CGSize(width: 720, height: 1280),
            pitch: app.motionService.pitch,
            roll: app.motionService.roll,
            stableDetections: candidates
        )

        let frame = cameraManager.snapshotImage()
        let metadata = liveFrameMetadata(imageSize: frame?.size ?? cameraManager.latestFrameSize ?? CGSize(width: 720, height: 1280))
        autoReporter.ingest(
            detections: candidates,
            frame: frame,
            location: app.locationService.currentLocation,
            speed: speed,
            metadata: metadata,
            pipeline: app.pipeline,
            userId: app.authManager.user?.uid,
            userProfile: app.userProfile
        ) { result in
            switch result.outcome {
            case .saved:
                if let saved = autoReporter.lastSavedReport {
                    app.liveMessage = "Auto-saved \(saved.label) report."
                } else {
                    app.liveMessage = "Auto report saved."
                }
                if app.autoSaveSnapshotsEnabled, let img = result.annotatedImage {
                    Task { await saveToPhotoLibrary(img) }
                }
            case .duplicate:
                app.liveMessage = "Duplicate skipped."
            case .qualityGateFailed(let hint):
                app.liveMessage = hint.rawValue
            case .error(let error):
                app.liveMessage = error.localizedDescription
            default:
                break
            }
        }

        if useTracking {
            let result = tracker.update(
                with: candidates,
                frame: cameraManager.snapshotImage(),
                speed: speed
            )
            mergeOverlays(result.overlays)
        } else {
            // Raw mode — show model detections directly without tracking or smoothing
            overlays = candidates.enumerated().map { index, c in
                TrackedOverlay(
                    id: index,
                    label: c.label,
                    state: .confirmed,
                    age: 0,
                    currentBoundingBox: c.boundingBox,
                    targetBoundingBox: c.boundingBox,
                    confidence: c.confidence,
                    isFresh: true
                )
            }
        }
    }

    private func liveFrameMetadata(imageSize: CGSize) -> FrameMetadata {
        let location = app.locationService.currentLocation
        var metadata = FrameMetadata(
            timestamp: Date(),
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            horizontalAccuracy: location?.horizontalAccuracy,
            heading: location?.course,
            speed: location?.speed,
            cameraOrientation: nil,
            imageWidth: Int(imageSize.width),
            imageHeight: Int(imageSize.height),
            modelVersion: "best_v1",
            cameraDeviceType: nil,
            lensType: cameraManager.currentLens.rawValue,
            iso: cameraManager.currentISO,
            exposureDuration: cameraManager.currentExposureDuration,
            exposureTargetBias: nil,
            focusMode: cameraManager.currentFocusMode,
            whiteBalanceMode: nil,
            focusPoint: cameraManager.currentFocusPoint,
            exposurePoint: cameraManager.currentExposurePoint,
            roadAttentionPoint: app.roadAttentionService.roadAttentionPoint,
            motionPitch: nil,
            motionRoll: nil,
            motionYaw: nil,
            accelerationMagnitude: nil,
            rotationRate: nil,
            frameQualityScores: nil
        )
        let snapshot = app.motionService.currentSnapshot()
        metadata.motionPitch = snapshot.pitch
        metadata.motionRoll = snapshot.roll
        metadata.motionYaw = snapshot.yaw
        metadata.accelerationMagnitude = snapshot.accelerationMagnitude
        metadata.rotationRate = snapshot.rotationRate
        return metadata
    }

    private func mergeOverlays(_ updated: [TrackedOverlay]) {
        overlays = updated.map { incoming in
            if let existing = overlays.first(where: { $0.id == incoming.id }) {
                var merged = incoming
                merged.currentBoundingBox = existing.currentBoundingBox
                merged.targetBoundingBox = incoming.targetBoundingBox
                return merged
            }
            return incoming
        }
    }

    private func saveToPhotoLibrary(_ image: UIImage) async {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let granted: Bool
        if current == .notDetermined {
            granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
        } else {
            granted = current == .authorized || current == .limited
        }
        guard granted else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    private func smoothOverlayBoxes() {
        let alpha: CGFloat = 0.2
        // Mutate indices directly — avoids the .map {} closure allocation per tick.
        for i in overlays.indices where overlays[i].isFresh {
            overlays[i].currentBoundingBox.origin.x    += (overlays[i].targetBoundingBox.origin.x    - overlays[i].currentBoundingBox.origin.x)    * alpha
            overlays[i].currentBoundingBox.origin.y    += (overlays[i].targetBoundingBox.origin.y    - overlays[i].currentBoundingBox.origin.y)    * alpha
            overlays[i].currentBoundingBox.size.width  += (overlays[i].targetBoundingBox.size.width  - overlays[i].currentBoundingBox.size.width)  * alpha
            overlays[i].currentBoundingBox.size.height += (overlays[i].targetBoundingBox.size.height - overlays[i].currentBoundingBox.size.height) * alpha
        }
    }
}

// MARK: - PiP Source View Capture

private struct PiPSourceViewCapture: UIViewRepresentable {
    let onViewReady: (UIView) -> Void
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        DispatchQueue.main.async { onViewReady(v) }
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Quality Hint Banner

private struct QualityHintBanner: View {
    let hint: QualityHint

    private var icon: String {
        switch hint {
        case .motionBlur: return "waveform.path.ecg"
        case .lowVisibility: return "eye.slash"
        case .tapToFocus: return "scope"
        case .adjustAngle: return "rotate.3d"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.appWarning)
            Text(hint.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.65))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.appWarning.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - HUD

private struct EnhancedHUDView: View {
    let isDetecting: Bool
    let hazardCount: Int
    let message: String?
    let location: String
    let speedKmh: Double?
    let fps: Double
    let autoSaveEnabled: Bool
    let autoState: LiveAutoReportState
    let currentCandidate: LiveAutoReportCandidate?
    let reportsSavedCount: Int

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
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor.opacity(0.8), radius: 4)
                    Text(statusText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isDetecting {
                    Text("\(reportsSavedCount) saved")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                Label(location, systemImage: "location.fill")
                    .foregroundColor(location == "GPS Active" ? .appPrimary : .appWarning)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Text(metricText)
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))

            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
            }

            if isDetecting {
                HStack(spacing: 8) {
                    Label(autoSaveEnabled ? autoState.displayText : "Auto off", systemImage: autoSaveEnabled ? "tray.and.arrow.down.fill" : "tray")
                        .foregroundColor(autoSaveEnabled ? .appSuccess : .white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 6)

                    if let currentCandidate {
                        Text("\(currentCandidate.label) \(Int(currentCandidate.confidence * 100))%")
                            .foregroundColor(.white.opacity(0.78))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
            }
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var metricText: String {
        var parts: [String] = []
        if let speedKmh {
            parts.append(String(format: "%.0f km/h", speedKmh))
        }
        if isDetecting, fps > 0 {
            parts.append(String(format: "%.0f fps", fps))
        }
        return parts.isEmpty ? "--" : parts.joined(separator: "  ")
    }
}
