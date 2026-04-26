import CoreLocation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit

struct UploadReportView: View {
    @EnvironmentObject private var app: AppController
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedImageData: Data?
    @State private var detectedCandidates: [DetectionCandidate] = []
    @State private var resolvedCoordinate: CLLocationCoordinate2D?
    @State private var resolvedAddress: String?
    @State private var statusMessage: String?
    @State private var statusColor: Color = .appWarning
    @State private var isProcessing = false
    @State private var showingCamera = false
    @State private var shouldClearAfterSave = false

    private var uniqueDetectionLabel: String? {
        let labels = detectedCandidates.map(\.label)
        let unique = Array(NSOrderedSet(array: labels)) as? [String] ?? []
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    private var reportImage: UIImage? {
        guard let selectedImage else { return nil }
        return ImageAnnotator.drawBoundingBoxes(on: selectedImage, detections: detectedCandidates)
    }

    private var canSave: Bool {
        !app.isUploadingReport &&
        !detectedCandidates.isEmpty &&
        selectedImage != nil &&
        resolvedCoordinate != nil &&
        resolvedAddress != nil
    }

    var body: some View {
        FormScreen(title: "Upload Report", subtitle: "Detect hazards from camera or gallery images.") {
            HStack(spacing: 12) {
                Button {
                    app.locationService.requestPermission()
                    showingCamera = true
                } label: {
                    UploadSourceButton(icon: "camera.fill", title: "Camera")
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    UploadSourceButton(icon: "photo.fill", title: "Gallery")
                }
                .onChange(of: selectedItem) { _, item in
                    Task { await loadGalleryImage(from: item) }
                }
            }

            if isProcessing {
                StatusText(message: "Detecting hazards...", color: .appPrimary)
            }

            if let selectedImage {
                DetectionPreviewCard(image: selectedImage, detections: detectedCandidates)
            }

            if let label = uniqueDetectionLabel {
                StatusText(message: "Detected \(label).", color: .appSuccess)
            } else if selectedImage != nil, !isProcessing {
                StatusText(message: "No hazard detected in this image.", color: .appDark400)
            }

            LocationStatus(coordinate: resolvedCoordinate, address: resolvedAddress)

            if let statusMessage {
                StatusText(message: statusMessage, color: statusColor)
            }

            if !detectedCandidates.isEmpty {
                Button {
                    saveReport()
                } label: {
                    Text(app.isUploadingReport ? "Saving..." : "Save Report")
                        .primaryButtonStyle()
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.55)
            }

            if let message = app.uploadMessage {
                StatusText(message: message, color: message == "Report saved." ? .appSuccess : .appWarning)
            }
        }
        .onAppear { app.locationService.requestPermission() }
        .sheet(isPresented: $showingCamera) {
            CameraImagePicker { image, data in
                Task { await processImage(image: image, data: data, isCamera: true) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: app.uploadMessage) { _, message in
            guard message == "Report saved.", !shouldClearAfterSave else { return }
            shouldClearAfterSave = true
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    clearState()
                    shouldClearAfterSave = false
                }
            }
        }
    }

    private func loadGalleryImage(from item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            await MainActor.run {
                statusMessage = "Please upload an image file."
                statusColor = .appDanger
            }
            return
        }
        await processImage(image: image.normalizedOrientation(), data: data, isCamera: false)
    }

