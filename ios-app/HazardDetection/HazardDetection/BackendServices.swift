import Combine
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftUI
import UIKit

enum AppBackendError: LocalizedError {
    case unauthenticated
    case unauthorized
    case missingLocation
    case invalidImage
    case missingReportId
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated: return "You must be signed in to use this feature."
        case .unauthorized: return "You are not authorized to change this report."
        case .missingLocation: return "Location is unavailable. Enable location permission and try again."
        case .invalidImage: return "Could not prepare the selected image for upload."
        case .missingReportId: return "The report ID is missing."
        case .custom(let msg): return msg
        }
    }
}

@MainActor
final class ReportRepository: ObservableObject {
    @Published private(set) var reports: [HazardReport] = []
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isUploading = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    func fetchReports() {
        listener?.remove()
        isLoading = true
        errorMessage = nil

        listener = db.collection("reports")
            .order(by: "id", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoading = false

                    if let error {
                        self.errorMessage = error.localizedDescription
                        print("Firestore reports listener failed: \(error.localizedDescription)")
                        return
                    }

                    let documents = snapshot?.documents ?? []
                    self.reports = documents.compactMap { HazardReport(document: $0) }
                    print("Firestore reports listener updated: \(self.reports.count) reports.")
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        reports = []
        isLoading = false
    }

    func addReport(
        type: String,
        description: String?,
        lat: Double,
        lng: Double,
        image: UIImage?,
        userProfile: AppUserProfile?,
        userId: String,
        detectionLabel: String? = nil,
        detectionConfidence: Double? = nil,
        detectionSource: String? = nil,
        detectionBoundingBox: DetectionBoundingBox? = nil
    ) async throws {
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        var address: String? = nil
        do {
            address = try await GeocodingService.shared.reverseGeocode(coordinate: coordinate)
        } catch {
            print("Geocoding failed: \(error)")
        }

        try await addReport(
            type: type,
            description: description,
            lat: lat,
            lng: lng,
            address: address,
            image: image,
            userProfile: userProfile,
            userId: userId,
            createdAtMillis: Int64(Date().timeIntervalSince1970 * 1000),
            detectionLabel: detectionLabel,
            detectionConfidence: detectionConfidence,
            detectionSource: detectionSource,
            detectionBoundingBox: detectionBoundingBox
        )
    }

    func addReport(
        type: String,
        description: String?,
        lat: Double,
        lng: Double,
        address: String?,
        image: UIImage?,
        userProfile: AppUserProfile?,
        userId: String,
        createdAtMillis: Int64,
        detectionLabel: String? = nil,
        detectionConfidence: Double? = nil,
        detectionSource: String? = nil,
        detectionBoundingBox: DetectionBoundingBox? = nil
    ) async throws {
        guard Auth.auth().currentUser?.uid == userId else {
            throw AppBackendError.unauthenticated
        }

        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            var imageUrl: String? = nil
            if let image {
                imageUrl = try await CloudinaryService.shared.uploadImage(image)
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yy HH:mm"
            let dateString = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(createdAtMillis) / 1000))
            let reportedBy = userProfile?.displayName ?? userProfile?.email ?? "User"

            let reportRef = db.collection("reports").document()
            let counterRef = db.collection("metadata").document("reportCounter")
            
            let newId = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                let counterDoc: DocumentSnapshot
                do {
                    try counterDoc = transaction.getDocument(counterRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                
                let oldCount = counterDoc.data()?["count"] as? Int ?? 0
                let newCount = oldCount + 1
                
                transaction.setData(["count": newCount], forDocument: counterRef, merge: true)

                var data: [String: Any] = [
                    "id": newCount,
                    "hazardType": type,
                    "date": dateString,
                    "createdAt": createdAtMillis,
                    "coordinate": GeoPoint(latitude: lat, longitude: lng),
                    "address": address ?? "",
                    "imageUrl": imageUrl ?? "",
                    "reportedBy": reportedBy,
                    "status": "new"
                ]
                if let description { data["description"] = description }
                if let detectionLabel { data["detectedLabel"] = detectionLabel }
                if let detectionConfidence { data["detectionConfidence"] = detectionConfidence }
                if let detectionSource { data["detectionSource"] = detectionSource }
                if let detectionBoundingBox { data["detectionBoundingBox"] = detectionBoundingBox.dictionary }

                transaction.setData(data, forDocument: reportRef)
                
                return newCount
            })
            print("Firestore report created with id: \(newId ?? -1)")
        } catch {
            errorMessage = error.localizedDescription
            print("Failed to create report: \(error.localizedDescription)")
            throw error
        }
    }

    func updateReportStatus(reportId: String, newStatus: String, isAdmin: Bool) async throws {
        guard isAdmin else { throw AppBackendError.unauthorized }
        do {
            try await db.collection("reports").document(reportId).updateData([
                "status": newStatus
            ])
            print("Firestore report status updated: \(reportId) -> \(newStatus)")
        } catch {
            errorMessage = error.localizedDescription
            print("Failed to update report status: \(error.localizedDescription)")
            throw error
        }
    }

    func deleteReport(reportId: String, isAdmin: Bool) async throws {
        guard isAdmin else { throw AppBackendError.unauthorized }
        do {
            try await db.collection("reports").document(reportId).delete()
            print("Firestore report deleted: \(reportId)")
        } catch {
            errorMessage = error.localizedDescription
            print("Failed to delete report: \(error.localizedDescription)")
            throw error
        }
    }
}

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var currentUser: AppUser?
    @Published private(set) var userProfile: AppUserProfile?
    @Published private(set) var reports: [HazardReport] = []
    @Published var authMessage: String?
    @Published var dashboardMessage: String?
    @Published var uploadMessage: String?
    @Published var liveMessage: String?
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isLoadingReports = false
    @Published private(set) var isUploadingReport = false

    let authManager = AuthManager()
    let reportRepository = ReportRepository()
    let locationService = LocationManager()
    private(set) lazy var reportCreationService: ReportCreationService = ReportCreationService(repository: reportRepository)

    private var cancellables = Set<AnyCancellable>()
    private var recentlySavedLabels: [String: Date] = [:]

    var isAdmin: Bool { userProfile?.type == "admin" }

    init() {
        bindManagers()
    }

    func signIn(email: String, password: String) {
        Task { await authManager.login(email: email, password: password) }
    }

    func register(username: String, email: String, password: String) {
        Task { await authManager.register(email: email, password: password, displayName: username) }
    }

    func signOut() {
        authManager.logout()
    }

    func refreshReports() {
        guard authManager.isAuthenticated else { return }
        reportRepository.fetchReports()
    }

    func createManualReport(
        image: UIImage?,
        hazardType: String,
        detection: DetectionCandidate? = nil
    ) {
        guard let userId = authManager.user?.uid else {
            uploadMessage = AppBackendError.unauthenticated.localizedDescription
            return
        }
        guard let coordinate = locationService.currentCoordinate else {
            uploadMessage = AppBackendError.missingLocation.localizedDescription
            return
        }

        let draft = ReportDraft(
            source: .manualUpload,
            hazardType: hazardType,
            rawLabel: detection?.label,
            confidence: detection.map { Double($0.confidence) },
            imageData: image?.jpegData(compressionQuality: 0.8),
            boundingBox: detection.map { CodableRect($0.boundingBox) },
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            locationSource: .gps
        )

        isUploadingReport = true
        uploadMessage = nil
        Task {
            do {
                try await reportCreationService.submit(draft, userId: userId, userProfile: userProfile)
                uploadMessage = "Report saved."
            } catch {
                uploadMessage = error.localizedDescription
            }
            isUploadingReport = false
        }
    }

    func createUploadedReport(
        image: UIImage,
        hazardType: String,
        coordinate: CLLocationCoordinate2D,
        address: String,
        detections: [DetectionCandidate]
    ) {
        guard let userId = authManager.user?.uid else {
            uploadMessage = AppBackendError.unauthenticated.localizedDescription
            return
        }
        guard !detections.isEmpty else {
            uploadMessage = "Cannot save: missing detection data"
            return
        }

        let draft = ReportDraft(
            source: .manualUpload,
            hazardType: hazardType,
            rawLabel: hazardType,
            confidence: detections.map(\.confidence).max().map(Double.init),
            imageData: image.jpegData(compressionQuality: 0.95),
            boundingBox: detections.first.map { CodableRect($0.boundingBox) },
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            address: address,
            locationSource: .gps
        )

        isUploadingReport = true
        uploadMessage = nil
        Task {
            do {
                try await reportCreationService.submit(draft, userId: userId, userProfile: userProfile)
                uploadMessage = "Report saved."
            } catch {
                uploadMessage = error.localizedDescription
            }
            isUploadingReport = false
        }
    }

    func submitLiveReport(_ trigger: LiveReportTrigger) {
        guard let userId = authManager.user?.uid else {
            liveMessage = AppBackendError.unauthenticated.localizedDescription
            return
        }
        guard shouldSaveLiveReport(label: trigger.label) else { return }
        guard let location = locationService.currentLocation else {
            liveMessage = AppBackendError.missingLocation.localizedDescription
            return
        }
        guard !hasNearbyDuplicate(
            label: trigger.label,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ) else {
            liveMessage = "Skipped duplicate \(trigger.label)."
            return
        }

        let coordinate = location.coordinate
        recentlySavedLabels[trigger.label] = Date()

        let annotated = ImageAnnotator.drawBoundingBoxes(on: trigger.image, detections: [trigger.candidate])
        let draft = ReportDraft(
            source: .liveDetectionCandidate,
            hazardType: trigger.label,
            rawLabel: trigger.label,
            confidence: Double(trigger.confidence),
            imageData: annotated.jpegData(compressionQuality: 0.8),
            boundingBox: CodableRect(trigger.boundingBox),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            locationSource: .gps,
            notes: "Live detection"
        )

        liveMessage = "Saving \(trigger.label)..."
        Task {
            do {
                try await reportCreationService.submit(draft, userId: userId, userProfile: userProfile)
                liveMessage = "Saved \(trigger.label) report."
            } catch {
                recentlySavedLabels.removeValue(forKey: trigger.label)
                liveMessage = error.localizedDescription
            }
        }
    }

    private func bindManagers() {
        authManager.$user
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                guard let self else { return }
                if let user {
                    self.currentUser = AppUser(id: user.uid, email: user.email ?? "")
                    self.locationService.requestPermission()
                    self.reportRepository.fetchReports()
                } else {
                    self.currentUser = nil
                    self.reportRepository.stopListening()
                }
            }
            .store(in: &cancellables)

        authManager.$userProfile
            .receive(on: DispatchQueue.main)
            .assign(to: &$userProfile)

        authManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$authMessage)

        authManager.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAuthenticating)

        reportRepository.$reports
            .receive(on: DispatchQueue.main)
            .assign(to: &$reports)

        reportRepository.$errorMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$dashboardMessage)

        reportRepository.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoadingReports)

        reportRepository.$isUploading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isUploadingReport)
    }

    private func shouldSaveLiveReport(label: String) -> Bool {
        guard let lastSave = recentlySavedLabels[label] else { return true }
        return Date().timeIntervalSince(lastSave) >= 10
    }

    private func hasNearbyDuplicate(label: String, latitude: Double, longitude: Double) -> Bool {
        let current = CLLocation(latitude: latitude, longitude: longitude)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let recent = reports
            .filter { $0.hazardType == label }
            .sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
            .prefix(10)

        return recent.contains { report in
            guard report.hazardType == label else { return false }
            guard let createdAt = report.createdAt, now - createdAt < 30_000 else { return false }
            let reportLocation = CLLocation(latitude: report.coordinate.latitude, longitude: report.coordinate.longitude)
            return current.distance(from: reportLocation) < 5
        }
    }
}

