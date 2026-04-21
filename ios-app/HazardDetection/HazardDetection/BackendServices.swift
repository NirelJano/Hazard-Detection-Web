import CoreLocation
import Foundation
import SwiftUI
import UIKit

struct AppConfig {
    let firebaseAPIKey: String
    let firebaseProjectID: String
    let cloudinaryCloudName: String
    let cloudinaryUploadPreset: String
    let mapboxAccessToken: String

    static let current = AppConfig(
        firebaseAPIKey: Bundle.main.object(forInfoDictionaryKey: "FirebaseAPIKey") as? String ?? "",
        firebaseProjectID: Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String ?? "",
        cloudinaryCloudName: Bundle.main.object(forInfoDictionaryKey: "CloudinaryCloudName") as? String ?? "",
        cloudinaryUploadPreset: Bundle.main.object(forInfoDictionaryKey: "CloudinaryUploadPreset") as? String ?? "",
        mapboxAccessToken: Bundle.main.object(forInfoDictionaryKey: "MapboxAccessToken") as? String ?? ""
    )

    var isBackendConfigured: Bool {
        !firebaseAPIKey.isEmpty && !firebaseProjectID.isEmpty
    }

    var isMediaConfigured: Bool {
        !cloudinaryCloudName.isEmpty && !cloudinaryUploadPreset.isEmpty
    }
}

struct AppUser: Identifiable, Equatable {
    let id: String
    let username: String
    let email: String
    let type: String

    var displayName: String { username.isEmpty ? email : username }
    var isAdmin: Bool { type == "admin" }
}

struct HazardReport: Identifiable, Equatable {
    let documentID: String
    let numericID: Int
    let hazardType: String
    let date: String
    let createdAt: Int?
    let latitude: Double
    let longitude: Double
    let address: String
    let imageURL: String
    let reportedBy: String
    let status: String

    var id: String { documentID }
}

struct LocationSnapshot {
    let latitude: Double
    let longitude: Double
    let address: String
}

enum AppBackendError: LocalizedError {
    case missingConfig(String)
    case invalidCredentials
    case invalidPasswordPolicy
    case invalidResponse
    case http(String)
    case missingLocation
    case missingImage

