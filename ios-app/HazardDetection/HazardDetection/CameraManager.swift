import AVFoundation
import CoreLocation
import CoreML
import os
import UIKit
import Vision

private let logger = Logger(subsystem: "com.hazarddetection", category: "Camera")

// MARK: - CameraLens

enum CameraLens: String, CaseIterable, Identifiable {
    case ultraWide = "0.5×"
    case wide      = "1×"
    case telephoto = "2×"
    var id: String { rawValue }
    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide:  return .builtInUltraWideCamera
        case .wide:       return .builtInWideAngleCamera
        case .telephoto:  return .builtInTelephotoCamera
        }
    }
}

// MARK: - HazardDetector

final class HazardDetector {
    static let shared = HazardDetector()
    private init() {}

    // Single MLModel load — shared by both the modern async path and the legacy sequence-handler path.
    private(set) lazy var mlModel: MLModel? = {
        let config = MLModelConfiguration()
        guard let url = Bundle.main.url(forResource: "best", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url, configuration: config) else {
            logger.error("Could not load best.mlmodelc from the app bundle")
            return nil
        }
        return model
    }()

    // VNCoreMLModel wrapper — used by CameraManager's VNSequenceRequestHandler.
    lazy var vnModel: VNCoreMLModel? = {
        guard let mlModel, let wrapped = try? VNCoreMLModel(for: mlModel) else { return nil }
        return wrapped
    }()

    // MARK: - Detection