enum TrackState: String {
    case tentative
    case confirmed
    case vanished
    case reported
    case deleted
}

struct TrackedOverlay: Identifiable, Equatable {
    let id: Int
    var label: String
    var state: TrackState
    var age: Int
    var currentBoundingBox: CGRect
    var targetBoundingBox: CGRect
    var confidence: Float

    var displayLabel: String {
        state == .confirmed ? label : "\(label) (?)"
    }

    var color: Color {
        switch state {
        case .tentative: return .yellow
        case .confirmed: return .appSuccess
        case .vanished: return .appDanger
        case .reported, .deleted: return .appDark400
        }
    }
}

struct LiveReportTrigger {
    let candidate: DetectionCandidate
    let image: UIImage

    var label: String { candidate.label }
    var confidence: Float { candidate.confidence }
    var boundingBox: CGRect { candidate.boundingBox }
}

struct DetectionTracker {
    private var active: [TrackedDetection] = []
    private var nextID = 1
    private let maxAge = 15
    private let minHits = 1
    private let iouThreshold: CGFloat = 0.30

    mutating func reset() {
        active = []
        nextID = 1
    }

    mutating func update(
        with detections: [DetectionCandidate],
        frame: UIImage?,
        speed: CLLocationSpeed
    ) -> (overlays: [TrackedOverlay], reports: [LiveReportTrigger]) {
        let confidenceThreshold: Float = speed > 13.8 ? 0.30 : 0.40
        let filtered = detections.filter { $0.confidence >= confidenceThreshold }

        for index in active.indices where active[index].state != .reported {
            active[index].age += 1
        }

        var matchedDetections = Set<Int>()

        for index in active.indices {
            guard active[index].state != .reported else { continue }
            var bestIoU: CGFloat = 0
            var bestDetectionIndex: Int?

            for detectionIndex in filtered.indices where !matchedDetections.contains(detectionIndex) {
                let detection = filtered[detectionIndex]
                guard detection.label == active[index].label else { continue }
                let iou = active[index].candidate.boundingBox.iou(with: detection.boundingBox)
                if iou > bestIoU, iou > iouThreshold {
                    bestIoU = iou
                    bestDetectionIndex = detectionIndex
                }
            }

            if let bestDetectionIndex {
                let detection = filtered[bestDetectionIndex]
                active[index].velocity = CGVector(
                    dx: detection.boundingBox.minX - active[index].candidate.boundingBox.minX,
                    dy: detection.boundingBox.minY - active[index].candidate.boundingBox.minY
                )
                active[index].candidate = detection
                active[index].age = 0
                active[index].hits += 1

                if active[index].state == .tentative, active[index].hits >= minHits {
                    active[index].state = .confirmed
                } else if active[index].state == .vanished {
                    active[index].state = .confirmed
                }

                if let frame {
                    active[index].appendFrame(image: frame, candidate: detection)
                }
                matchedDetections.insert(bestDetectionIndex)
            } else if active[index].state == .confirmed {
                active[index].state = .vanished
            }
        }

        for detectionIndex in filtered.indices where !matchedDetections.contains(detectionIndex) {
            let detection = filtered[detectionIndex]
            var track = TrackedDetection(
                id: nextID,
                candidate: detection,
                hits: 1,
                age: 0,
                state: .tentative
            )
            if let frame {
                track.appendFrame(image: frame, candidate: detection)
            }
            active.append(track)
            nextID += 1
        }

        var reports: [LiveReportTrigger] = []

        for index in active.indices {
            if active[index].state == .vanished, active[index].age > maxAge {
                if let frame = active[index].bestFrame, active[index].isInReportZone(imageSize: frame.image.size) {
                    active[index].state = .reported
                    reports.append(LiveReportTrigger(candidate: frame.candidate, image: frame.image))
                } else {
                    active[index].state = .deleted
                }
            } else if active[index].state == .tentative, active[index].age > 2 {
                active[index].state = .deleted
            }
        }

        let overlays = active.compactMap { track -> TrackedOverlay? in
            guard track.state != .deleted, track.state != .reported else { return nil }
            var predicted = track.candidate.boundingBox
            if track.age > 0 {
                predicted.origin.x += track.velocity.dx * CGFloat(track.age)
                predicted.origin.y += track.velocity.dy * CGFloat(track.age)
            }
            return TrackedOverlay(
                id: track.id,
                label: track.label,
                state: track.state,
                age: track.age,
                currentBoundingBox: predicted,
                targetBoundingBox: predicted,
                confidence: track.candidate.confidence
            )
        }

        active.removeAll { $0.state == .deleted || $0.state == .reported }
        return (overlays, reports)
    }
}