    var errorDescription: String? {
        switch self {
        case .missingConfig(let key):
            return "Missing configuration: \(key). Add it to Info.plist before using backend features."
        case .invalidCredentials:
            return "Enter a valid email and password."
        case .invalidPasswordPolicy:
            return "Password must be at least 8 characters and include uppercase and lowercase letters."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .http(let message):
            return message
        case .missingLocation:
            return "Location is unavailable. Enable location permission and try again."
        case .missingImage:
            return "Choose an image before submitting the report."
        }
    }
}

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var currentUser: AppUser?
    @Published private(set) var reports: [HazardReport] = []
    @Published var authMessage: String?
    @Published var dashboardMessage: String?
    @Published var uploadMessage: String?
    @Published var liveMessage: String?
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isLoadingReports = false
    @Published private(set) var isUploadingReport = false

    let locationService = LocationService()

    private let config = AppConfig.current
    private let authClient: FirebaseAuthClient
    private let firestore: FirestoreRESTClient
    private let cloudinary: CloudinaryService
    private let geocoder: GeocodingService
    private var authSession: AuthSession?
    private var reportRefreshTask: Task<Void, Never>?
    private var recentlySavedLabels: [String: Date] = [:]

    init() {
        self.authClient = FirebaseAuthClient(config: config)
        self.firestore = FirestoreRESTClient(config: config)
        self.cloudinary = CloudinaryService(config: config)
        self.geocoder = GeocodingService(config: config)
        restoreSession()
    }

    func signIn(email: String, password: String) {
        guard config.isBackendConfigured else {
            authMessage = AppBackendError.missingConfig("FirebaseAPIKey/FirebaseProjectID").localizedDescription
            return
        }
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !cleanPassword.isEmpty else {
            authMessage = AppBackendError.invalidCredentials.localizedDescription
            return
        }

        isAuthenticating = true
        authMessage = nil
        Task {
            do {
                let session = try await authClient.signIn(email: cleanEmail, password: cleanPassword)
                try await completeAuth(session: session, fallbackUsername: "")
            } catch {
                authMessage = error.localizedDescription
            }
            isAuthenticating = false
        }
    }

    func register(username: String, email: String, password: String) {
        guard config.isBackendConfigured else {
            authMessage = AppBackendError.missingConfig("FirebaseAPIKey/FirebaseProjectID").localizedDescription
            return
        }
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !cleanUsername.isEmpty else {
            authMessage = AppBackendError.invalidCredentials.localizedDescription
            return
        }
        guard validatePassword(password) else {
            authMessage = AppBackendError.invalidPasswordPolicy.localizedDescription
            return
        }

        isAuthenticating = true
        authMessage = nil
        Task {
            do {
                let session = try await authClient.register(email: cleanEmail, password: password)
                try await firestore.upsertUser(uid: session.uid, username: cleanUsername, email: cleanEmail, idToken: session.idToken)
                try await completeAuth(session: session, fallbackUsername: cleanUsername)
            } catch {
                authMessage = error.localizedDescription
            }
            isAuthenticating = false
        }
    }

    func signOut() {
        authSession = nil
        currentUser = nil
        reports = []
        reportRefreshTask?.cancel()
        UserDefaults.standard.removeObject(forKey: AuthSession.storageKey)
    }

    func refreshReports() {
        guard let authSession else { return }
        isLoadingReports = true
        dashboardMessage = nil
        Task {
            do {
                reports = try await firestore.fetchReports(idToken: authSession.idToken)
            } catch {
                dashboardMessage = error.localizedDescription
            }
            isLoadingReports = false
        }
    }

    func createManualReport(image: UIImage?, hazardType: String) {
        guard let user = currentUser, let authSession else { return }
        guard let image else {
            uploadMessage = AppBackendError.missingImage.localizedDescription
            return
        }

        isUploadingReport = true
        uploadMessage = nil
        Task {
            do {
                let location = try await resolvedLocation()
                let imageURL = try await cloudinary.upload(image: image)
                try await firestore.createReport(
                    hazardType: hazardType,
                    location: location,
                    imageURL: imageURL,
                    reportedBy: user.displayName,
                    createdAt: nil,
                    idToken: authSession.idToken
                )
                uploadMessage = "Report saved."
                refreshReports()
            } catch {
                uploadMessage = error.localizedDescription
            }
            isUploadingReport = false
        }
    }

    func submitLiveReport(label: String, boundingBox: CGRect, image: UIImage?) {
        guard let user = currentUser, let authSession else { return }
        guard shouldSaveLiveReport(label: label) else { return }
        guard let image else {
            liveMessage = AppBackendError.missingImage.localizedDescription
            return
        }

        liveMessage = "Saving \(label)..."
        let annotated = ImageAnnotator.drawBoundingBox(on: image, label: label, box: boundingBox)
        Task {
            do {
                let location = try await resolvedLocation()
                guard !hasNearbyDuplicate(label: label, latitude: location.latitude, longitude: location.longitude) else {
                    liveMessage = "Skipped duplicate \(label)."
                    return
                }
                let imageURL = try await cloudinary.upload(image: annotated)
                try await firestore.createReport(
                    hazardType: label,
                    location: location,
                    imageURL: imageURL,
                    reportedBy: user.displayName,
                    createdAt: Int(Date().timeIntervalSince1970 * 1000),
                    idToken: authSession.idToken
                )
                recentlySavedLabels[label] = Date()
                liveMessage = "Saved \(label) report."
                refreshReports()
            } catch {
                liveMessage = error.localizedDescription
            }
        }
    }

    private func completeAuth(session: AuthSession, fallbackUsername: String) async throws {
        authSession = session
        session.save()
        currentUser = try await firestore.fetchUser(uid: session.uid, idToken: session.idToken)
            ?? AppUser(id: session.uid, username: fallbackUsername, email: session.email, type: "user")
        refreshReports()
        startReportPolling()
        locationService.requestPermission()
    }

    private func restoreSession() {
        guard let session = AuthSession.restore(), config.isBackendConfigured else { return }
        authSession = session
        Task {
            do {
                currentUser = try await firestore.fetchUser(uid: session.uid, idToken: session.idToken)
                    ?? AppUser(id: session.uid, username: "", email: session.email, type: "user")
                refreshReports()
                startReportPolling()
                locationService.requestPermission()
            } catch {
                signOut()
            }
        }
    }

    private func startReportPolling() {
        reportRefreshTask?.cancel()
        reportRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                self?.refreshReports()
            }
        }
    }

    private func resolvedLocation() async throws -> LocationSnapshot {
        guard let coordinate = locationService.currentCoordinate else {
            throw AppBackendError.missingLocation
        }
        let address = await geocoder.reverseGeocode(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return LocationSnapshot(latitude: coordinate.latitude, longitude: coordinate.longitude, address: address)
    }

    private func shouldSaveLiveReport(label: String) -> Bool {
        guard let lastSave = recentlySavedLabels[label] else { return true }
        return Date().timeIntervalSince(lastSave) >= 10
    }

    private func hasNearbyDuplicate(label: String, latitude: Double, longitude: Double) -> Bool {
        let nowMS = Int(Date().timeIntervalSince1970 * 1000)
        return reports.contains { report in
            guard report.hazardType == label else { return false }
            if let createdAt = report.createdAt, nowMS - createdAt > 30_000 { return false }
            let distance = CLLocation(latitude: latitude, longitude: longitude)
                .distance(from: CLLocation(latitude: report.latitude, longitude: report.longitude))
            return distance < 5
        }
    }

    private func validatePassword(_ password: String) -> Bool {
        password.count >= 8
            && password.range(of: "[A-Z]", options: .regularExpression) != nil
            && password.range(of: "[a-z]", options: .regularExpression) != nil
    }
}

