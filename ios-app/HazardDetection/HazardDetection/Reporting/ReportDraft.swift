import CoreGraphics
import Foundation

struct ReportDraft: Identifiable, Codable {
    let id: UUID
    let source: ReportDraftSource
    var hazardType: String
    var rawLabel: String?
    var confidence: Double?
    var imageData: Data?
    var imageLocalURL: URL?
    var boundingBox: CodableRect?
    var createdAt: Date
    var latitude: Double?
    var longitude: Double?
    var address: String?
    var locationSource: LocationSource
    var notes: String?
    var metadata: DetectionMetadata?

    init(
        id: UUID = UUID(),
        source: ReportDraftSource,
        hazardType: String,
        rawLabel: String? = nil,
        confidence: Double? = nil,
        imageData: Data? = nil,
        imageLocalURL: URL? = nil,
        boundingBox: CodableRect? = nil,
        createdAt: Date = Date(),
        latitude: Double? = nil,
        longitude: Double? = nil,
        address: String? = nil,
        locationSource: LocationSource = .unknown,
        notes: String? = nil,
        metadata: DetectionMetadata? = nil
    ) {
        self.id = id
        self.source = source
        self.hazardType = hazardType
        self.rawLabel = rawLabel
        self.confidence = confidence
        self.imageData = imageData
        self.imageLocalURL = imageLocalURL
        self.boundingBox = boundingBox
        self.createdAt = createdAt
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.locationSource = locationSource
        self.notes = notes
        self.metadata = metadata
    }
}

enum ReportDraftSource: String, Codable {
    case manualUpload
    case liveDetectionCandidate
    case postProcessedSession
}

enum LocationSource: String, Codable {
    case gps
    case manualPin
    case inferred
    case unknown
}

struct DetectionMetadata: Codable {
    var detectedLabel: String?
    var detectionConfidence: Double?
    var detectionSource: String?
    var detectionBoundingBox: CodableRect?
}

struct CodableRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