struct DetectionCandidate {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}

private struct DetectionFrame {
    let image: UIImage
    let candidate: DetectionCandidate
    let score: CGFloat
}

private struct TrackedDetection {
    let id: Int
    var candidate: DetectionCandidate
    var hits: Int
    var age: Int
    var state: TrackState
    var velocity: CGVector = .zero
    var frameBuffer: [DetectionFrame] = []

    var label: String { candidate.label }
    var bestFrame: DetectionFrame? { frameBuffer.first }

    mutating func appendFrame(image: UIImage, candidate: DetectionCandidate) {
        let rect = DetectionGeometry.visionRectToImageRect(candidate.boundingBox, imageSize: image.size)
        let frameScore = CGFloat(candidate.confidence) * rect.width * rect.height
        frameBuffer.append(DetectionFrame(image: image, candidate: candidate, score: frameScore))
        frameBuffer.sort { $0.score > $1.score }
        if frameBuffer.count > 5 {
            frameBuffer.removeLast(frameBuffer.count - 5)
        }
    }

    func isInReportZone(imageSize: CGSize) -> Bool {
        let rect = DetectionGeometry.visionRectToImageRect(candidate.boundingBox, imageSize: imageSize)
        return rect.maxY > imageSize.height * 0.6
    }
}

enum ImageAnnotator {
    static func drawBoundingBox(on image: UIImage, label: String, box: CGRect) -> UIImage {
        drawBoundingBoxes(
            on: image,
            detections: [DetectionCandidate(label: label, confidence: 0, boundingBox: box)]
        )
    }

