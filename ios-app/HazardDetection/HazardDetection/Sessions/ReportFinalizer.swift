import CoreLocation
import Foundation
import os
import UIKit

private let finalizerLogger = Logger(subsystem: "com.hazarddetection", category: "ReportFinalizer")

struct SessionFinalizationResult {
    let finalReportCount: Int
    let skippedCandidateCount: Int
    let failedCount: Int
    let sessionDuration: TimeInterval
    let rawCandidateCount: Int
}

@MainActor
final class ReportFinalizer {
    private let creationService: ReportCreationService
    private let frameFileStore: SessionFrameFileStore
    private let clusterer = CandidateClusterer()
    private let filter = FalsePositiveFilter()
    private let frameSelector = BestFrameSelector()

    init(creationService: ReportCreationService, frameFileStore: SessionFrameFileStore) {
        self.creationService = creationService
        self.frameFileStore = frameFileStore
    }

    func finalize(
        session: DetectionSession,
        candidates: [SessionDetectionCandidate],
        userId: String,
        userProfile: AppUserProfile?
    ) async -> SessionFinalizationResult {
        let sessionDuration = session.endedAt.map { $0.timeIntervalSince(session.startedAt) } ?? 0
        let rawCount = candidates.count

        guard !candidates.isEmpty else {
            return SessionFinalizationResult(
                finalReportCount: 0, skippedCandidateCount: 0, failedCount: 0,
                sessionDuration: sessionDuration, rawCandidateCount: rawCount
            )
        }

        let clusters = clusterer.cluster(candidates)
        finalizerLogger.info("\(rawCount) candidates → \(clusters.count) clusters")

        var finalReportCount = 0
        var skippedCount = 0
        var failedCount = 0

        for cluster in clusters {
            guard filter.shouldAccept(cluster: cluster) else {
                skippedCount += cluster.candidates.count
                continue
            }
            guard let best = frameSelector.selectBestCandidate(from: cluster) else {
                skippedCount += cluster.candidates.count
                continue
            }
            do {
                try await submitReport(cluster: cluster, bestCandidate: best, session: session, userId: userId, userProfile: userProfile)
                finalReportCount += 1
            } catch {
                finalizerLogger.error("Failed to submit \(cluster.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
                failedCount += 1
            }
        }

        return SessionFinalizationResult(
            finalReportCount: finalReportCount,
            skippedCandidateCount: skippedCount,
            failedCount: failedCount,
            sessionDuration: sessionDuration,
            rawCandidateCount: rawCount
        )
    }

    private func submitReport(
        cluster: CandidateCluster,
        bestCandidate: SessionDetectionCandidate,
        session: DetectionSession,
        userId: String,
        userProfile: AppUserProfile?
    ) async throws {
        guard let fileName = bestCandidate.imageFileName,
              let image = try? frameFileStore.loadFrame(fileName: fileName, sessionId: session.id),
              let imageData = image.jpegData(compressionQuality: 0.8)
        else { throw ReportFinalizerError.noImageAvailable }

        guard let location = decodeLocation(bestCandidate.locationJSON) else {
            throw ReportFinalizerError.missingLocation
        }

        let conditionScore = decodeConditionScore(bestCandidate.conditionScoreJSON)
        let bbox = decodeBoundingBox(bestCandidate.boundingBoxJSON)
        let candidateIds = cluster.candidates.map(\.id)

        let metadata = DetectionMetadata(
            detectedLabel: bestCandidate.rawLabel,
            detectionConfidence: bestCandidate.confidence,
            detectionSource: "post_processed",
            detectionBoundingBox: bbox,
            sourceSessionId: session.id,
            sourceCandidateIds: candidateIds,
            effectiveThreshold: bestCandidate.effectiveThreshold,
            gateReasons: conditionScore?.gateReasons,
            postProcessed: true
        )

        let draft = ReportDraft(
            source: .postProcessedSession,
            hazardType: bestCandidate.displayLabel,
            rawLabel: bestCandidate.rawLabel,
            confidence: bestCandidate.confidence,
            imageData: imageData,
            boundingBox: bbox,
            createdAt: bestCandidate.timestamp,
            latitude: location.latitude,
            longitude: location.longitude,
            locationSource: .gps,
            metadata: metadata
        )

        try await creationService.submit(draft, userId: userId, userProfile: userProfile)
    }

    private func decodeLocation(_ data: Data?) -> CandidateLocation? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(CandidateLocation.self, from: data)
    }

    private func decodeConditionScore(_ data: Data?) -> CandidateConditionScore? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(CandidateConditionScore.self, from: data)
    }

    private func decodeBoundingBox(_ data: Data) -> CodableRect? {
        return try? JSONDecoder().decode(CodableRect.self, from: data)
    }
}

enum ReportFinalizerError: LocalizedError {
    case noImageAvailable
    case missingLocation

    var errorDescription: String? {
        switch self {
        case .noImageAvailable: return "No frame image available for this detection cluster."
        case .missingLocation: return "Location data is missing for this detection cluster."
        }
    }
}
