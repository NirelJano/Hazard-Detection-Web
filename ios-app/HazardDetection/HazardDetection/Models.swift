import CoreGraphics
import FirebaseFirestore
import Foundation
import UIKit

struct AppUser: Identifiable, Equatable {
    let id: String
    let email: String

    var displayName: String { email.isEmpty ? "User" : email }
}

struct AppUserProfile: Codable, Equatable {
    var type: String
    var email: String?
    var displayName: String?
}

struct HazardReport: Identifiable, Equatable {
    var docId: String?
    var numericId: Int?
    var hazardType: String
    var date: String
    var description: String?
    var coordinate: GeoPoint
    var address: String?
    var imageUrl: String?
    var status: String
    var reportedBy: String
    var createdAt: Int64?

    // Detection metadata (legacy — single detection, always written for backward compat)
    var detectedLabel: String?
    var detectionConfidence: Double?
    var detectionSource: String?
    var detectionBoundingBox: DetectionBoundingBox?

    // Multi-detection support (new)
    var primaryLabel: String?
    var primaryConfidence: Double?
    var detections: [DetectedItem]?

    var id: String { docId ?? UUID().uuidString }

    init(
        docId: String?,
        numericId: Int?,
        hazardType: String,
        date: String,
        description: String?,
        coordinate: GeoPoint,
        address: String?,
        imageUrl: String?,
        status: String,
        reportedBy: String,
        createdAt: Int64?,
        detectedLabel: String?,
        detectionConfidence: Double?,
        detectionSource: String?,
        detectionBoundingBox: DetectionBoundingBox?,
        primaryLabel: String? = nil,
        primaryConfidence: Double? = nil,
        detections: [DetectedItem]? = nil
    ) {
        self.docId = docId
        self.numericId = numericId
        self.hazardType = hazardType
        self.date = date
        self.description = description
        self.coordinate = coordinate
        self.address = address
        self.imageUrl = imageUrl
        self.status = status
        self.reportedBy = reportedBy
        self.createdAt = createdAt
        self.detectedLabel = detectedLabel
        self.detectionConfidence = detectionConfidence
        self.detectionSource = detectionSource
        self.detectionBoundingBox = detectionBoundingBox
        self.primaryLabel = primaryLabel
        self.primaryConfidence = primaryConfidence
        self.detections = detections
    }

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard
            let hazardType = data["hazardType"] as? String,
            let date = data["date"] as? String,
            let coordinate = data["coordinate"] as? GeoPoint,
            let status = data["status"] as? String,
            let reportedBy = data["reportedBy"] as? String
        else { return nil }

        // Read multi-detection array — falls back gracefully when absent (legacy docs)
        let detectionsRaw = data["detections"] as? [[String: Any]] ?? []
        let detections: [DetectedItem]? = detectionsRaw.isEmpty ? nil : detectionsRaw.compactMap { item in
            guard let label = item["label"] as? String,
                  let confidence = item["confidence"] as? Double,
                  let bb = DetectionBoundingBox(dictionary: item["boundingBox"] as? [String: Any])
            else { return nil }
            return DetectedItem(label: label, confidence: confidence, boundingBox: bb)
        }

        self.init(
            docId: document.documentID,
            numericId: Self.readInt(data["id"]),
            hazardType: hazardType,
            date: date,
            description: data["description"] as? String,
            coordinate: coordinate,
            address: data["address"] as? String,
            imageUrl: data["imageUrl"] as? String,
            status: status,
            reportedBy: reportedBy,
            createdAt: Self.readCreatedAt(data["createdAt"]),
            detectedLabel: data["detectedLabel"] as? String,
            detectionConfidence: data["detectionConfidence"] as? Double,
            detectionSource: data["detectionSource"] as? String,
            detectionBoundingBox: DetectionBoundingBox(dictionary: data["detectionBoundingBox"] as? [String: Any]),
            primaryLabel: data["primaryLabel"] as? String,
            primaryConfidence: data["primaryConfidence"] as? Double,
            detections: detections
        )
    }

    private static func readCreatedAt(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? Timestamp {
            return Int64(value.dateValue().timeIntervalSince1970 * 1000)
        }
        return nil
    }

    private static func readInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Double { return Int(value) }
        return nil
    }
}