    static func drawBoundingBoxes(on image: UIImage, detections: [DetectionCandidate]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let scaleFactor = max(image.size.width / 600, 1)
            for detection in detections {
                let rect = DetectionGeometry.visionRectToImageRect(detection.boundingBox, imageSize: image.size)
                UIColor.systemGreen.setStroke()
                context.cgContext.setLineWidth(4 * scaleFactor)
                context.cgContext.stroke(rect)

                let fontSize = 16 * scaleFactor
                let label = "\(detection.label) \(Int(detection.confidence * 100))%"
                let font = UIFont.boldSystemFont(ofSize: fontSize)
                let labelSize = (label as NSString).size(withAttributes: [.font: font])
                let padX = 8 * scaleFactor
                let padY = 6 * scaleFactor
                let labelRect = CGRect(
                    x: rect.minX,
                    y: max(rect.minY - labelSize.height - padY * 2, 0),
                    width: labelSize.width + padX * 2,
                    height: labelSize.height + padY * 2
                )

                UIColor.systemGreen.setFill()
                context.cgContext.fill(labelRect)
                (label as NSString).draw(
                    at: CGPoint(x: labelRect.minX + padX, y: labelRect.minY + padY),
                    withAttributes: [
                        .font: font,
                        .foregroundColor: UIColor.white
                    ]
                )
            }
        }
    }
}