struct AuthSession: Codable {
    static let storageKey = "hazard.auth.session"

    let uid: String
    let email: String
    let idToken: String
    let refreshToken: String

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func restore() -> AuthSession? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }
}

final class FirebaseAuthClient {
    private let config: AppConfig
    private let urlSession = URLSession.shared

    init(config: AppConfig) {
        self.config = config
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        try await auth(endpoint: "signInWithPassword", email: email, password: password)
    }

    func register(email: String, password: String) async throws -> AuthSession {
        try await auth(endpoint: "signUp", email: email, password: password)
    }

    private func auth(endpoint: String, email: String, password: String) async throws -> AuthSession {
        guard !config.firebaseAPIKey.isEmpty else { throw AppBackendError.missingConfig("FirebaseAPIKey") }
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:\(endpoint)?key=\(config.firebaseAPIKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ])
        let data = try await perform(request)
        let json = try decodeObject(data)
        return AuthSession(
            uid: json["localId"] as? String ?? "",
            email: json["email"] as? String ?? email,
            idToken: json["idToken"] as? String ?? "",
            refreshToken: json["refreshToken"] as? String ?? ""
        )
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppBackendError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let raw = FirebaseRESTError.message(from: data) ?? "Authentication failed."
            let friendly = FirebaseAuthErrorMapper.friendlyMessage(from: raw)
            throw AppBackendError.http(friendly)
        }
        return data
    }
}

private enum FirebaseAuthErrorMapper {
    static func friendlyMessage(from raw: String) -> String {
        let upper = raw.uppercased()
        if upper.contains("REFERER") {
            return "Requests are blocked due to API key restrictions. In Google Cloud Console, change your Firebase Web API key restrictions to 'iOS apps' (bundle ID) or remove HTTP referrer restrictions."
        }
        if upper.contains("EMAIL_EXISTS") {
            return "This email is already registered."
        }
        if upper.contains("INVALID_EMAIL") {
            return "Enter a valid email address."
        }
        if upper.contains("WEAK_PASSWORD") {
            return "Password is too weak. Use at least 8 characters with upper and lower case."
        }
        if upper.contains("EMAIL_NOT_FOUND") || upper.contains("USER_DISABLED") || upper.contains("INVALID_PASSWORD") {
            return "Invalid email or password."
        }
        if upper.contains("OPERATION_NOT_ALLOWED") {
            return "Email/password sign-in is disabled in Firebase Authentication."
        }
        if upper.contains("TOO_MANY_ATTEMPTS_TRY_LATER") {
            return "Too many attempts. Try again later."
        }
        return raw
    }
}

final class FirestoreRESTClient {
    private let config: AppConfig
    private let urlSession = URLSession.shared

    init(config: AppConfig) {
        self.config = config
    }

    func fetchUser(uid: String, idToken: String) async throws -> AppUser? {
        let request = try authedRequest(path: "users/\(uid)", idToken: idToken)
        do {
            let data = try await perform(request)
            let document = try FirestoreDocument(data: data)
            return document.appUser(uid: uid)
        } catch AppBackendError.http {
            return nil
        }
    }

