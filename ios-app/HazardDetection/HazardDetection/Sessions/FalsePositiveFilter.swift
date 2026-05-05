import Foundation

struct FalsePositiveFilter {
    private static let minimumAverageConfidence: Double = 0.45
    private static let singleCandidateMinConfidence: Double = 0.65

    func shouldAccept(cluster: CandidateCluster) -> Bool {
        rejectionReason(for: cluster) == nil
    }

    func rejectionReason(for cluster: CandidateCluster) -> String? {
        guard !cluster.candidates.isEmpty else { return "empty_cluster" }

        let hasUsableImage = cluster.candidates.contains { $0.imageFileName != nil }
        guard hasUsableImage else { return "no_usable_image" }

        let count = cluster.candidates.count

        if count == 1 {
            let single = cluster.candidates[0]
            guard single.confidence >= Self.singleCandidateMinConfidence else {
                return "single_low_confidence"
            }
            let score = decodeConditionScore(single.conditionScoreJSON)
            if score?.isInIgnoredBottomBand == true { return "single_in_ignored_band" }
            return nil
        }

        guard cluster.averageConfidence >= Self.minimumAverageConfidence else {
            return "low_average_confidence"
        }

        let bottomBandCount = cluster.candidates.filter { candidate in
            decodeConditionScore(candidate.conditionScoreJSON)?.isInIgnoredBottomBand == true
        }.count
        if bottomBandCount > count / 2 { return "dominated_by_bottom_band" }

        return nil
    }

    private func decodeConditionScore(_ data: Data?) -> CandidateConditionScore? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(CandidateConditionScore.self, from: data)
    }
}
