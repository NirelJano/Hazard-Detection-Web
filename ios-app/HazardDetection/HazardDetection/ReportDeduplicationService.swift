import CoreLocation
import Foundation

/// Prevents duplicate reports for the same hazard at the same location.
/// Extracted from AppController so it can be shared by the unified pipeline.
@MainActor
final class ReportDeduplicationService {
    private let reportRepository: ReportRepository
    private var recentlySavedByLabel: [String: Date] = [:]
    private var recentIoUEntries: [(detections: [DetectionCandidate], savedAt: Date)] = []

    init(repository: ReportRepository) {
        self.reportRepository = repository
    }

    // MARK: - GPS-based deduplication

    /// Returns true if the same label was saved within the deduplication radius and time window.
    func isGPSDuplicate(label: String, lat: Double, lng: Double) -> Bool {
        let current = CLLocation(latitude: lat, longitude: lng)
        let cutoff = Date().addingTimeInterval(-DetectionConfig.deduplicationTimeSeconds)
        return reportRepository.reports
            .filter { $0.hazardType == label }
            .sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
            .prefix(10)
            .contains { report in
                guard let ts = report.createdAt,
                      Date(timeIntervalSince1970: Double(ts) / 1000) > cutoff
                else { return false }
                let loc = CLLocation(
                    latitude: report.coordinate.latitude,
                    longitude: report.coordinate.longitude
                )
                return current.distance(from: loc) < DetectionConfig.deduplicationDistanceMeters
            }
    }

    // MARK: - IoU-based deduplication (no GPS)

    /// Returns true if any recently saved detection overlaps with the incoming ones (IoU ≥ threshold).
    func isIoUDuplicate(detections: [DetectionCandidate]) -> Bool {
        let cutoff = Date().addingTimeInterval(-DetectionConfig.noGPSWindowSeconds)
        recentIoUEntries = recentIoUEntries.filter { $0.savedAt > cutoff }
        for entry in recentIoUEntries {
            for prev in entry.detections {
                for current in detections where current.label == prev.label {
                    if current.boundingBox.iou(with: prev.boundingBox) >= CGFloat(DetectionConfig.noGPSIoUThreshold) {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - Per-label cooldown

    /// Returns false if the same label was saved less than `labelSaveCooldown` seconds ago.
    func shouldAllowSave(label: String) -> Bool {
        guard let last = recentlySavedByLabel[label] else { return true }
        return Date().timeIntervalSince(last) >= DetectionConfig.labelSaveCooldown
    }

    // MARK: - Record saves

    func recordSaved(label: String, detections: [DetectionCandidate]) {
        recentlySavedByLabel[label] = Date()
        recentIoUEntries.append((detections: detections, savedAt: Date()))
    }
}

// CGRect IoU helper — accessible to both this service and DetectionTracker
extension CGRect {
    func iou(with other: CGRect) -> CGFloat {
        let intersection = self.intersection(other)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = width * height + other.width * other.height - intersectionArea
        return unionArea <= 0 ? 0 : intersectionArea / unionArea
    }
}