    /// Runs hazard detection on a still image.
    /// Uses the modern Vision async API on iOS 18+; falls back to the legacy handler on iOS 17.
    func detect(in image: UIImage, confidenceThreshold: Float = 0.40) async -> [DetectionCandidate] {
        if #available(iOS 18.0, *) {
            return await detectModern(in: image, confidenceThreshold: confidenceThreshold)
        }
        return detectLegacy(in: image, confidenceThreshold: confidenceThreshold)
    }

    @available(iOS 18.0, *)
    private func detectModern(in image: UIImage, confidenceThreshold: Float) async -> [DetectionCandidate] {
        guard let cgImage = image.cgImage, let mlModel else { return [] }
        do {
            let container = try CoreMLModelContainer(model: mlModel)
            let request = CoreMLRequest(model: container)
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            let results = try await request.perform(on: cgImage, orientation: orientation)
            return results.compactMap { obs -> DetectionCandidate? in
                guard let obj = obs as? VNRecognizedObjectObservation,
                      obj.confidence >= confidenceThreshold,
                      let label = obj.labels.first?.identifier else { return nil }
                return DetectionCandidate(
                    label: normalize(label),
                    confidence: obj.confidence,
                    boundingBox: obj.boundingBox
                )
            }
        } catch {
            logger.error("Modern detection failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func detectLegacy(in image: UIImage, confidenceThreshold: Float) -> [DetectionCandidate] {
        guard let vnModel, let cgImage = image.cgImage else { return [] }
        var results: [DetectionCandidate] = []
        let request = VNCoreMLRequest(model: vnModel) { req, _ in
            let observations = req.results as? [VNRecognizedObjectObservation] ?? []
            results = observations.compactMap { observation in
                guard observation.confidence >= confidenceThreshold,
                      let label = observation.labels.first?.identifier else { return nil }
                return DetectionCandidate(
                    label: self.normalize(label),
                    confidence: observation.confidence,
                    boundingBox: observation.boundingBox
                )
            }
        }
        request.imageCropAndScaleOption = .scaleFill
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        try? handler.perform([request])
        return results
    }

    func normalize(_ label: String) -> String {
        switch label.lowercased() {
        case "crack":   return "Crack"
        case "pothole": return "Pothole"
        default:        return label.capitalized
        }
    }
}

// MARK: - CameraManager

final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var detectedHazards: [DetectionCandidate] = []
    @Published var fps: Double = 0
    @Published private(set) var isSessionRunning = false

    // Lens selection
    @Published private(set) var availableLenses: [CameraLens] = []
    @Published private(set) var currentLens: CameraLens = .wide

    // Published camera metadata — populated live and included in FrameMetadata for reports
    @Published private(set) var currentFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.75)
    @Published private(set) var currentExposurePoint: CGPoint = CGPoint(x: 0.5, y: 0.75)
    @Published private(set) var currentISO: Float = 0
    @Published private(set) var currentExposureDuration: Double = 0
    @Published private(set) var currentFocusMode: String = "continuousAutoFocus"

    // MARK: - AVFoundation
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "hazard.camera.session", qos: .userInitiated)
    private let detectionQueue = DispatchQueue(label: "hazard.camera.detection", qos: .userInitiated)
    private weak var captureDevice: AVCaptureDevice?

    // MARK: - Vision
    // VNSequenceRequestHandler maintains temporal context across frames — preferred over
    // creating a new VNImageRequestHandler per frame for video sequences.
    private let sequenceHandler = VNSequenceRequestHandler()
    private var visionRequest: VNCoreMLRequest?
    private var confidenceThreshold: Float = DetectionConfig.displayThreshold
    private let inferenceInterval: TimeInterval = 0.10
    // cacheIntermediates: false prevents CIContext from accumulating GPU-memory
    // as a render cache across frames, which causes OOM kills during live detection.
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let frameLock = NSLock()
    private var lastInferenceTime: Date = .distantPast
    private var latestFrame: UIImage?

    // MARK: - FPS Tracking
    private var frameTimestamps: [Date] = []
    private var frameCountForMetadata = 0

    // MARK: - Init
    override init() {
        super.init()
        logger.info("Camera permission at init: \(Self.cameraAuthorizationDescription(), privacy: .public)")
        // Dispatch both model loading and session configuration to the session queue.
        // This unblocks the main thread (MLModel(contentsOf:) is synchronous I/O)
        // and ensures every AVCaptureSession mutation happens on the same serial queue,
        // which is required for the preview layer to connect and show video.
        sessionQueue.async {
            self.setupModel()
            self.setupSession()
        }
        observeSessionNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func observeSessionNotifications() {
        // AVCaptureSession runtime errors (e.g. camera daemon XPC failure, err=-17281)
        // require explicit recovery — the session does NOT restart itself.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: captureSession
        )
        // Re-start after an interruption (phone call, background, etc.) is cleared.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: captureSession
        )
    }

    @objc private func handleSessionRuntimeError(_ notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        logger.error("AVCaptureSession runtime error: \(error.localizedDescription, privacy: .public), code: \(error.code.rawValue, privacy: .public)")
        sessionQueue.async { self.logSessionState("runtime error") }
        // AVErrorMediaServicesWereReset means the camera daemon crashed and recovered.
        // Attempt one restart; any other error is unrecoverable without user action.
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.captureSession.isRunning { return }
                self.captureSession.startRunning()
                self.logSessionState("restart after media services reset")
                DispatchQueue.main.async { self.isSessionRunning = self.captureSession.isRunning }
            }
        }
    }

    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        sessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                self.logSessionState("interruption ended restart")
                DispatchQueue.main.async { self.isSessionRunning = self.captureSession.isRunning }
            }
        }
    }

    // MARK: - Model Setup
    private func setupModel() {
        guard let vnModel = HazardDetector.shared.vnModel else {
            logger.error("Could not obtain VNCoreMLModel from HazardDetector")
            return
        }
        let request = VNCoreMLRequest(model: vnModel) { [weak self] req, err in
            self?.handleDetections(request: req, error: err)
        }
        request.imageCropAndScaleOption = .scaleFill
        self.visionRequest = request
        logger.info("Model loaded successfully")
    }

    // MARK: - Session Setup
    private func setupSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720

        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                  ?? AVCaptureDevice.default(for: .video)
        guard
            let device,
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            logger.error("Cannot access rear camera")
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)
        self.captureDevice = device
        configureDeviceForRoadDetection(device)
        logger.info("Camera: \(device.localizedName, privacy: .public), preset: hd1280x720")

        videoOutput.setSampleBufferDelegate(self, queue: detectionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            logger.error("Cannot add AVCaptureVideoDataOutput to capture session")
        }

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .standard
            }
        } else {
            logger.error("Video data output has no video connection after session setup")
        }

        captureSession.commitConfiguration()
        logSessionState("setup complete")
        discoverAvailableLenses()
    }

    private func discoverAvailableLenses() {
        let types = CameraLens.allCases.map(\.deviceType)
        let found = Set(
            AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .back)
                .devices.map(\.deviceType)
        )
        let lenses = CameraLens.allCases.filter { found.contains($0.deviceType) }
        DispatchQueue.main.async { self.availableLenses = lenses }
    }

    private func configureDeviceForRoadDetection(_ device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        let defaultPoint = CGPoint(x: 0.5, y: 0.75)
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = defaultPoint
        }
        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = true
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = defaultPoint
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        DispatchQueue.main.async {
            self.currentFocusPoint = defaultPoint
            self.currentExposurePoint = defaultPoint
            self.currentFocusMode = "continuousAutoFocus"
        }
    }

    // MARK: - Tap-to-Focus

    /// Set focus and exposure at a normalized camera point (0–1 range, AVCapture coords).
    /// Temporarily locks to autoFocus/autoExpose, then restores continuous modes after 2 s.
    func setFocusAndExposure(at normalizedPoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.captureDevice else { return }
            guard (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }

            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = normalizedPoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = normalizedPoint
                device.exposureMode = .autoExpose
            }
            DispatchQueue.main.async {
                self.currentFocusPoint = normalizedPoint
                self.currentExposurePoint = normalizedPoint
                self.currentFocusMode = "autoFocus"
                logger.debug("Focus/exposure set to (\(normalizedPoint.x, privacy: .public), \(normalizedPoint.y, privacy: .public))")
            }

            // Restore continuous modes after 2 s so the camera stays sharp while driving
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self else { return }
                self.sessionQueue.async {
                    guard let device = self.captureDevice,
                          (try? device.lockForConfiguration()) != nil else { return }
                    defer { device.unlockForConfiguration() }
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                    DispatchQueue.main.async { self.currentFocusMode = "continuousAutoFocus" }
                }
            }
        }
    }

    // MARK: - Lens Switching

    func switchLens(to lens: CameraLens) {
        guard lens != currentLens,
              let device = AVCaptureDevice.DiscoverySession(
                  deviceTypes: [lens.deviceType], mediaType: .video, position: .back
              ).devices.first else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.inputs.forEach { self.captureSession.removeInput($0) }
            guard let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(input)
            self.captureDevice = device
            self.configureDeviceForRoadDetection(device)
            if let connection = self.videoOutput.connection(with: .video) {
                let angle: CGFloat = 90
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .standard
                }
            }
            self.captureSession.commitConfiguration()
            DispatchQueue.main.async { self.currentLens = lens }
        }
    }

    // MARK: - Orientation

    /// Called by CameraView whenever the interface orientation changes so that
    /// the video output delivers pixel buffers in the same orientation as the preview.
    /// Must be called on the main thread; the actual property update is dispatched
    /// to the session queue to stay consistent with other AVCapture mutations.
    func setOutputRotationAngle(_ angle: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let connection = self.videoOutput.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle)
            else { return }
            connection.videoRotationAngle = angle
            logger.debug("Video output rotation angle set: \(angle, privacy: .public)")
        }
    }

    // MARK: - Session Control
    func startSession() {
        logger.info("startSession requested. Camera permission: \(Self.cameraAuthorizationDescription(), privacy: .public), main thread: \(Thread.isMainThread, privacy: .public)")
        sessionQueue.async {
            guard !self.captureSession.isRunning else { return }
            self.logSessionState("before startRunning")
            self.captureSession.startRunning()
            self.logSessionState("after startRunning")
            DispatchQueue.main.async { self.isSessionRunning = self.captureSession.isRunning }
        }
    }

    func stopSession() {
        logger.info("stopSession requested. main thread: \(Thread.isMainThread, privacy: .public)")
        sessionQueue.async {
            guard self.captureSession.isRunning else { return }
            self.logSessionState("before stopRunning")
            self.captureSession.stopRunning()
            self.logSessionState("after stopRunning")
            DispatchQueue.main.async {
                self.isSessionRunning = false
                self.fps = 0
                self.frameTimestamps.removeAll()
            }
        }
    }

    private func logSessionState(_ context: String) {
        logger.info(
            "Session \(context, privacy: .public): running=\(self.captureSession.isRunning, privacy: .public), inputs=\(self.captureSession.inputs.count, privacy: .public), outputs=\(self.captureSession.outputs.count, privacy: .public)"
        )
    }

    private static func cameraAuthorizationDescription() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }

    func snapshotImage() -> UIImage? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return latestFrame
    }

    func updateConfidenceThreshold(forSpeed speed: CLLocationSpeed) {
        frameLock.lock()
        confidenceThreshold = speed > DetectionConfig.highSpeedMSCutoff
            ? DetectionConfig.highSpeedThreshold
            : DetectionConfig.displayThreshold
        frameLock.unlock()
    }

    // MARK: - Vision Processing
    private func handleDetections(request: VNRequest, error: Error?) {
        if let error { logger.error("Vision error: \(error.localizedDescription, privacy: .public)") }
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return }

        frameLock.lock()
        let threshold = confidenceThreshold
        frameLock.unlock()

        let candidates = results.compactMap { observation -> DetectionCandidate? in
            guard observation.confidence >= threshold,
                  let rawLabel = observation.labels.first?.identifier else { return nil }
            return DetectionCandidate(
                label: HazardDetector.shared.normalize(rawLabel),
                confidence: observation.confidence,
                boundingBox: observation.boundingBox
            )
        }

        DispatchQueue.main.async { self.detectedHazards = candidates }
    }

    var latestFrameSize: CGSize? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return latestFrame?.size
    }
}

