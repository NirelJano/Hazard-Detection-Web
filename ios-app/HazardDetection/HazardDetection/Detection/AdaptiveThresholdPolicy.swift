import Foundation

struct DetectionContext {
    let baseThreshold: Double
    let speedMetersPerSecond: Double
    let roi: ROIEvaluation
    let frameQuality: FrameQualityScore?
    let motion: MotionSignal?
    let recentStabilityScore: Double?
    let preferences: DetectionPreferences
}

struct AdaptiveThresholdResult: Codable, Equatable {
    let effectiveThreshold: Double
    let reasons: [String]
}

struct AdaptiveThresholdPolicy {
    @MainActor
    func threshold(for context: DetectionContext) -> AdaptiveThresholdResult {
        guard context.preferences.enableAdaptiveThreshold else {
            return AdaptiveThresholdResult(
                effectiveThreshold: clamp(context.baseThreshold, min: 0.20, max: 0.85),
                reasons: ["fixed threshold"]
            )
        }

        var threshold = context.baseThreshold
        var reasons: [String] = []

        if context.preferences.enableROI, context.roi.roiPenalty > 0 {
            threshold += context.roi.roiPenalty
            reasons.append(context.roi.isInIgnoredBottomBand ? "bottom band" : "outside ROI")
        }

        if context.preferences.enableFrameQualitySignals, let quality = context.frameQuality {
            if quality.isTooDark {
                threshold += 0.10
                reasons.append("dark frame")
            } else if quality.brightness < 0.28 {
                threshold += 0.05
                reasons.append("low light")
            }
            if quality.isBlurry {
                threshold += 0.10
                reasons.append("blur")
            }
        }

        let motionStable = context.motion?.isDeviceStable ?? true
        if context.preferences.enableMotionSignals, let motion = context.motion, !motion.isDeviceStable {
            threshold += 0.08
            reasons.append("motion")
        }

        if context.speedMetersPerSecond > DetectionConfig.highSpeedMSCutoff {
            if motionStable, !(context.frameQuality?.isBlurry ?? false), !(context.frameQuality?.isTooDark ?? false) {
                threshold += context.preferences.highSpeedConfidenceOffset
                reasons.append("stable high speed")
            } else {
                threshold += 0.04
                reasons.append("unstable high speed")
            }
        }

        if let stability = context.recentStabilityScore, stability > 0.8 {
            threshold -= 0.03
            reasons.append("stable recent detections")
        }

        if reasons.isEmpty { reasons.append("base") }
        return AdaptiveThresholdResult(
            effectiveThreshold: clamp(threshold, min: 0.20, max: 0.85),
            reasons: reasons
        )
    }

    private func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.max(lower, Swift.min(upper, value))
    }
}
