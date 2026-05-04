import CoreLocation
import Foundation
import os
import UIKit

private let pipelineLogger = Logger(subsystem: "com.hazarddetection", category: "Pipeline")

/// The single shared report creation pipeline used by both upload and live detection flows.
/// Both `UploadReportView` and `LiveDetectionView` call `process(input:userId:userProfile:)`.
///
/// Live flow:    CandidateAggregator + FrameQualityService + RoadAttentionService gates are applied.
/// Upload flow:  Quality and aggregation gates are skipped; all valid detections are saved immediately.
@MainActor
final class DetectionReportPipeline: ObservableObject {
    @Published private(set) var status: PipelineStatus = .detecting
    @Published private(set) var qualityHint: QualityHint? = nil

    private let repository: ReportRepository
    private let qualityService: FrameQualityService
    private let attentionService: RoadAttentionService
    private let aggregator: CandidateAggregator
    private let deduplication: ReportDeduplicationService
    private let motionService: MotionService

    init(
        repository: ReportRepository,
        qualityService: FrameQualityService = FrameQualityService(),
        attentionService: RoadAttentionService,
        aggregator: CandidateAggregator,
        deduplication: ReportDeduplicationService,
        motionService: MotionService
    ) {
        self.repository = repository
        self.qualityService = qualityService
        self.attentionService = attentionService
        self.aggregator = aggregator
        self.deduplication = deduplication
        self.motionService = motionService
    }

    // MARK: - Main entry point

    @discardableResult
    func process(
        input: DetectionInput,
        userId: String,
        userProfile: AppUserProfile?
    ) async throws -> PipelineResult {
        status = .detecting
        qualityHint = nil

        // Step 1 — Normalize image orientation
        let image = normalizeOrientation(input.image)

        // Step 2 — Run detection if not pre-computed
        var detections: [DetectionCandidate]
        if let precomputed = input.detections, !precomputed.isEmpty {
            detections = precomputed
        } else {
            detections = await HazardDetector.shared.detect(
                in: image,
                confidenceThreshold: DetectionConfig.reportCandidateThreshold
            )
        }

        // Step 3 — Filter by threshold
        detections = detections.filter { $0.confidence >= DetectionConfig.reportCandidateThreshold }
        guard !detections.isEmpty else {
            log(input: input, detections: [], outcome: "below_threshold")
            return PipelineResult(
                outcome: .belowThreshold,
                detections: [],
                annotatedImage: nil,
                metadata: input.metadata
            )
        }

        var metadata = input.metadata

        // Steps 4–6 only apply to live camera (upload skips quality gate and confirmation)
        if input.source == .liveCamera || input.source == .liveAutoDetection {
            // Step 4 — Soft road attention penalty
            detections = attentionService.penalize(detections)
            metadata.roadAttentionPoint = attentionService.roadAttentionPoint

            // Step 5 — Frame quality gate
            let snapshot = motionService.currentSnapshot()
            let scores = qualityService.evaluate(image: image, motionStability: snapshot.stabilityScore)
            metadata.frameQualityScores = scores
            metadata.motionPitch = snapshot.pitch
            metadata.motionRoll = snapshot.roll
            metadata.motionYaw = snapshot.yaw
            metadata.accelerationMagnitude = snapshot.accelerationMagnitude
            metadata.rotationRate = snapshot.rotationRate

            if let hint = qualityService.qualityHint(scores: scores, motionStability: snapshot.stabilityScore) {
                qualityHint = hint
                let pipelineHintStatus: PipelineStatus = {
                    switch hint {
                    case .motionBlur: return .motionBlur
                    case .lowVisibility: return .lowVisibility
                    case .tapToFocus, .adjustAngle: return .tapToFocus
                    }
                }()
                status = pipelineHintStatus
                log(input: input, detections: detections, outcome: "quality_gate: \(hint.rawValue)")
                return PipelineResult(
                    outcome: .qualityGateFailed(hint),
                    detections: detections,
                    annotatedImage: nil,
                    metadata: metadata
                )
            }

            // Step 6 — Confirmation window.
            // Live auto reports are already confirmed by LiveAutoReportCoordinator;
            // legacy live-camera triggers still use the shared CandidateAggregator.
            status = .candidateFound
            if input.source == .liveCamera {
                let confirmed = aggregator.add(
                    detections: detections,
                    frameQuality: scores,
                    stabilityScore: snapshot.stabilityScore
                )
                guard !confirmed.isEmpty else {
                    status = .confirming
                    log(input: input, detections: detections, outcome: "not_confirmed")
                    return PipelineResult(
                        outcome: .notConfirmed,
                        detections: detections,
                        annotatedImage: nil,
                        metadata: metadata
                    )
                }
                detections = confirmed.map {
                    DetectionCandidate(label: $0.label, confidence: $0.confidence, boundingBox: $0.boundingBox)
                }
            }
        }

        // Step 7 — Annotate image with all confirmed detections
        let annotated = ImageAnnotator.drawBoundingBoxes(on: image, detections: detections)

        // Step 8 — Deduplication
        let primaryDetection = detections.max(by: { $0.confidence < $1.confidence })!
        if !deduplication.shouldAllowSave(label: primaryDetection.label) {
            status = .duplicateSkipped
            log(input: input, detections: detections, outcome: "duplicate_cooldown")
            return PipelineResult(
                outcome: .duplicate,
                detections: detections,
                annotatedImage: annotated,
                metadata: metadata
            )
        }
        if let lat = metadata.latitude, let lng = metadata.longitude {
            if deduplication.isGPSDuplicate(label: primaryDetection.label, lat: lat, lng: lng) {
                status = .duplicateSkipped
                log(input: input, detections: detections, outcome: "duplicate_gps")
                return PipelineResult(
                    outcome: .duplicate,
                    detections: detections,
                    annotatedImage: annotated,
                    metadata: metadata
                )
            }
        } else if deduplication.isIoUDuplicate(detections: detections) {
            status = .duplicateSkipped
            log(input: input, detections: detections, outcome: "duplicate_iou")
            return PipelineResult(
                outcome: .duplicate,
                detections: detections,
                annotatedImage: annotated,
                metadata: metadata
            )
        }

        // Step 9 — Geocoding (skip if caller already resolved the address)
        var address: String? = input.preResolvedAddress
        if address == nil, let lat = metadata.latitude, let lng = metadata.longitude {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            address = try? await GeocodingService.shared.reverseGeocode(coordinate: coord)
        }

        // Step 10 — Create report
        do {
            try await repository.addReport(
                type: primaryDetection.label,
                description: input.description,
                lat: metadata.latitude ?? 0,
                lng: metadata.longitude ?? 0,
                address: address,
                image: annotated,
                userProfile: userProfile,
                userId: userId,
                createdAtMillis: Int64(Date().timeIntervalSince1970 * 1000),
                detections: detections,
                detectionSource: input.source,
                metadata: metadata
            )
        } catch {
            log(input: input, detections: detections, outcome: "error: \(error)")
            return PipelineResult(
                outcome: .error(error),
                detections: detections,
                annotatedImage: annotated,
                metadata: metadata
            )
        }

        deduplication.recordSaved(label: primaryDetection.label, detections: detections)
        status = .reportSaved
        log(input: input, detections: detections, outcome: "saved")
        return PipelineResult(
            outcome: .saved,
            detections: detections,
            annotatedImage: annotated,
            metadata: metadata
        )
    }

