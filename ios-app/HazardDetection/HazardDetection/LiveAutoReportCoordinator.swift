import CoreLocation
import Foundation
import os
import UIKit

private let autoReportLogger = Logger(subsystem: "com.hazarddetection", category: "LiveAutoReport")

@MainActor
final class LiveAutoReportCoordinator: ObservableObject {
    @Published private(set) var state: LiveAutoReportState = .idle
    @Published private(set) var currentCandidate: LiveAutoReportCandidate?
    @Published private(set) var lastSavedReport: LiveAutoReportSavedSummary?
    @Published private(set) var reportsSavedCount = 0
    @Published var isAutoSaveEnabled: Bool {
        didSet { UserDefaults.standard.set(isAutoSaveEnabled, forKey: "liveAutoSaveReports") }
    }

    private struct SavedEntry {
        let label: String
        let confidence: Float
        let location: CLLocation
        let savedAt: Date
        let boundingBox: CGRect
    }

    private var consecutiveByLabel: [String: Int] = [:]
    private var bestCandidateByLabel: [String: DetectionCandidate] = [:]
    private var lastSavedByLabel: [String: SavedEntry] = [:]
    private var reportTimestamps: [Date] = []
    private var isSaving = false

    init() {
        let stored = UserDefaults.standard.object(forKey: "liveAutoSaveReports") as? Bool
        self.isAutoSaveEnabled = stored ?? true
    }

    func resetSession() {
        state = isAutoSaveEnabled ? .detecting : .idle
        currentCandidate = nil
        lastSavedReport = nil
        reportsSavedCount = 0
        consecutiveByLabel.removeAll()
        bestCandidateByLabel.removeAll()
        reportTimestamps.removeAll()
        isSaving = false
    }

    func stop() {
        state = .idle
        currentCandidate = nil
        consecutiveByLabel.removeAll()
        bestCandidateByLabel.removeAll()
        isSaving = false
    }

    func ingest(
        detections: [DetectionCandidate],
        frame: UIImage?,
        location: CLLocation?,
        speed: CLLocationSpeed,
        metadata: FrameMetadata,
        pipeline: DetectionReportPipeline,
        userId: String?,
        userProfile: AppUserProfile?,
        onOutcome: @escaping (PipelineResult) -> Void
    ) {
        guard isAutoSaveEnabled else {
            state = .idle
            currentCandidate = nil
            return
        }
        guard !isSaving else { return }
        guard let location else {
            state = .error(AppBackendError.missingLocation.localizedDescription)
            autoReportLogger.debug("Auto report skipped: GPS unavailable")
            return
        }

        let threshold = threshold(forSpeed: speed)
        let filtered = detections
            .filter { $0.confidence >= threshold }
            .sorted { $0.confidence > $1.confidence }

        guard let strongest = filtered.first else {
            state = .detecting
            currentCandidate = nil
            decayAbsentLabels(presentLabels: [])
            return
        }

        let presentLabels = Set(filtered.map(\.label))
        decayAbsentLabels(presentLabels: presentLabels)

        for detection in filtered {
            let previousBest = bestCandidateByLabel[detection.label]
            consecutiveByLabel[detection.label, default: 0] += 1
            if previousBest == nil || detection.confidence > previousBest!.confidence {
                bestCandidateByLabel[detection.label] = detection
            }
        }

        let candidate = bestCandidateByLabel[strongest.label] ?? strongest
        currentCandidate = LiveAutoReportCandidate(
            label: candidate.label,
            confidence: candidate.confidence,
            boundingBox: candidate.boundingBox
        )

        let consecutive = consecutiveByLabel[candidate.label, default: 0]
        state = consecutive >= DetectionConfig.liveAutoConsecutiveDetections ? .candidateDetected : .confirming

        guard consecutive >= DetectionConfig.liveAutoConsecutiveDetections else {
            autoReportLogger.debug("Auto report confirming \(candidate.label, privacy: .public): \(consecutive, privacy: .public)")
            return
        }
        guard let frame else {
            state = .error("Frame unavailable")
            autoReportLogger.error("Auto report skipped: frame snapshot unavailable")
            return
        }
        guard let userId else {
            state = .error(AppBackendError.unauthenticated.localizedDescription)
            autoReportLogger.error("Auto report skipped: user unauthenticated")
            return
        }
        guard allowRateLimit() else {
            state = .cooldown
            autoReportLogger.info("Auto report skipped: max reports per minute reached")
            return
        }
        guard shouldSave(candidate: candidate, location: location) else {
            state = .cooldown
            return
        }

        save(
            candidate: candidate,
            detections: filtered,
            frame: frame,
            location: location,
            metadata: metadata,
            pipeline: pipeline,
            userId: userId,
            userProfile: userProfile,
            onOutcome: onOutcome
        )
    }

