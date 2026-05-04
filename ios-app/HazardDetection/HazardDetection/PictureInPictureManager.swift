import AVFoundation
import AVKit
import UIKit

// MARK: - PiP Preview View

// Uses AVCaptureVideoPreviewLayer as its backing CALayer so layout is handled
// by UIView's Auto Layout engine instead of CALayer.autoresizingMask (unavailable on iOS).
private final class PiPPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

// MARK: - PictureInPictureManager

@MainActor
final class PictureInPictureManager: NSObject, ObservableObject {
    @Published private(set) var isPiPActive    = false
    @Published private(set) var isPiPSupported = AVPictureInPictureController.isPictureInPictureSupported()

    private var pipController: AVPictureInPictureController?
    private let pipContentVC = AVPictureInPictureVideoCallViewController()
    private var statusLabel: UILabel?
    private var isSetUp = false

    // MARK: - Setup

    func setup(captureSession: AVCaptureSession, sourceView: UIView) {
        guard !isSetUp, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        isSetUp = true

        // Audio session keeps the process alive while the camera runs in background PiP.
        // .playAndRecord lets the camera stay active; .mixWithOthers avoids interrupting music.
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord,
            options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP]
        )
        try? AVAudioSession.sharedInstance().setActive(true)

        pipContentVC.preferredContentSize = CGSize(width: 9, height: 16)

        // Camera preview — fills the PiP container via Auto Layout
        let previewView = PiPPreviewView()
        previewView.previewLayer.session = captureSession
        previewView.previewLayer.videoGravity = .resizeAspectFill
        previewView.translatesAutoresizingMaskIntoConstraints = false
        pipContentVC.view.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: pipContentVC.view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: pipContentVC.view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: pipContentVC.view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: pipContentVC.view.bottomAnchor)
        ])

        // Hazard count status label pinned to the bottom of the PiP window
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.text = "Scanning..."
        label.translatesAutoresizingMaskIntoConstraints = false
        pipContentVC.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: pipContentVC.view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: pipContentVC.view.bottomAnchor, constant: -12),
            label.heightAnchor.constraint(equalToConstant: 28),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
        ])
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel = label

        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: pipContentVC
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        pipController = controller
    }

    // MARK: - Control

    func startPiP() { pipController?.startPictureInPicture() }
    func stopPiP()  { pipController?.stopPictureInPicture() }

    func updateStatus(_ text: String) {
        statusLabel?.text = text
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PictureInPictureManager: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isPiPActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isPiPActive = false }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
