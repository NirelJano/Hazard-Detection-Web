import CoreGraphics
import Foundation

struct ROIEvaluation: Codable, Equatable {
    let isInsideROI: Bool
    let isInIgnoredBottomBand: Bool
    let roiPenalty: Double
    let normalizedCenterX: Double
    let normalizedCenterY: Double
}

struct RegionOfInterestManager {
    @MainActor
    func evaluate(candidate: DetectionCandidate, preferences: DetectionPreferences) -> ROIEvaluation {
        guard preferences.enableROI else {
            return ROIEvaluation(
                isInsideROI: true,
                isInIgnoredBottomBand: false,
                roiPenalty: 0,
                normalizedCenterX: Double(candidate.boundingBox.midX),
                normalizedCenterY: Double(candidate.boundingBox.midY)
            )
        }

        let bottomIgnoreRatio = clamp(preferences.bottomIgnoreRatio, min: 0, max: 0.45)
        let centerX = Double(candidate.boundingBox.midX)
        let centerY = Double(candidate.boundingBox.midY)
        let activeROI = CGRect(
            x: 0,
            y: bottomIgnoreRatio,
            width: 1,
            height: 1 - bottomIgnoreRatio
        )
        let center = CGPoint(x: centerX, y: centerY)
        let isInIgnoredBottomBand = centerY < bottomIgnoreRatio
        let isInsideROI = activeROI.contains(center)
        let penalty: Double
        if isInIgnoredBottomBand {
            penalty = 0.45
        } else if !isInsideROI {
            penalty = 0.12
        } else {
            penalty = 0
        }

        return ROIEvaluation(
            isInsideROI: isInsideROI,
            isInIgnoredBottomBand: isInIgnoredBottomBand,
            roiPenalty: penalty,
            normalizedCenterX: centerX,
            normalizedCenterY: centerY
        )
    }

    private func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.max(lower, Swift.min(upper, value))
    }
}
