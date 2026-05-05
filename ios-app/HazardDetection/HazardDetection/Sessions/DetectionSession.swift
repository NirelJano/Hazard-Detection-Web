import Foundation
import SwiftData

@Model
final class DetectionSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var candidateCount: Int
    var finalReportCount: Int
    var skippedCandidateCount: Int
    var routeSummaryJSON: Data?
    var lastError: String?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: DetectionSessionStatus = .active,
        candidateCount: Int = 0,
        finalReportCount: Int = 0,
        skippedCandidateCount: Int = 0,
        routeSummaryJSON: Data? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.statusRaw = status.rawValue
        self.candidateCount = candidateCount
        self.finalReportCount = finalReportCount
        self.skippedCandidateCount = skippedCandidateCount
        self.routeSummaryJSON = routeSummaryJSON
        self.lastError = lastError
    }

    var status: DetectionSessionStatus {
        get { DetectionSessionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}

enum DetectionSessionStatus: String, Codable {
    case active
    case processing
    case completed
    case failed
    case cancelled
}
