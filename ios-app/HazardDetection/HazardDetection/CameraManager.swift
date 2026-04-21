import AVFoundation
import Vision
import CoreML
import UIKit

final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var detectedHazards: [VNRecognizedObjectObservation] = []

    // MARK: - AVFoundation
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "hazard.camera.session", qos: .userInitiated)

    // MARK: - Vision
    private var visionRequest: VNCoreMLRequest?
    private let confidenceThreshold: Float = 0.50
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
        // TODO: Replace "best" with your actual .mlpackage name after drag-dropping it into Xcode
        guard
            let modelURL = Bundle.main.url(forResource: "best", withExtension: "mlmodelc"),
            let mlModel = try? MLModel(contentsOf: modelURL),
            let vnModel = try? VNCoreMLModel(for: mlModel)
        else {
            print("[CameraManager] CoreML model not found. Add best.mlpackage to the project.")
            return
        }

        let request = VNCoreMLRequest(model: vnModel) { [weak self] req, err in
            self?.handleDetections(request: req, error: err)
        }
        request.imageCropAndScaleOption = .scaleFill
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

    // MARK: - Vision Processing
    private func handleDetections(request: VNRequest, error: Error?) {
        if let error { print("[CameraManager] Vision error: \(error)") }
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
        let filtered = results.filter { $0.confidence >= confidenceThreshold }
        DispatchQueue.main.async { self.detectedHazards = filtered }
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
