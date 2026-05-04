import Foundation

/// Confirms live detections by requiring a label to appear in a sliding window of frames
/// before it becomes eligible for report creation. This prevents single-frame noise from
/// generating reports while still reacting quickly to genuine hazards.
final class CandidateAggregator {

    struct ConfirmedCandidate {
        let label: String
        let confidence: Float
        let boundingBox: CGRect
        let confirmationCount: Int
    }

    // Per-label ring buffer of presence flags (true = detected in that frame)
    private var frameHistory: [String: [Bool]] = [:]
    private let maxHistory = 4  // covers both the 3-frame and 4-frame windows

    /// Feed the latest frame's detections and quality data.
    /// Returns candidates whose confirmation count has reached the threshold.
    func add(
        detections: [DetectionCandidate],
        frameQuality: FrameQualityScores,
        stabilityScore: Float
    ) -> [ConfirmedCandidate] {
        let isUnstable = stabilityScore < 0.4
        let neededFrames = isUnstable
            ? DetectionConfig.unstableConfirmationNeeded
            : DetectionConfig.confirmationFramesNeeded
        let windowSize = isUnstable
            ? DetectionConfig.unstableConfirmationWindow
            : DetectionConfig.confirmationFramesWindow

        let presentLabels = Set(detections.map(\.label))

        // Advance history for all tracked labels (including absent ones)
        for label in frameHistory.keys {
            var history = frameHistory[label] ?? []
            history.append(presentLabels.contains(label))
            if history.count > maxHistory { history.removeFirst() }
            frameHistory[label] = history
        }
        // Register first-seen labels
        for label in presentLabels where frameHistory[label] == nil {
            frameHistory[label] = [true]
        }

        // Evaluate which labels meet the confirmation threshold in the current window
        var confirmed: [ConfirmedCandidate] = []
        for detection in detections {
            let history = frameHistory[detection.label] ?? []
            let recentWindow = Array(history.suffix(windowSize))
            let hitCount = recentWindow.filter { $0 }.count
            if hitCount >= neededFrames {
                confirmed.append(ConfirmedCandidate(
                    label: detection.label,
                    confidence: detection.confidence,
                    boundingBox: detection.boundingBox,
                    confirmationCount: hitCount
                ))
            }
        }

        // Prune labels absent for longer than maxHistory frames
        frameHistory = frameHistory.filter { _, history in
            history.suffix(maxHistory).contains(true)
        }

        return confirmed
    }

    /// Reset all accumulated frame history. Call when stopping live detection.
    func reset() {
        frameHistory.removeAll()
    }
}