struct DetectionBoundingBox: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(from cgRect: CGRect) {
        self.x = Double(cgRect.origin.x)
        self.y = Double(cgRect.origin.y)
        self.width = Double(cgRect.size.width)
        self.height = Double(cgRect.size.height)
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }
        self.x = dictionary["x"] as? Double ?? 0
        self.y = dictionary["y"] as? Double ?? 0
        self.width = dictionary["width"] as? Double ?? 0
        self.height = dictionary["height"] as? Double ?? 0
    }

    var dictionary: [String: Double] {
        ["x": x, "y": y, "width": width, "height": height]
    }
}

struct DetectedItem: Equatable {
    var label: String
    var confidence: Double
    var boundingBox: DetectionBoundingBox
}

// MARK: - Detection Pipeline Types

enum DetectionSource: String {
    case liveCamera = "live_camera"
    case liveAutoDetection = "live_auto_detection"
    case upload = "manual_image"
}

struct FrameQualityScores {
    var blurScore: Float           // Laplacian variance — higher = sharper
    var brightnessScore: Float     // 0–1 normalized luminance
    var overexposureRatio: Float   // fraction of pixels above saturation threshold
    var contrastScore: Float
    var motionStabilityScore: Float
}

struct FrameMetadata {
    var timestamp: Date
    // Location
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double?
    var heading: Double?
    var speed: Double?
    // Camera
    var cameraOrientation: Int?
    var imageWidth: Int
    var imageHeight: Int
    var modelVersion: String?
    var cameraDeviceType: String?
    var lensType: String?
    var iso: Float?
    var exposureDuration: Double?
    var exposureTargetBias: Float?
    var focusMode: String?
    var whiteBalanceMode: String?
    var focusPoint: CGPoint?
    var exposurePoint: CGPoint?
    var roadAttentionPoint: CGPoint?
    // Motion
    var motionPitch: Double?
    var motionRoll: Double?
    var motionYaw: Double?
    var accelerationMagnitude: Double?
    var rotationRate: Double?
    // Quality
    var frameQualityScores: FrameQualityScores?
}

enum QualityHint: String {
    case motionBlur = "Motion blur"
    case lowVisibility = "Low visibility"
    case tapToFocus = "Tap road to focus"
    case adjustAngle = "Adjust phone angle"
}

enum PipelineStatus: String {
    case detecting = "Detecting"
    case candidateFound = "Candidate found"
    case confirming = "Confirming"
    case reportSaved = "Report saved"
    case duplicateSkipped = "Duplicate skipped"
    case motionBlur = "Motion blur"
    case lowVisibility = "Low visibility"
    case tapToFocus = "Tap road to focus"
}

enum LiveAutoReportState: Equatable {
    case idle
    case detecting
    case candidateDetected
    case confirming
    case savingReport
    case cooldown
    case error(String)

    var displayText: String {
        switch self {
        case .idle:
            return "Auto idle"
        case .detecting:
            return "Auto scanning"
        case .candidateDetected:
            return "Candidate detected"
        case .confirming:
            return "Confirming"
        case .savingReport:
            return "Saving report"
        case .cooldown:
            return "Cooldown"
        case .error(let message):
            return message
        }
    }
}

struct LiveAutoReportCandidate: Equatable {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}

struct LiveAutoReportSavedSummary: Equatable {
    let label: String
    let confidence: Float
    let timestamp: Date
}

struct DetectionInput {
    let image: UIImage
    let source: DetectionSource
    let metadata: FrameMetadata
    var detections: [DetectionCandidate]?   // nil → pipeline runs model
    var frameId: UUID?
    var description: String?
    var preResolvedAddress: String?         // skip geocoding if already resolved
}

enum PipelineOutcome {
    case saved
    case duplicate
    case belowThreshold
    case qualityGateFailed(QualityHint)
    case notConfirmed
    case error(Error)
}

struct PipelineResult {
    let outcome: PipelineOutcome
    let detections: [DetectionCandidate]
    let annotatedImage: UIImage?
    let metadata: FrameMetadata
}
