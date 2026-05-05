import Foundation
import SwiftData

@Model
final class SessionDetectionCandidate {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID
    var rawLabel: String
    var displayLabel: String
    var confidence: Double
    var effectiveThreshold: Double?
    var boundingBoxJSON: Data
    var locationJSON: Data?
    var conditionScoreJSON: Data?
    var imageFileName: String?
    var timestamp: Date
    var statusRaw: String
    var rejectionReason: String?

    init(
        id: UUID = UUID(),
        sessionId: UUID,
        rawLabel: String,
        displayLabel: String,
        confidence: Double,
        effectiveThreshold: Double? = nil,
        boundingBoxJSON: Data,
        locationJSON: Data? = nil,
        conditionScoreJSON: Data? = nil,
        imageFileName: String? = nil,
        timestamp: Date = Date(),
        status: SessionCandidateStatus = .candidate,
        rejectionReason: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.rawLabel = rawLabel
        self.displayLabel = displayLabel
        self.confidence = confidence
        self.effectiveThreshold = effectiveThreshold
        self.boundingBoxJSON = boundingBoxJSON
        self.locationJSON = locationJSON
        self.conditionScoreJSON = conditionScoreJSON
        self.imageFileName = imageFileName
        self.timestamp = timestamp
        self.statusRaw = status.rawValue
        self.rejectionReason = rejectionReason
    }

    var status: SessionCandidateStatus {
        get { SessionCandidateStatus(rawValue: statusRaw) ?? .candidate }
        set { statusRaw = newValue.rawValue }
    }
}

enum SessionCandidateStatus: String, Codable {
    case candidate
    case accepted
    case rejected
    case merged
    case finalized
}

struct CandidateLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double?
}

struct CandidateConditionScore: Codable, Equatable {
    let effectiveThreshold: Double?
    let gateReasons: [String]
    let brightness: Double?
    let blurScore: Double?
    let isInsideROI: Bool?
    let isInIgnoredBottomBand: Bool?
    let isDeviceStable: Bool?
}