    func upsertUser(uid: String, username: String, email: String, idToken: String) async throws {
        var request = try authedRequest(path: "users/\(uid)", idToken: idToken)
        request.httpMethod = "PATCH"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "fields": [
                "username": ["stringValue": username],
                "email": ["stringValue": email],
                "createdAt": ["timestampValue": ISO8601DateFormatter().string(from: Date())],
                "type": ["stringValue": "user"]
            ]
        ])
        _ = try await perform(request)
    }

    func fetchReports(idToken: String) async throws -> [HazardReport] {
        let request = try authedRequest(path: "reports", idToken: idToken, queryItems: [
            URLQueryItem(name: "pageSize", value: "100")
        ])
        let data = try await perform(request)
        let json = try decodeObject(data)
        let documents = json["documents"] as? [[String: Any]] ?? []
        return documents.compactMap { FirestoreDocument(raw: $0).hazardReport() }
            .sorted { $0.numericID > $1.numericID }
    }

    func createReport(
        hazardType: String,
        location: LocationSnapshot,
        imageURL: String,
        reportedBy: String,
        createdAt: Int?,
        idToken: String
    ) async throws {
        let transaction = try await beginTransaction(idToken: idToken)
        let nextID = try await nextReportID(transaction: transaction, idToken: idToken)
        let reportID = UUID().uuidString
        let fields = reportFields(
            id: nextID,
            hazardType: hazardType,
            location: location,
            imageURL: imageURL,
            reportedBy: reportedBy,
            createdAt: createdAt
        )

        let commitURL = try firestoreURL(path: ":commit")
        var request = URLRequest(url: commitURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "writes": [
                [
                    "update": [
                        "name": documentName(path: "metadata/reportCounter"),
                        "fields": ["count": ["integerValue": "\(nextID)"]]
                    ]
                ],
                [
                    "update": [
                        "name": documentName(path: "reports/\(reportID)"),
                        "fields": fields
                    ]
                ]
            ],
            "transaction": transaction
        ])
        _ = try await perform(request)
    }

    private func beginTransaction(idToken: String) async throws -> String {
        var request = URLRequest(url: try firestoreURL(path: ":beginTransaction"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [:])
        let data = try await perform(request)
        let json = try decodeObject(data)
        return json["transaction"] as? String ?? ""
    }

    private func nextReportID(transaction: String, idToken: String) async throws -> Int {
        var request = URLRequest(url: try firestoreURL(path: ":batchGet"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "documents": [documentName(path: "metadata/reportCounter")],
            "transaction": transaction
        ])
        let data = try await perform(request)
        let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let found = array?.first?["found"] as? [String: Any]
        let fields = found?["fields"] as? [String: Any]
        let count = FirestoreValue.integer(fields?["count"])
        return count + 1
    }

    private func reportFields(
        id: Int,
        hazardType: String,
        location: LocationSnapshot,
        imageURL: String,
        reportedBy: String,
        createdAt: Int?
    ) -> [String: Any] {
        var fields: [String: Any] = [
            "id": ["integerValue": "\(id)"],
            "hazardType": ["stringValue": hazardType],
            "date": ["stringValue": DateFormatter.reportDate.string(from: Date())],
            "coordinate": ["geoPointValue": ["latitude": location.latitude, "longitude": location.longitude]],
            "address": ["stringValue": location.address],
            "imageUrl": ["stringValue": imageURL],
            "reportedBy": ["stringValue": reportedBy],
            "status": ["stringValue": "new"]
        ]
        if let createdAt {
            fields["createdAt"] = ["integerValue": "\(createdAt)"]
        }
        return fields
    }

    private func authedRequest(path: String, idToken: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        var request = URLRequest(url: try firestoreURL(path: path, queryItems: queryItems))
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func firestoreURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard !config.firebaseProjectID.isEmpty else { throw AppBackendError.missingConfig("FirebaseProjectID") }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "firestore.googleapis.com"
        let root = "/v1/projects/\(config.firebaseProjectID)/databases/(default)/documents"
        components.path = path.hasPrefix(":") ? "\(root)\(path)" : "\(root)/\(path)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw AppBackendError.invalidResponse }
        return url
    }

    private func documentName(path: String) -> String {
        "projects/\(config.firebaseProjectID)/databases/(default)/documents/\(path)"
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppBackendError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = FirebaseRESTError.message(from: data) ?? "Firestore request failed."
            throw AppBackendError.http(message)
        }
        return data
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in currentCoordinate = coordinate }
    }
}

