import Foundation

/// Validates a `ReportDraft` and enqueues it as a `PendingReport` for
/// durable background upload.  Returns as soon as the report is safely
/// persisted locally — network delivery is handled asynchronously by
/// `BackgroundUploadCoordinator`.
@MainActor
final class ReportCreationService {
    private let coordinator: BackgroundUploadCoordinator
    private let validator: ReportValidationPolicy

    init(
        coordinator: BackgroundUploadCoordinator = .shared,
        validator: ReportValidationPolicy = ReportValidationPolicy()
    ) {
        self.coordinator = coordinator
        self.validator = validator
    }

    func submit(_ draft: ReportDraft, userId: String, userProfile: AppUserProfile?) async throws {
        try validator.validate(draft)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let draftData = try encoder.encode(draft)

        let reportedBy = userProfile?.displayName ?? userProfile?.email ?? "User"
        let pending = PendingReport(
            clientReportId: draft.id.uuidString,
            draftData: draftData,
            userId: userId,
            reportedBy: reportedBy
        )

        try coordinator.enqueue(pending)
    }
}
