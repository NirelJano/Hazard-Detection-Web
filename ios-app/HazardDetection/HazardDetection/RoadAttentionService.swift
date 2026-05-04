import CoreGraphics
import Foundation

@MainActor
final class RoadAttentionService: ObservableObject {
    @Published private(set) var roadAttentionPoint: CGPoint = DetectionConfig.defaultRoadAttentionPoint
    @Published private(set) var roadAttentionRegion: CGRect = CGRect(x: 0, y: 0.4, width: 1.0, height: 0.6)

    private var userTapExpiry: Date?
    private let userTapDuration: TimeInterval = 10.0

    /// Call on each frame to keep the road attention point adaptive.
    /// - Parameters:
    ///   - userTap: Normalized AVCapture point if the user just tapped; pass nil to use auto-adapt.
    ///   - frameSize: The current frame dimensions.
    ///   - pitch: Device pitch from MotionService (radians).
    ///   - roll: Device roll from MotionService (radians).
    ///   - stableDetections: Recent confirmed detections for context.
    func update(
        userTap: CGPoint?,
        frameSize: CGSize,
        pitch: Double?,
        roll: Double?,
        stableDetections: [DetectionCandidate]
    ) {
        if let tap = userTap {
            roadAttentionPoint = tap
            userTapExpiry = Date().addingTimeInterval(userTapDuration)
        } else if let expiry = userTapExpiry, Date() < expiry {
            // Hold the user-set point until it expires
        } else {
            userTapExpiry = nil
            roadAttentionPoint = adaptedPoint(pitch: pitch, roll: roll, detections: stableDetections)
        }
        roadAttentionRegion = region(around: roadAttentionPoint)
    }

    /// Applies a small confidence penalty to detections whose bounding box center falls outside
    /// the road attention region. This is advisory only — never filters or crops model input,
    /// and never hides detections from the live overlay.
    func penalize(_ detections: [DetectionCandidate]) -> [DetectionCandidate] {
        detections.map { candidate in
            let center = candidate.boundingBox.center
            guard !roadAttentionRegion.contains(center) else { return candidate }
            return DetectionCandidate(
                label: candidate.label,
                confidence: max(0, candidate.confidence - DetectionConfig.confidencePenaltyOutsideROI),
                boundingBox: candidate.boundingBox
            )
        }
    }

    // MARK: - Private helpers

    private func adaptedPoint(pitch: Double?, roll: Double?, detections: [DetectionCandidate]) -> CGPoint {
        // Default: center-lower-middle; shift slightly based on device pitch if available.
        var y: CGFloat = 0.70
        if let pitch, abs(pitch) < 0.4 {
            y = CGFloat(0.65 + pitch * 0.15).clamped(to: 0.45...0.85)
        }
        return CGPoint(x: 0.5, y: y)
    }

    private func region(around point: CGPoint) -> CGRect {
        let halfW: CGFloat = 0.5
        let halfH: CGFloat = 0.30
        return CGRect(
            x: max(0, point.x - halfW),
            y: max(0, point.y - halfH),
            width: halfW * 2,
            height: min(1, halfH * 2 + max(0, point.y - halfH))
        )
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
