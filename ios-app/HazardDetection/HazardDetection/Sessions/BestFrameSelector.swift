import Foundation

struct BestFrameSelector {
    func selectBestCandidate(from cluster: CandidateCluster) -> SessionDetectionCandidate? {
        guard !cluster.candidates.isEmpty else { return nil }
        let withImages = cluster.candidates.filter { $0.imageFileName != nil }
        let pool = withImages.isEmpty ? cluster.candidates : withImages
        return pool.max { score($0) < score($1) }
    }

    private func score(_ candidate: SessionDetectionCandidate) -> Double {
        var s = candidate.confidence * 10.0
        if candidate.imageFileName != nil { s += 5.0 }
        if let data = candidate.conditionScoreJSON,
           let cs = try? JSONDecoder().decode(CandidateConditionScore.self, from: data) {
            if let brightness = cs.brightness {
                s -= abs(brightness - 0.45) * 2.0
            }
            if let blur = cs.blurScore { s -= blur * 3.0 }
            if cs.isInsideROI == true { s += 2.0 }
            if cs.isInIgnoredBottomBand == true { s -= 4.0 }
            if cs.isDeviceStable == true { s += 1.0 }
        }
        return s
    }
}
