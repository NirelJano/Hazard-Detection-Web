import CoreLocation
import Foundation
import SwiftData
import UIKit

/// Drains the `PendingReport` SwiftData queue: uploads images to Cloudinary,
/// geocodes addresses, then commits reports to Firestore with a stable
/// `clientReportId` for idempotency.
///
/// Triggered on launch, on every enqueue, and whenever the network comes back.
/// All access runs on `@MainActor` so it can share the container's `mainContext`
/// with SwiftUI and other `@MainActor` services.
@MainActor
final class BackgroundUploadCoordinator {
    static let shared = BackgroundUploadCoordinator()

    private var container: ModelContainer?
    private var repository: ReportRepository?
    private(set) var isProcessing = false

    private init() {}

    // MARK: - Startup

    func start(container: ModelContainer, repository: ReportRepository) {
        self.container = container
        self.repository = repository
        ReachabilityMonitor.shared.onReachable = { [weak self] in
            Task { await self?.processQueue() }
        }
        Task { await processQueue() }
    }

    // MARK: - Enqueue

    func enqueue(_ pending: PendingReport) throws {
        guard let container else { return }
        container.mainContext.insert(pending)
        try container.mainContext.save()
        Task { await processQueue() }
    }

    // MARK: - Queue processing

    func processQueue() async {
        guard !isProcessing, let container else { return }
        guard ReachabilityMonitor.shared.isOnline else { return }

        isProcessing = true
        defer { isProcessing = false }

        let context = container.mainContext
        let actionable = fetchActionable(from: context)

        for pending in actionable {
            await process(pending, context: context)
        }

        pruneCommitted(from: context)
    }

    // MARK: - Private helpers

    private func fetchActionable(from context: ModelContext) -> [PendingReport] {
        let descriptor = FetchDescriptor<PendingReport>(
            sortBy: [SortDescriptor(\PendingReport.queuedAt)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { pending in
            switch pending.status {
            case .pending:    return true
            case .uploaded:   return true
            case .failed:     return RetryPolicy.isRetryEligible(pending)
            case .uploading, .committed, .cancelled: return false
            }
        }
    }

    private func pruneCommitted(from context: ModelContext) {
        let descriptor = FetchDescriptor<PendingReport>(
            predicate: #Predicate { $0.statusRaw == "committed" }
        )
        guard let committed = try? context.fetch(descriptor), !committed.isEmpty else { return }
        committed.forEach { context.delete($0) }
        try? context.save()
    }

    private func process(_ pending: PendingReport, context: ModelContext) async {
        pending.attempts += 1
        pending.lastAttemptAt = Date()
        pending.status = .uploading
        try? context.save()

        guard let draft = decodeDraft(pending.draftData) else {
            fail(pending, error: "Failed to decode report draft", context: context)
            return
        }

        // Step 1: upload image to Cloudinary
        if pending.imageUrl == nil {
            guard let image = loadImage(from: draft) else {
                fail(pending, error: "No image data available for upload", context: context)
                return
            }
            do {
                let url = try await CloudinaryService.shared.uploadImage(image)
                pending.imageUrl = url
                pending.status = .uploaded
                try? context.save()
            } catch {
                fail(pending, error: "Cloudinary: \(error.localizedDescription)", context: context)
                return
            }
        }

        // Step 2: resolve address if not already available
        if pending.resolvedAddress == nil {
            if let preresolved = draft.address {
                pending.resolvedAddress = preresolved
            } else if let lat = draft.latitude, let lng = draft.longitude {
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                pending.resolvedAddress = try? await GeocodingService.shared.reverseGeocode(coordinate: coord)
            }
            try? context.save()
        }

        // Step 3: commit to Firestore (idempotent via clientReportId as doc ID)
        guard let repository else {
            fail(pending, error: "Repository unavailable", context: context)
            return
        }

        do {
            try await repository.commitPendingReport(
                clientReportId: pending.clientReportId,
                draft: draft,
                imageUrl: pending.imageUrl,
                resolvedAddress: pending.resolvedAddress,
                userId: pending.userId,
                reportedBy: pending.reportedBy,
                queuedAt: pending.queuedAt,
                uploadAttempts: pending.attempts
            )
            pending.status = .committed
            try? context.save()
            print("BackgroundUploadCoordinator: committed \(pending.clientReportId)")
        } catch {
            fail(pending, error: "Firestore: \(error.localizedDescription)", context: context)
        }
    }

    private func fail(_ pending: PendingReport, error: String, context: ModelContext) {
        pending.status = .failed
        pending.lastError = error
        try? context.save()
        print("BackgroundUploadCoordinator: failed \(pending.clientReportId) — \(error)")
    }

    private func decodeDraft(_ data: Data) -> ReportDraft? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(ReportDraft.self, from: data)
    }

    private func loadImage(from draft: ReportDraft) -> UIImage? {
        if let data = draft.imageData { return UIImage(data: data) }
        if let url = draft.imageLocalURL, let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return nil
    }
}
