import Foundation
import UIKit

@MainActor
final class ReportCreationService {
    private let repository: ReportRepository
    private let validator: ReportValidationPolicy
    private let imagePreparer: ReportImagePreparer
    private let payloadBuilder: ReportPayloadBuilder

    init(
        repository: ReportRepository,
        validator: ReportValidationPolicy = ReportValidationPolicy(),
        imagePreparer: ReportImagePreparer = ReportImagePreparer(),
        payloadBuilder: ReportPayloadBuilder = ReportPayloadBuilder()
    ) {
        self.repository = repository
        self.validator = validator
        self.imagePreparer = imagePreparer
        self.payloadBuilder = payloadBuilder
    }

    func submit(_ draft: ReportDraft, userId: String, userProfile: AppUserProfile?) async throws {
        try validator.validate(draft)
        let preparedImage = try imagePreparer.prepareImage(for: draft)
        let payload = payloadBuilder.buildPayload(from: draft)

        try await repository.addReport(
            type: payload.type,
            description: payload.description,
            lat: payload.lat,
            lng: payload.lng,
            image: preparedImage.uiImage,
            userProfile: userProfile,
            userId: userId,
            detectionLabel: payload.detectionLabel,
            detectionConfidence: payload.detectionConfidence,
            detectionSource: payload.detectionSource,
            detectionBoundingBox: payload.detectionBoundingBox
        )
    }
}
