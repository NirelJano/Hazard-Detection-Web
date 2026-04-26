import AVFoundation
import Vision
import CoreML
import UIKit
import CoreLocation

final class HazardDetector {
    static let shared = HazardDetector()
    private init() {}
    
    private let model: VNCoreMLModel? = {
        let config = MLModelConfiguration()
        guard let modelURL = Bundle.main.url(forResource: "best", withExtension: "mlmodelc"),
              let mlModel = try? MLModel(contentsOf: modelURL, configuration: config) else {
            print("[HazardDetector] Error: Could not load best.mlmodelc from the app bundle.")
            return nil
        }
        return try? VNCoreMLModel(for: mlModel)
    }()

    func detect(in image: UIImage, confidenceThreshold: Float = 0.40) -> [DetectionCandidate] {
        guard let model, let cgImage = image.cgImage else { return [] }

        var results: [DetectionCandidate] = []
        let request = VNCoreMLRequest(model: model) { request, _ in
            let observations = request.results as? [VNRecognizedObjectObservation] ?? []
            results = observations.compactMap { observation in
                guard observation.confidence >= confidenceThreshold,
                      let rawLabel = observation.labels.first?.identifier else { return nil }
                
                // Normalize label: crack -> Crack, pothole -> Pothole
                let normalizedLabel = self.normalize(rawLabel)
                return DetectionCandidate(
                    label: normalizedLabel,
                    confidence: observation.confidence,
                    boundingBox: observation.boundingBox
                )
            }
        }
        request.imageCropAndScaleOption = .scaleFill

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try? handler.perform([request])

        return results
    }
    
    func createVisionRequest(callback: @escaping (VNRequest, Error?) -> Void) -> VNCoreMLRequest? {
        guard let model else { return nil }
        let request = VNCoreMLRequest(model: model, completionHandler: callback)
        request.imageCropAndScaleOption = .scaleFill
        return request
    }

    func normalize(_ label: String) -> String {
        switch label.lowercased() {
        case "crack": return "Crack"
        case "pothole": return "Pothole"
        default: return label.capitalized
        }
    }
}

final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var detectedHazards: [DetectionCandidate] = []

    // MARK: - AVFoundation
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "hazard.camera.session", qos: .userInitiated)

    // MARK: - Vision
    private var visionRequest: VNCoreMLRequest?
    private var confidenceThreshold: Float = 0.40
    private let inferenceInterval: TimeInterval = 0.25
    private let imageContext = CIContext()
    private let frameLock = NSLock()
    private var lastInferenceTime: Date = .distantPast
    private var latestFrame: UIImage?

    // MARK: - Init
    override init() {
        super.init()
        setupModel()
        setupSession()
    }

    // MARK: - Model Setup
    private func setupModel() {
        guard let request = HazardDetector.shared.createVisionRequest(callback: { [weak self] req, err in
            self?.handleDetections(request: req, error: err)
        }) else {
            print("[CameraManager] Error: Could not create Vision request from HazardDetector.")
            return
        }
        self.visionRequest = request
        print("[CameraManager] Model loaded successfully.")
    }

    // MARK: - Session Setup
    private func setupSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .vga640x480

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            print("[CameraManager] Cannot access rear camera.")
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
        }

        captureSession.commitConfiguration()
    }

    // MARK: - Session Control
    func startSession() {
        guard !captureSession.isRunning else { return }
        sessionQueue.async { self.captureSession.startRunning() }
    }

    func stopSession() {
        guard captureSession.isRunning else { return }
        sessionQueue.async { self.captureSession.stopRunning() }
    }

    func snapshotImage() -> UIImage? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return latestFrame
    }

    func updateConfidenceThreshold(forSpeed speed: CLLocationSpeed) {
        frameLock.lock()
        confidenceThreshold = speed > 13.8 ? 0.30 : 0.40
        frameLock.unlock()
    }

    // MARK: - Vision Processing
    private func handleDetections(request: VNRequest, error: Error?) {
        if let error { print("[CameraManager] Vision error: \(error)") }
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
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([visionRequest])
    }

    private func storeLatestFrame(_ pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
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
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
