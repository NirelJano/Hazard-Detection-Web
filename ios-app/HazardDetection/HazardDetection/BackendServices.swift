import Combine
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftData
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
        // Forward to the multi-detection overload using a single-element array (backward compat shim)
        let singleDetection: [DetectionCandidate]
        if let label = detectionLabel {
            singleDetection = [DetectionCandidate(
                label: label,
                confidence: Float(detectionConfidence ?? 0),
                boundingBox: detectionBoundingBox?.rect ?? .zero
            )]
        } else {
            singleDetection = []
        }
        let source: DetectionSource = {
            switch detectionSource {
            case DetectionSource.liveCamera.rawValue:
                return .liveCamera
            case DetectionSource.liveAutoDetection.rawValue:
                return .liveAutoDetection
            default:
                return .upload
            }
        }()
        try await addReport(
            type: type,
            description: description,
            lat: lat,
            lng: lng,
            address: address,
            image: image,
            userProfile: userProfile,
            userId: userId,
            createdAtMillis: createdAtMillis,
            detections: singleDetection,
            detectionSource: source
        )
    }

    /// Multi-detection overload — used by DetectionReportPipeline for both live and upload flows.
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
        detections: [DetectionCandidate],
        detectionSource: DetectionSource,
        metadata: FrameMetadata? = nil
    ) async throws {
        guard Auth.auth().currentUser?.uid == userId else {
            throw AppBackendError.unauthenticated
        }

        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        let primaryDetection = detections.max(by: { $0.confidence < $1.confidence })
        let primaryLabel = primaryDetection?.label ?? type
        let primaryConfidence = primaryDetection.map { Double($0.confidence) }
        let primaryBoundingBox = primaryDetection.map { DetectionBoundingBox(from: $0.boundingBox) }

        do {
            var imageUrl: String? = nil
            if let image {
                do {
                    imageUrl = try await CloudinaryService.shared.uploadImage(image)
                } catch {
                    print("[addReport] Cloudinary upload failed, saving without image: \(error)")
                }
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
                    "hazardType": primaryLabel,
                    "date": dateString,
                    "createdAt": createdAtMillis,
                    "coordinate": GeoPoint(latitude: lat, longitude: lng),
                    "address": address ?? "",
                    "imageUrl": imageUrl ?? "",
                    "reportedBy": reportedBy,
                    "status": "new"
                ]
                if let description { data["description"] = description }
                if let metadata {
                    data["source"] = detectionSource.rawValue
                    data["timestamp"] = Timestamp(date: metadata.timestamp)
                    if let speed = metadata.speed, speed >= 0 { data["speedMetersPerSecond"] = speed }
                    if let heading = metadata.heading, heading >= 0 { data["heading"] = heading }
                    if let horizontalAccuracy = metadata.horizontalAccuracy { data["horizontalAccuracy"] = horizontalAccuracy }
                    data["imageWidth"] = metadata.imageWidth
                    data["imageHeight"] = metadata.imageHeight
                    if let modelVersion = metadata.modelVersion { data["modelVersion"] = modelVersion }
                }

                // Legacy single-detection fields (always written for web dashboard compatibility)
                data["detectedLabel"] = primaryLabel
                if let primaryConfidence { data["detectionConfidence"] = primaryConfidence }
                data["detectionSource"] = detectionSource.rawValue
                if let primaryBoundingBox { data["detectionBoundingBox"] = primaryBoundingBox.dictionary }

                // New multi-detection fields
                data["primaryLabel"] = primaryLabel
                if let primaryConfidence { data["primaryConfidence"] = primaryConfidence }
                data["detections"] = detections.map { d -> [String: Any] in
                    [
                        "label": d.label,
                        "confidence": Double(d.confidence),
                        "boundingBox": DetectionBoundingBox(from: d.boundingBox).dictionary
                    ]
                }

                transaction.setData(data, forDocument: reportRef)
                return newCount
            })
            print("Firestore report created with id: \(newId ?? -1), source: \(detectionSource.rawValue), detections: \(detections.count)")
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

    /// Commits a queued report to Firestore using `clientReportId` as the
    /// document ID so retries are safe: if the document already exists the
    /// transaction is a no-op and the pending report is marked committed.
    func commitPendingReport(
        clientReportId: String,
        draft: ReportDraft,
        imageUrl: String?,
        resolvedAddress: String?,
        userId: String,
        reportedBy: String,
        queuedAt: Date,
        uploadAttempts: Int
    ) async throws {
        guard Auth.auth().currentUser?.uid == userId else {
            throw AppBackendError.unauthenticated
        }
        guard let lat = draft.latitude, let lng = draft.longitude else {
            throw ReportValidationError.missingLocation
        }

        let detectionSource: String?
        switch draft.source {
        case .liveDetectionCandidate: detectionSource = "live_camera"
        case .manualUpload:           detectionSource = draft.rawLabel != nil ? "manual_image" : nil
        case .postProcessedSession:   detectionSource = "post_processed"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy HH:mm"
        let dateString = formatter.string(from: draft.createdAt)
        let createdAtMillis = Int64(draft.createdAt.timeIntervalSince1970 * 1000)
        let queuedAtMillis  = Int64(queuedAt.timeIntervalSince1970 * 1000)

        let reportRef  = db.collection("reports").document(clientReportId)
        let counterRef = db.collection("metadata").document("reportCounter")

        do {
            _ = try await db.runTransaction { transaction, errorPointer -> Any? in
                let counterDoc: DocumentSnapshot
                let reportDoc: DocumentSnapshot
                do {
                    counterDoc = try transaction.getDocument(counterRef)
                    reportDoc  = try transaction.getDocument(reportRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                // Idempotency: document already committed on a previous attempt.
                if reportDoc.exists { return nil }

                let oldCount = counterDoc.data()?["count"] as? Int ?? 0
                let newCount = oldCount + 1
                transaction.setData(["count": newCount], forDocument: counterRef, merge: true)

                var data: [String: Any] = [
                    "id":             newCount,
                    "clientReportId": clientReportId,
                    "hazardType":     draft.hazardType,
                    "date":           dateString,
                    "createdAt":      createdAtMillis,
                    "coordinate":     GeoPoint(latitude: lat, longitude: lng),
                    "address":        resolvedAddress ?? "",
                    "imageUrl":       imageUrl ?? "",
                    "reportedBy":     reportedBy,
                    "status":         "new",
                    "queuedAt":       queuedAtMillis,
                    "uploadAttempts": uploadAttempts,
                ]
                if let notes = draft.notes { data["description"] = notes }
                if let rawLabel = draft.rawLabel { data["detectedLabel"] = rawLabel }
                if let confidence = draft.confidence { data["detectionConfidence"] = confidence }
                if let source = detectionSource { data["detectionSource"] = source }
                if let bbox = draft.boundingBox {
                    data["detectionBoundingBox"] = DetectionBoundingBox(from: bbox.cgRect).dictionary
                }
                if let meta = draft.metadata {
                    if let sessionId = meta.sourceSessionId {
                        data["sourceSessionId"] = sessionId.uuidString
                    }
                    if let candidateIds = meta.sourceCandidateIds, !candidateIds.isEmpty {
                        data["sourceCandidateIds"] = candidateIds.map { $0.uuidString }
                    }
                    if let threshold = meta.effectiveThreshold {
                        data["effectiveThreshold"] = threshold
                    }
                    if let reasons = meta.gateReasons, !reasons.isEmpty {
                        data["gateReasons"] = reasons
                    }
                    if meta.postProcessed == true {
                        data["postProcessed"] = true
                    }
                }

                transaction.setData(data, forDocument: reportRef)
                return newCount
            }
            print("Firestore report committed: \(clientReportId)")
        } catch {
            print("Failed to commit pending report \(clientReportId): \(error.localizedDescription)")
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
    let motionService = MotionService()
    let roadAttentionService = RoadAttentionService()
    let pipManager = PictureInPictureManager()
    let detectionPreferences = DetectionPreferences()
    let motionSignalProvider = MotionSignalProvider()
    private(set) lazy var reportCreationService: ReportCreationService = ReportCreationService()

    @Published var autoSaveSnapshotsEnabled: Bool = UserDefaults.standard.object(forKey: "autoSaveSnapshots") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoSaveSnapshotsEnabled, forKey: "autoSaveSnapshots") }
    }

    private(set) lazy var pipeline: DetectionReportPipeline = {
        DetectionReportPipeline(
            repository: reportRepository,
            attentionService: roadAttentionService,
            aggregator: CandidateAggregator(),
            deduplication: ReportDeduplicationService(repository: reportRepository),
            motionService: motionService
        )
    }()

    private var cancellables = Set<AnyCancellable>()

    var isAdmin: Bool { userProfile?.type == "admin" }

    init() {
        bindManagers()
        BackgroundUploadCoordinator.shared.start(
            container: HazardModelContainer.shared.container,
            repository: reportRepository
        )
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

    // MARK: - Report Creation (via DetectionReportPipeline)

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
                uploadMessage = "Report queued for upload."
            } catch {
                uploadMessage = error.localizedDescription
            }
            isUploadingReport = false
        }
    }

    /// Saves a manually triggered upload report through the shared pipeline.
    func createUploadedReport(
        image: UIImage,
        hazardType: String,
        coordinate: CLLocationCoordinate2D,
        address: String,
        detections: [DetectionCandidate],
        description: String? = nil
    ) {
        guard let userId = authManager.user?.uid else {
            uploadMessage = AppBackendError.unauthenticated.localizedDescription
            return
        }
        guard !detections.isEmpty else {
            uploadMessage = "Cannot save: missing detection data"
            return
        }
        isUploadingReport = true
        uploadMessage = nil
        Task {
            let metadata = buildMetadata(
                lat: coordinate.latitude,
                lng: coordinate.longitude,
                imageSize: image.size
            )
            let input = DetectionInput(
                image: image,
                source: .upload,
                metadata: metadata,
                detections: detections,
                frameId: UUID(),
                description: description,
                preResolvedAddress: address.isEmpty ? nil : address
            )
            do {
                let result = try await pipeline.process(input: input, userId: userId, userProfile: userProfile)
                switch result.outcome {
                case .saved: uploadMessage = "Report saved."
                case .duplicate: uploadMessage = "Skipped duplicate report."
                case .belowThreshold: uploadMessage = "No hazard detected."
                case .error(let e): uploadMessage = e.localizedDescription
                default: break
                }
            } catch {
                uploadMessage = error.localizedDescription
            }
            isUploadingReport = false
        }
    }

    /// Submits a live detection report through the shared pipeline.
    func submitLiveReport(_ trigger: LiveReportTrigger) {
        guard let userId = authManager.user?.uid else {
            liveMessage = AppBackendError.unauthenticated.localizedDescription
            return
        }
        guard let location = locationService.currentLocation else {
            liveMessage = AppBackendError.missingLocation.localizedDescription
            return
        }
        liveMessage = "Confirming \(trigger.label)..."
        Task {
            var metadata = buildMetadata(
                lat: location.coordinate.latitude,
                lng: location.coordinate.longitude,
                imageSize: trigger.image.size
            )
            metadata.speed = location.speed
            metadata.heading = location.course
            metadata.horizontalAccuracy = location.horizontalAccuracy
            let input = DetectionInput(
                image: trigger.image,
                source: .liveCamera,
                metadata: metadata,
                detections: [trigger.candidate],
                frameId: UUID()
            )
            do {
                let result = try await pipeline.process(input: input, userId: userId, userProfile: userProfile)
                switch result.outcome {
                case .saved: liveMessage = "Saved \(trigger.label) report."
                case .duplicate: liveMessage = "Skipped duplicate \(trigger.label)."
                case .qualityGateFailed(let hint): liveMessage = hint.rawValue
                case .notConfirmed: liveMessage = nil
                case .error(let e): liveMessage = e.localizedDescription
                default: break
                }
            } catch {
                liveMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Metadata builder

    func buildMetadata(lat: Double, lng: Double, imageSize: CGSize) -> FrameMetadata {
        FrameMetadata(
            timestamp: Date(),
            latitude: lat,
            longitude: lng,
            horizontalAccuracy: locationService.currentLocation?.horizontalAccuracy,
            heading: locationService.currentLocation?.course,
            speed: locationService.currentLocation?.speed,
            imageWidth: Int(imageSize.width),
            imageHeight: Int(imageSize.height),
            modelVersion: "best_v1"
        )
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
    var isFresh: Bool

    var displayLabel: String {
        state == .confirmed ? label : "\(label) (?)"
    }

    var color: Color {
        switch state {
        case .tentative: return .yellow
        case .confirmed: return isFresh ? .appSuccess : .appWarning
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
    private let maxAge = 6
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
        let confidenceThreshold: Float = speed > DetectionConfig.highSpeedMSCutoff
            ? DetectionConfig.highSpeedThreshold
            : DetectionConfig.displayThreshold
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
            let box = track.candidate.boundingBox
            return TrackedOverlay(
                id: track.id,
                label: track.label,
                state: track.state,
                age: track.age,
                currentBoundingBox: box,
                targetBoundingBox: box,
                confidence: track.candidate.confidence,
                isFresh: track.age == 0
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
        // Keep only the 2 best frames — enough for a quality report image while
        // bounding memory to ~2.4 MB per tracked detection at 640x480.
        if frameBuffer.count > 2 {
            frameBuffer.removeLast(frameBuffer.count - 2)
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

// CGRect.iou(with:) is defined in ReportDeduplicationService.swift
