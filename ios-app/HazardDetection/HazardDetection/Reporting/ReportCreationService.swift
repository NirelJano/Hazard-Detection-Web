import CoreLocation
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
        let payload = try payloadBuilder.buildPayload(from: draft)

        let resolvedAddress: String?
        if let preresolved = draft.address {
            resolvedAddress = preresolved
        } else {
            let coordinate = CLLocationCoordinate2D(latitude: payload.lat, longitude: payload.lng)
            resolvedAddress = try? await GeocodingService.shared.reverseGeocode(coordinate: coordinate)
        }

        try await repository.addReport(
            type: payload.type,
            description: payload.description,
            lat: payload.lat,
            lng: payload.lng,
            address: resolvedAddress,
            image: preparedImage.uiImage,
            userProfile: userProfile,
            userId: userId,
            createdAtMillis: payload.createdAtMillis,
            detectionLabel: payload.detectionLabel,
            detectionConfidence: payload.detectionConfidence,
            detectionSource: payload.detectionSource,
            detectionBoundingBox: payload.detectionBoundingBox
        )
    }
}