    private func save(
        candidate: DetectionCandidate,
        detections: [DetectionCandidate],
        frame: UIImage,
        location: CLLocation,
        metadata: FrameMetadata,
        pipeline: DetectionReportPipeline,
        userId: String,
        userProfile: AppUserProfile?,
        onOutcome: @escaping (PipelineResult) -> Void
    ) {
        isSaving = true
        state = .savingReport

        var reportMetadata = metadata
        reportMetadata.latitude = location.coordinate.latitude
        reportMetadata.longitude = location.coordinate.longitude
        reportMetadata.speed = location.speed
        reportMetadata.heading = location.course
        reportMetadata.horizontalAccuracy = location.horizontalAccuracy
        reportMetadata.timestamp = Date()
        reportMetadata.imageWidth = Int(frame.size.width)
        reportMetadata.imageHeight = Int(frame.size.height)

        let input = DetectionInput(
            image: frame,
            source: .liveAutoDetection,
            metadata: reportMetadata,
            detections: detections,
            frameId: UUID()
        )

        Task {
            do {
                let result = try await pipeline.process(input: input, userId: userId, userProfile: userProfile)
                onOutcome(result)
                switch result.outcome {
                case .saved:
                    recordSaved(candidate: candidate, location: location)
                    consecutiveByLabel[candidate.label] = 0
                    bestCandidateByLabel[candidate.label] = nil
                    state = .cooldown
                case .duplicate:
                    state = .cooldown
                case .qualityGateFailed:
                    state = .detecting
                case .notConfirmed:
                    state = .confirming
                case .belowThreshold:
                    state = .detecting
                case .error(let error):
                    state = .error(error.localizedDescription)
                }
            } catch {
                state = .error(error.localizedDescription)
                autoReportLogger.error("Auto report save failed: \(error.localizedDescription, privacy: .public)")
            }
            isSaving = false
        }
    }

    private func threshold(forSpeed speed: CLLocationSpeed) -> Float {
        let speedThreshold = speed > DetectionConfig.highSpeedMSCutoff
            ? DetectionConfig.highSpeedThreshold
            : DetectionConfig.liveAutoMinimumConfidence
        return max(DetectionConfig.reportCandidateThreshold, speedThreshold)
    }

    private func decayAbsentLabels(presentLabels: Set<String>) {
        for label in consecutiveByLabel.keys where !presentLabels.contains(label) {
            consecutiveByLabel[label] = 0
            bestCandidateByLabel[label] = nil
        }
    }

    private func allowRateLimit() -> Bool {
        let cutoff = Date().addingTimeInterval(-60)
        reportTimestamps = reportTimestamps.filter { $0 > cutoff }
        return reportTimestamps.count < DetectionConfig.liveAutoMaxReportsPerMinute
    }

    private func shouldSave(candidate: DetectionCandidate, location: CLLocation) -> Bool {
        guard let last = lastSavedByLabel[candidate.label] else { return true }

        let secondsSinceLast = Date().timeIntervalSince(last.savedAt)
        let distance = location.distance(from: last.location)
        let stronger = candidate.confidence >= last.confidence + DetectionConfig.liveAutoStrongerConfidenceDelta
        let overlap = candidate.boundingBox.iou(with: last.boundingBox)

        if secondsSinceLast < DetectionConfig.liveAutoCooldownSeconds, !stronger {
            autoReportLogger.info("Auto report duplicate: cooldown label=\(candidate.label, privacy: .public)")
            return false
        }
        if distance < DetectionConfig.liveAutoMinimumDistanceMeters, !stronger {
            autoReportLogger.info("Auto report duplicate: nearby label=\(candidate.label, privacy: .public), distance=\(distance, privacy: .public)")
            return false
        }
        if overlap >= CGFloat(DetectionConfig.noGPSIoUThreshold), secondsSinceLast < DetectionConfig.deduplicationTimeSeconds, !stronger {
            autoReportLogger.info("Auto report duplicate: overlapping box label=\(candidate.label, privacy: .public)")
            return false
        }
        return true
    }

    private func recordSaved(candidate: DetectionCandidate, location: CLLocation) {
        let now = Date()
        lastSavedByLabel[candidate.label] = SavedEntry(
            label: candidate.label,
            confidence: candidate.confidence,
            location: location,
            savedAt: now,
            boundingBox: candidate.boundingBox
        )
        reportTimestamps.append(now)
        reportsSavedCount += 1
        lastSavedReport = LiveAutoReportSavedSummary(
            label: candidate.label,
            confidence: candidate.confidence,
            timestamp: now
        )
        autoReportLogger.info("Auto report saved: \(candidate.label, privacy: .public) \(candidate.confidence, privacy: .public)")
    }
}
