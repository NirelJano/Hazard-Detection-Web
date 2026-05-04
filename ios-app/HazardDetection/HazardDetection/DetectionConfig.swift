import CoreGraphics
import Foundation

enum DetectionConfig {
    // Display and reporting thresholds
    static let displayThreshold: Float = 0.45
    static let reportCandidateThreshold: Float = 0.45

    // Speed-adaptive threshold for live detection
    static let highSpeedThreshold: Float = 0.30
    static let highSpeedMSCutoff: Double = 13.8  // ~50 km/h

    // Deduplication — GPS-based
    static let deduplicationDistanceMeters: Double = 12.0
    static let deduplicationTimeSeconds: Double = 60.0

    // Deduplication — IoU-based (no GPS)
    static let noGPSIoUThreshold: Double = 0.4
    static let noGPSWindowSeconds: Double = 3.0

    // Live confirmation window (CandidateAggregator)
    static let confirmationFramesNeeded: Int = 2
    static let confirmationFramesWindow: Int = 3
    static let unstableConfirmationNeeded: Int = 3
    static let unstableConfirmationWindow: Int = 4

    // RoadAttentionService defaults
    static let defaultRoadAttentionPoint = CGPoint(x: 0.5, y: 0.7)
    static let confidencePenaltyOutsideROI: Float = 0.05

    // Per-label save cooldown (seconds)
    static let labelSaveCooldown: TimeInterval = 10.0

    // Live auto-report gating
    static let liveAutoMinimumConfidence: Float = 0.55
    static let liveAutoConsecutiveDetections: Int = 3
    static let liveAutoCooldownSeconds: TimeInterval = 20.0
    static let liveAutoMinimumDistanceMeters: Double = 15.0
    static let liveAutoMaxReportsPerMinute: Int = 4
    static let liveAutoStrongerConfidenceDelta: Float = 0.20
}
