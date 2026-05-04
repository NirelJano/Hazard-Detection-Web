import Foundation
import SwiftData

enum PendingReportStatus: String {
    case pending
    case uploading
    case uploaded    // image on Cloudinary, Firestore write pending
    case committed   // fully written to Firestore; safe to prune
    case failed
    case cancelled
}

@Model
final class PendingReport {
    @Attribute(.unique) var id: UUID
    var clientReportId: String           // Firestore doc ID and idempotency key
    @Attribute(.externalStorage) var draftData: Data  // JSON-encoded ReportDraft
    var statusRaw: String                // PendingReportStatus.rawValue
    var attempts: Int
    var lastError: String?
    var queuedAt: Date
    var lastAttemptAt: Date?
    var imageUrl: String?                // set after Cloudinary upload
    var resolvedAddress: String?         // set after geocoding
    var userId: String
    var reportedBy: String

    var status: PendingReportStatus {
        get { PendingReportStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        clientReportId: String,
        draftData: Data,
        userId: String,
        reportedBy: String
    ) {
        self.id = id
        self.clientReportId = clientReportId
        self.draftData = draftData
        self.statusRaw = PendingReportStatus.pending.rawValue
        self.attempts = 0
        self.queuedAt = Date()
        self.userId = userId
        self.reportedBy = reportedBy
    }
}