enum DetectionGeometry {
    static func visionRectToImageRect(_ rect: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * imageSize.width,
            y: (1 - rect.maxY) * imageSize.height,
            width: rect.width * imageSize.width,
            height: rect.height * imageSize.height
        )
    }

    static func visionRectToAspectFillRect(
        _ rect: CGRect,
        imageSize: CGSize,
        containerSize: CGSize
    ) -> CGRect {
        let imageRect = visionRectToImageRect(rect, imageSize: imageSize)
        let scale = max(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let xOffset = (scaledSize.width - containerSize.width) / 2
        let yOffset = (scaledSize.height - containerSize.height) / 2

        return CGRect(
            x: imageRect.minX * scale - xOffset,
            y: imageRect.minY * scale - yOffset,
            width: imageRect.width * scale,
            height: imageRect.height * scale
        )
    }

    static func visionRectToAspectFitRect(
        _ rect: CGRect,
        imageSize: CGSize,
        containerSize: CGSize
    ) -> CGRect {
        let imageRect = visionRectToImageRect(rect, imageSize: imageSize)
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let xInset = (containerSize.width - scaledSize.width) / 2
        let yInset = (containerSize.height - scaledSize.height) / 2

        return CGRect(
            x: imageRect.minX * scale + xInset,
            y: imageRect.minY * scale + yInset,
            width: imageRect.width * scale,
            height: imageRect.height * scale
        )
    }
}

private extension CGRect {
    func iou(with other: CGRect) -> CGFloat {
        let intersection = self.intersection(other)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = width * height + other.width * other.height - intersectionArea
        return unionArea <= 0 ? 0 : intersectionArea / unionArea
    }
}
