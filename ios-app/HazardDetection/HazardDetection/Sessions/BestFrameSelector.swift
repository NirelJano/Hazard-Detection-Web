import Foundation

struct BestFrameSelector {
    func selectBestCandidate(from cluster: CandidateCluster) -> SessionDetectionCandidate? {
        let pool = cluster.candidates.isEmpty ? [] : cluster.candidates

        // Prefer candidates that have a saved image
        let withImages = pool.filter { $0.imageFileName != nil }
        let scoringPool = withImages.isEmpty ? pool : withImages

        return scoringPool.max { score($0) < score($1) }
    }

    // MARK: - Private

    private func score(_ candidate: SessionDetectionCandidate) -> Double {
        var s = candidate.confidence * 10.0

        // Bonus for having a saved image
        if candidate.imageFileName != nil { s += 5.0 }

        if let data = candidate.conditionScoreJSON,
           let cs = try? JSONDecoder().decode(CandidateConditionScore.self, from: data) {
            if let brightness = cs.brightness {
                // Ideal brightness is ~0.45. Penalize extreme values.
                let penalty = abs(brightness - 0.45) * 2.0
                s -= penalty
            }
            if let blur = cs.blurScore {
                // Lower blur score = sharper = better
                s -= blur * 3.0
            }
            if cs.isInsideROI == true { s += 2.0 }
            if cs.isInIgnoredBottomBand == true { s -= 4.0 }
            if cs.isDeviceStable == true { s += 1.0 }
        }

        return s
    }
}
