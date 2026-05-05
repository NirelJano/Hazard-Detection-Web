import Foundation

struct DetectionGateDecision {
    let accepted: Bool
    let effectiveThreshold: Double
    let reasons: [String]
    let roi: ROIEvaluation
    let frameQuality: FrameQualityScore?
    let motion: MotionSignal?
}

struct DetectionGateDebugState: Equatable {
    var lastEffectiveThreshold: Double = DetectionPreferenceDefaults.baseConfidenceThreshold
    var acceptedCandidateCount: Int = 0
    var rejectedCandidateCount: Int = 0
    var lastGateReasons: [String] = []
    var lastROI: ROIEvaluation?
    var currentFrameQuality: FrameQualityScore?
    var currentMotion: MotionSignal?
}

struct DetectionGate {
    private let roiManager = RegionOfInterestManager()
    private let thresholdPolicy = AdaptiveThresholdPolicy()

    @MainActor
    func evaluate(
        candidate: DetectionCandidate,
        speedMetersPerSecond: Double,
        frameQuality: FrameQualityScore?,
        motion: MotionSignal?,
        preferences: DetectionPreferences,
        recentStabilityScore: Double? = nil
    ) -> DetectionGateDecision {
        let roi = roiManager.evaluate(candidate: candidate, preferences: preferences)
        let quality = preferences.enableFrameQualitySignals ? frameQuality : nil
        let motionSignal = preferences.enableMotionSignals ? motion : nil
        let threshold = thresholdPolicy.threshold(for: DetectionContext(
            baseThreshold: preferences.baseConfidenceThreshold,
            speedMetersPerSecond: speedMetersPerSecond,
            roi: roi,
            frameQuality: quality,
            motion: motionSignal,
            recentStabilityScore: recentStabilityScore,
            preferences: preferences
        ))

        let accepted = Double(candidate.confidence) >= threshold.effectiveThreshold
        var reasons = threshold.reasons
        if !accepted { reasons.append("below threshold") }

        return DetectionGateDecision(
            accepted: accepted,
            effectiveThreshold: threshold.effectiveThreshold,
            reasons: reasons,
            roi: roi,
            frameQuality: quality,
            motion: motionSignal
        )
    }
}