// MARK: - Sample Buffer Delegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        trackFPS()

        // Sample camera metadata every 30 frames to avoid per-frame overhead
        frameCountForMetadata += 1
        if frameCountForMetadata >= 30, let device = captureDevice {
            frameCountForMetadata = 0
            let iso = device.iso
            let expDuration = CMTimeGetSeconds(device.exposureDuration)
            DispatchQueue.main.async {
                self.currentISO = iso
                self.currentExposureDuration = expDuration
            }
        }

        guard Date().timeIntervalSince(lastInferenceTime) >= inferenceInterval else { return }
        lastInferenceTime = Date()

        guard
            let visionRequest,
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            DispatchQueue.main.async { self.detectedHazards = [] }
            return
        }
        storeLatestFrame(pixelBuffer)
        // VNSequenceRequestHandler retains temporal context across frames — more efficient
        // than allocating a new VNImageRequestHandler per inference tick.
        try? sequenceHandler.perform([visionRequest], on: pixelBuffer)
    }

    private func trackFPS() {
        let now = Date()
        frameTimestamps.append(now)
        frameTimestamps = frameTimestamps.filter { now.timeIntervalSince($0) <= 1.0 }
        let currentFPS = Double(frameTimestamps.count)
        DispatchQueue.main.async { self.fps = currentFPS }
    }

    private func storeLatestFrame(_ pixelBuffer: CVPixelBuffer) {
        // The output connection's videoRotationAngle is kept in sync with the interface
        // orientation by setOutputRotationAngle(_:), so the pixel buffer already carries the
        // correct visual orientation — render it directly without any additional transform.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)
        frameLock.lock()
        latestFrame = image
        frameLock.unlock()
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:            self = .up
        case .down:          self = .down
        case .left:          self = .left
        case .right:         self = .right
        case .upMirrored:    self = .upMirrored
        case .downMirrored:  self = .downMirrored
        case .leftMirrored:  self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}
