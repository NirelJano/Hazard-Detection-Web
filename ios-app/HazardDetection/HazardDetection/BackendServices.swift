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
                    self.reports = documents.compactMap { document in
                        do {
                            return try document.data(as: HazardReport.self)
                        } catch {
                            print("Decode error: \(error)")
                            return nil
                        }
                    }
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
        userId: String
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
            
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            var address: String? = nil
            do {
                address = try await GeocodingService.shared.reverseGeocode(coordinate: coordinate)
            } catch {
                print("Geocoding failed: \(error)")
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yy HH:mm"
            let dateString = formatter.string(from: Date())
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
                
                let report = HazardReport(
                    docId: reportRef.documentID,
                    numericId: newCount,
                    hazardType: type,
                    date: dateString,
                    description: description,
                    coordinate: GeoPoint(latitude: lat, longitude: lng),
                    address: address,
                    imageUrl: imageUrl,
                    status: "new",
                    reportedBy: reportedBy,
                    createdAt: nil
                )
                
                do {
                    try transaction.setData(from: report, forDocument: reportRef)
                } catch let encodeError as NSError {
                    errorPointer?.pointee = encodeError
                    return nil
                }
                
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

    func createManualReport(image: UIImage?, hazardType: String) {
        guard let userId = authManager.user?.uid else {
            uploadMessage = AppBackendError.unauthenticated.localizedDescription
            return
        }
        guard let coordinate = locationService.currentCoordinate else {
            uploadMessage = AppBackendError.missingLocation.localizedDescription
            return
        }

        isUploadingReport = true
        uploadMessage = nil
        Task {
            do {
                try await reportRepository.addReport(
                    type: hazardType,
                    description: nil,
                    lat: coordinate.latitude,
                    lng: coordinate.longitude,
                    image: image,
                    userProfile: userProfile,
                    userId: userId
                )
                uploadMessage = "Report saved."
            } catch {
                uploadMessage = error.localizedDescription
            }
            isUploadingReport = false
        }
    }

    func submitLiveReport(label: String, boundingBox: CGRect, image: UIImage?) {
        guard let userId = authManager.user?.uid else {
            liveMessage = AppBackendError.unauthenticated.localizedDescription
            return
        }
        guard shouldSaveLiveReport(label: label) else { return }
        guard let coordinate = locationService.currentCoordinate else {
            liveMessage = AppBackendError.missingLocation.localizedDescription
            return
        }
        guard !hasNearbyDuplicate(label: label, latitude: coordinate.latitude, longitude: coordinate.longitude) else {
            liveMessage = "Skipped duplicate \(label)."
            return
        }

        let annotated = image.map { ImageAnnotator.drawBoundingBox(on: $0, label: label, box: boundingBox) }
        liveMessage = "Saving \(label)..."
        recentlySavedLabels[label] = Date()

        Task {
            do {
                try await reportRepository.addReport(
                    type: label,
                    description: "Live detection",
                    lat: coordinate.latitude,
                    lng: coordinate.longitude,
                    image: annotated,
                    userProfile: userProfile,
                    userId: userId
                )
                liveMessage = "Saved \(label) report."
            } catch {
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
        return reports.contains { report in
            guard report.hazardType == label else { return false }
            let reportLocation = CLLocation(latitude: report.coordinate.latitude, longitude: report.coordinate.longitude)
            return current.distance(from: reportLocation) < 5
        }
    }
}

struct DetectionTracker {
    private var active: [TrackedDetection] = []
    private var nextID = 1
    private let maxAge = 3
    private let iouThreshold: CGFloat = 0.30

    mutating func update(with detections: [DetectionCandidate]) -> DetectionCandidate? {
        var matchedIDs = Set<Int>()
        var report: DetectionCandidate?

        for detection in detections {
            if let index = bestMatch(for: detection, matchedIDs: matchedIDs) {
                active[index].candidate = detection
                active[index].age = 0
                active[index].hits += 1
                matchedIDs.insert(active[index].id)
            } else {
                active.append(TrackedDetection(id: nextID, candidate: detection, hits: 1, age: 0))
                matchedIDs.insert(nextID)
                nextID += 1
            }
        }

        for index in active.indices {
            if !matchedIDs.contains(active[index].id) {
                active[index].age += 1
            }
        }

        if let vanished = active.first(where: { $0.age >= maxAge && $0.hits >= 1 && $0.candidate.boundingBox.minY < 0.40 }) {
            report = vanished.candidate
        }

        active.removeAll { $0.age >= maxAge }
        return report
    }

    private func bestMatch(for detection: DetectionCandidate, matchedIDs: Set<Int>) -> Int? {
        active.indices
            .filter { active[$0].candidate.label == detection.label && !matchedIDs.contains(active[$0].id) }
            .map { ($0, active[$0].candidate.boundingBox.iou(with: detection.boundingBox)) }
            .filter { $0.1 >= iouThreshold }
            .max { $0.1 < $1.1 }?
            .0
    }
}

struct DetectionCandidate {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}

private struct TrackedDetection {
    let id: Int
    var candidate: DetectionCandidate
    var hits: Int
    var age: Int
}

enum ImageAnnotator {
    static func drawBoundingBox(on image: UIImage, label: String, box: CGRect) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let rect = CGRect(
                x: box.minX * image.size.width,
                y: (1 - box.maxY) * image.size.height,
                width: box.width * image.size.width,
                height: box.height * image.size.height
            )
            UIColor.systemGreen.setStroke()
            context.cgContext.setLineWidth(4)
            context.cgContext.stroke(rect)

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.black,
                .backgroundColor: UIColor.systemGreen
            ]
            label.draw(at: CGPoint(x: rect.minX, y: max(rect.minY - 24, 4)), withAttributes: attributes)
        }
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
