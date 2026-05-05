import CoreLocation
import Foundation
import os
import SwiftData
import UIKit

private let storeLogger = Logger(subsystem: "com.hazarddetection", category: "DetectionSessionStore")

@MainActor
final class DetectionSessionStore: ObservableObject {
    let frameFileStore = SessionFrameFileStore()

    private static let maxFramesPerWindow = 5
    private static let frameSaveWindowSeconds: Double = 60
    private static let minConfidenceForFrameSave: Double = 0.50
    private static let insertSaveInterval = 10

    private var recentFrameSaveTimes: [Date] = []
    private var pendingInsertCount = 0

    private var modelContext: ModelContext {
        HazardModelContainer.shared.container.mainContext
    }

    // MARK: - Session lifecycle

    func startSession() throws -> DetectionSession {
        let session = DetectionSession()
        modelContext.insert(session)
        try modelContext.save()
        storeLogger.info("Session started: \(session.id.uuidString, privacy: .public)")
        return session
    }

    func endSession(_ session: DetectionSession) throws {
        session.endedAt = Date()
        session.status = .processing
        try modelContext.save()
        storeLogger.info("Session ended: \(session.id.uuidString, privacy: .public), candidates: \(session.candidateCount)")
    }

    func updateStatus(_ session: DetectionSession, status: DetectionSessionStatus) throws {
        session.status = status
        try modelContext.save()
    }

    func finalizeSession(_ session: DetectionSession, finalReportCount: Int, skippedCount: Int) throws {
        session.finalReportCount = finalReportCount
        session.skippedCandidateCount = skippedCount
        session.status = .completed
        try modelContext.save()
    }

    func markSessionFailed(_ session: DetectionSession, error: String) {
        session.status = .failed
        session.lastError = error
        try? modelContext.save()
    }

    // MARK: - Candidate recording

    func addCandidate(
        sessionId: UUID,
        candidate: DetectionCandidate,
        image: UIImage?,
        location: CLLocation?
    ) {
        let encoder = JSONEncoder()
        guard let boundingBoxJSON = try? encoder.encode(CodableRect(candidate.boundingBox)) else { return }

        var locationJSON: Data? = nil
        if let loc = location {
            let cl = CandidateLocation(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                horizontalAccuracy: loc.horizontalAccuracy > 0 ? loc.horizontalAccuracy : nil
            )
            locationJSON = try? encoder.encode(cl)
        }

        let candidateId = UUID()
        var imageFileName: String? = nil
        if let image, shouldSaveFrame(confidence: Double(candidate.confidence)) {
            imageFileName = try? frameFileStore.saveFrame(
                image,
                sessionId: sessionId,
                candidateId: candidateId,
                compressionQuality: 0.7
            )
        }

        let sessionCandidate = SessionDetectionCandidate(
            id: candidateId,
            sessionId: sessionId,
            rawLabel: candidate.label,
            displayLabel: candidate.label,
            confidence: Double(candidate.confidence),
            boundingBoxJSON: boundingBoxJSON,
            locationJSON: locationJSON,
            imageFileName: imageFileName
        )

        modelContext.insert(sessionCandidate)
        pendingInsertCount += 1

        if pendingInsertCount >= Self.insertSaveInterval {
            try? modelContext.save()
            pendingInsertCount = 0
        }
    }

    func incrementCandidateCount(_ session: DetectionSession) {
        session.candidateCount += 1
    }

    // MARK: - Fetch

    func candidates(for sessionId: UUID) throws -> [SessionDetectionCandidate] {
        let descriptor = FetchDescriptor<SessionDetectionCandidate>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Flush

    func flush() {
        if pendingInsertCount > 0 {
            try? modelContext.save()
            pendingInsertCount = 0
        }
    }

    // MARK: - Private

    private func shouldSaveFrame(confidence: Double) -> Bool {
        let now = Date()
        recentFrameSaveTimes = recentFrameSaveTimes.filter {
            now.timeIntervalSince($0) < Self.frameSaveWindowSeconds
        }
        guard recentFrameSaveTimes.count < Self.maxFramesPerWindow else { return false }
        guard confidence >= Self.minConfidenceForFrameSave else { return false }
        recentFrameSaveTimes.append(now)
        return true
    }
}
