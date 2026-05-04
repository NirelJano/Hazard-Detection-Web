import Foundation

struct ReportPayload {
    let type: String
    let description: String?
    let lat: Double
    let lng: Double
    let createdAtMillis: Int64
    let detectionLabel: String?
    let detectionConfidence: Double?
    let detectionSource: String?
    let detectionBoundingBox: DetectionBoundingBox?
}

struct ReportPayloadBuilder {
    func buildPayload(from draft: ReportDraft) throws -> ReportPayload {
        guard let lat = draft.latitude, let lng = draft.longitude else {
            throw ReportValidationError.missingLocation
        }

        let detectionSource: String?
        switch draft.source {
        case .liveDetectionCandidate:
            detectionSource = "live_camera"
        case .manualUpload:
            detectionSource = draft.rawLabel != nil ? "manual_image" : nil
        case .postProcessedSession:
            detectionSource = "post_processed"
        }

        return ReportPayload(
            type: draft.hazardType,
            description: draft.notes ?? (draft.source == .liveDetectionCandidate ? "Live detection" : nil),
            lat: lat,
            lng: lng,
            createdAtMillis: Int64(draft.createdAt.timeIntervalSince1970 * 1000),
            detectionLabel: draft.rawLabel,
            detectionConfidence: draft.confidence,
            detectionSource: detectionSource,
            detectionBoundingBox: draft.boundingBox.map { DetectionBoundingBox(from: $0.cgRect) }
        )
    }
}
