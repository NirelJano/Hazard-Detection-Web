import Foundation

enum ReportValidationError: LocalizedError {
    case missingHazardType
    case missingImage
    case invalidImageData
    case missingLocation
    case invalidConfidence
    case invalidLatitude
    case invalidLongitude

    var errorDescription: String? {
        switch self {
        case .missingHazardType: return "Missing hazard type."
        case .missingImage: return "Missing report image."
        case .invalidImageData: return "Image data is corrupt or unreadable."
        case .missingLocation: return "Location is required to create a report."
        case .invalidConfidence: return "Detection confidence must be between 0 and 1."
        case .invalidLatitude: return "Latitude is invalid."
        case .invalidLongitude: return "Longitude is invalid."
        }
    }
}

struct ReportValidationPolicy {
    func validate(_ draft: ReportDraft) throws {
        if draft.hazardType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ReportValidationError.missingHazardType
        }
        if draft.imageLocalURL == nil && draft.imageData == nil {
            throw ReportValidationError.missingImage
        }
        if draft.latitude == nil || draft.longitude == nil {
            throw ReportValidationError.missingLocation
        }
        if let confidence = draft.confidence, confidence < 0 || confidence > 1 {
            throw ReportValidationError.invalidConfidence
        }
        if let latitude = draft.latitude, latitude < -90 || latitude > 90 {
            throw ReportValidationError.invalidLatitude
        }
        if let longitude = draft.longitude, longitude < -180 || longitude > 180 {
            throw ReportValidationError.invalidLongitude
        }
    }
}