    private func processImage(image: UIImage, data: Data?, isCamera: Bool) async {
        await MainActor.run {
            resetForNewImage(image: image, data: data)
            isProcessing = true
        }

        let coordinate = resolveCoordinate(from: data, isCamera: isCamera)
        let detections = HazardDetector.shared.detect(in: image)
        var address: String?

        if let coordinate {
            await MainActor.run {
                statusMessage = "Resolving address..."
                statusColor = .appPrimary
            }
            address = try? await GeocodingService.shared.reverseGeocode(coordinate: coordinate)
        }

        await MainActor.run {
            detectedCandidates = detections
            resolvedCoordinate = coordinate
            resolvedAddress = address
            isProcessing = false

            if coordinate == nil {
                statusMessage = isCamera
                    ? "Could not fetch device location. Location is required."
                    : "No GPS data found in image. Location required."
                statusColor = .appDanger
            } else if address == nil {
                statusMessage = "Could not resolve address."
                statusColor = .appDanger
            } else if detections.isEmpty {
                statusMessage = "No hazard detected in this image."
                statusColor = .appDark400
            } else {
                statusMessage = "Ready to save report."
                statusColor = .appSuccess
            }
        }
    }

    private func resolveCoordinate(from data: Data?, isCamera: Bool) -> CLLocationCoordinate2D? {
        if let data, let coordinate = ImageGPSExtractor.extractCoordinate(from: data) {
            return coordinate
        }
        if isCamera {
            app.locationService.requestPermission()
            return app.locationService.currentCoordinate
        }
        return nil
    }

    private func saveReport() {
        guard
            let image = reportImage,
            let label = uniqueDetectionLabel,
            let coordinate = resolvedCoordinate,
            let address = resolvedAddress
        else {
            statusMessage = "Cannot save: missing detection, location, or address."
            statusColor = .appDanger
            return
        }

        app.createUploadedReport(
            image: image,
            hazardType: label,
            coordinate: coordinate,
            address: address,
            detections: detectedCandidates
        )
    }

    private func resetForNewImage(image: UIImage, data: Data?) {
        selectedImage = image
        selectedImageData = data
        detectedCandidates = []
        resolvedCoordinate = nil
        resolvedAddress = nil
        statusMessage = "Waiting for image..."
        statusColor = .appDark400
        app.uploadMessage = nil
    }

    private func clearState() {
        selectedItem = nil
        selectedImage = nil
        selectedImageData = nil
        detectedCandidates = []
        resolvedCoordinate = nil
        resolvedAddress = nil
        statusMessage = nil
    }
}

private struct UploadSourceButton: View {
    let icon: String
    let title: String

    var body: some View {
        HStack {
            Image(systemName: icon)
            Text(title)
            Spacer()
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundColor(.white)
        .padding(14)
        .background(Color.appDark900)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct LocationStatus: View {
    let coordinate: CLLocationCoordinate2D?
    let address: String?

    var body: some View {
        let text: String = {
            if let address { return "Location: \(address)" }
            if let coordinate {
                return String(format: "GPS %.5f, %.5f", coordinate.latitude, coordinate.longitude)
            }
            return "Waiting for image location"
        }()
        StatusText(message: text, color: coordinate == nil ? .appWarning : .appSuccess)
    }
}

private struct DetectionPreviewCard: View {
    let image: UIImage
    let detections: [DetectionCandidate]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                ForEach(Array(detections.enumerated()), id: \.offset) { _, detection in
                    let rect = DetectionGeometry.visionRectToAspectFitRect(
                        detection.boundingBox,
                        imageSize: image.size,
                        containerSize: geometry.size
                    )

                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .stroke(Color.appSuccess, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)

                        Text("\(detection.label) \(Int(detection.confidence * 100))%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.appSuccess)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .position(
                                x: rect.minX + 60,
                                y: max(rect.minY - 12, 8)
                            )
                    }
                }
            }
        }
        .frame(height: 220)
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage, Data?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker

        init(parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image.normalizedOrientation(), image.jpegData(compressionQuality: 0.95))
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

enum ImageGPSExtractor {
    static func extractCoordinate(from imageData: Data) -> CLLocationCoordinate2D? {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
            let longitude = gps[kCGImagePropertyGPSLongitude] as? Double
        else { return nil }

        let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String
        let lngRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
        return CLLocationCoordinate2D(
            latitude: latRef == "S" ? -latitude : latitude,
            longitude: lngRef == "W" ? -longitude : longitude
        )
    }
}

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