final class GeocodingService {
    private let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func reverseGeocode(latitude: Double, longitude: Double) async -> String {
        guard !config.mapboxAccessToken.isEmpty else { return "Unknown address" }
        var components = URLComponents(string: "https://api.mapbox.com/geocoding/v5/mapbox.places/\(longitude),\(latitude).json")
        components?.queryItems = [
            URLQueryItem(name: "access_token", value: config.mapboxAccessToken),
            URLQueryItem(name: "language", value: "he"),
            URLQueryItem(name: "types", value: "address,place"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else { return "Unknown address" }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try decodeObject(data)
            let features = json["features"] as? [[String: Any]]
            let feature = features?.first
            return feature?["place_name"] as? String ?? "Unknown address"
        } catch {
            return "Unknown address"
        }
    }
}

final class CloudinaryService {
    private let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func upload(image: UIImage) async throws -> String {
        guard config.isMediaConfigured else { throw AppBackendError.missingConfig("CloudinaryCloudName/CloudinaryUploadPreset") }
        guard let imageData = image.jpegData(compressionQuality: 0.82) else { throw AppBackendError.missingImage }

        let boundary = "Boundary-\(UUID().uuidString)"
        let url = URL(string: "https://api.cloudinary.com/v1_1/\(config.cloudinaryCloudName)/image/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartFormData(boundary: boundary)
            .addField(name: "upload_preset", value: config.cloudinaryUploadPreset)
            .addFile(name: "file", filename: "hazard-\(UUID().uuidString).jpg", mimeType: "image/jpeg", data: imageData)
            .finalize()

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppBackendError.http("Cloudinary upload failed.")
        }
        let json = try decodeObject(data)
        guard let url = json["secure_url"] as? String else { throw AppBackendError.invalidResponse }
        return url
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

private struct MultipartFormData {
    let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func addField(name: String, value: String) -> MultipartFormData {
        var copy = self
        copy.data.append("--\(boundary)\r\n")
        copy.data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        copy.data.append("\(value)\r\n")
        return copy
    }

    func addFile(name: String, filename: String, mimeType: String, data fileData: Data) -> MultipartFormData {
        var copy = self
        copy.data.append("--\(boundary)\r\n")
        copy.data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        copy.data.append("Content-Type: \(mimeType)\r\n\r\n")
        copy.data.append(fileData)
        copy.data.append("\r\n")
        return copy
    }

    func finalize() -> Data {
        var copy = data
        copy.append("--\(boundary)--\r\n")
        return copy
    }
}

private enum FirebaseRESTError {
    static func message(from data: Data) -> String? {
        guard
            let json = try? decodeObject(data),
            let error = json["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }
}

private struct FirestoreDocument {
    let name: String
    let fields: [String: Any]

    init(data: Data) throws {
        self.init(raw: try decodeObject(data))
    }

    init(raw: [String: Any]) {
        self.name = raw["name"] as? String ?? ""
        self.fields = raw["fields"] as? [String: Any] ?? [:]
    }

    func appUser(uid: String) -> AppUser {
        AppUser(
            id: uid,
            username: FirestoreValue.string(fields["username"]),
            email: FirestoreValue.string(fields["email"]),
            type: FirestoreValue.string(fields["type"]).isEmpty ? "user" : FirestoreValue.string(fields["type"])
        )
    }

    func hazardReport() -> HazardReport? {
        let coordinate = FirestoreValue.geoPoint(fields["coordinate"])
        return HazardReport(
            documentID: name.components(separatedBy: "/").last ?? UUID().uuidString,
            numericID: FirestoreValue.integer(fields["id"]),
            hazardType: FirestoreValue.string(fields["hazardType"]),
            date: FirestoreValue.string(fields["date"]),
            createdAt: FirestoreValue.optionalInteger(fields["createdAt"]),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            address: FirestoreValue.string(fields["address"]),
            imageURL: FirestoreValue.string(fields["imageUrl"]),
            reportedBy: FirestoreValue.string(fields["reportedBy"]),
            status: FirestoreValue.string(fields["status"])
        )
    }
}

private enum FirestoreValue {
    static func string(_ value: Any?) -> String {
        (value as? [String: Any])?["stringValue"] as? String ?? ""
    }

    static func integer(_ value: Any?) -> Int {
        let raw = (value as? [String: Any])?["integerValue"]
        if let string = raw as? String { return Int(string) ?? 0 }
        return raw as? Int ?? 0
    }

    static func optionalInteger(_ value: Any?) -> Int? {
        guard let value else { return nil }
        return integer(value)
    }

    static func geoPoint(_ value: Any?) -> (latitude: Double, longitude: Double) {
        let raw = (value as? [String: Any])?["geoPointValue"] as? [String: Any]
        return (
            latitude: raw?["latitude"] as? Double ?? 0,
            longitude: raw?["longitude"] as? Double ?? 0
        )
    }
}

private extension DateFormatter {
    static let reportDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy HH:mm"
        return formatter
    }()
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

private extension Data {
    mutating func append(_ string: String) {
        append(string.data(using: .utf8) ?? Data())
    }
}

private func decodeObject(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AppBackendError.invalidResponse
    }
    return object
}