    // MARK: - Helpers

    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    private func log(input: DetectionInput, detections: [DetectionCandidate], outcome: String) {
        let scores = input.metadata.frameQualityScores
        let detStr = detections.map { "\($0.label)@\(String(format:"%.2f",$0.confidence))" }.joined(separator: ",")
        pipelineLogger.info("""
            [Pipeline] outcome=\(outcome, privacy: .public) \
            source=\(input.source.rawValue, privacy: .public) \
            frameId=\(input.frameId?.uuidString ?? "nil", privacy: .public) \
            detections=[\(detStr, privacy: .public)] \
            lat=\(input.metadata.latitude ?? 0) lng=\(input.metadata.longitude ?? 0) \
            speed=\(input.metadata.speed ?? 0) \
            iso=\(input.metadata.iso ?? 0) \
            expDur=\(input.metadata.exposureDuration ?? 0) \
            focusPt=\(input.metadata.focusPoint.map { "\($0.x),\($0.y)" } ?? "nil", privacy: .public) \
            roadPt=\(input.metadata.roadAttentionPoint.map { "\($0.x),\($0.y)" } ?? "nil", privacy: .public) \
            pitch=\(input.metadata.motionPitch ?? 0) roll=\(input.metadata.motionRoll ?? 0) \
            stability=\(scores?.motionStabilityScore ?? 1) \
            blur=\(scores?.blurScore ?? 0) \
            brightness=\(scores?.brightnessScore ?? 0) \
            overexp=\(scores?.overexposureRatio ?? 0)
            """)
    }
}
