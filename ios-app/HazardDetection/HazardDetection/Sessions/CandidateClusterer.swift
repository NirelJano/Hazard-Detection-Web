import CoreLocation
import Foundation

struct CandidateCluster: Identifiable {
    let id: UUID
    let label: String
    let candidates: [SessionDetectionCandidate]

    var bestConfidence: Double { candidates.map(\.confidence).max() ?? 0 }
    var averageConfidence: Double {
        guard !candidates.isEmpty else { return 0 }
        return candidates.map(\.confidence).reduce(0, +) / Double(candidates.count)
    }
}

struct CandidateClusterer {
    private static let maxDistanceMeters: Double = 8.0
    private static let maxTimeWindowSeconds: Double = 60.0

    func cluster(_ candidates: [SessionDetectionCandidate]) -> [CandidateCluster] {
        let sorted = candidates.sorted { $0.timestamp < $1.timestamp }
        var clusters: [MutableCluster] = []

        for candidate in sorted {
            if let index = findMatchingCluster(for: candidate, in: clusters) {
                clusters[index].candidates.append(candidate)
            } else {
                clusters.append(MutableCluster(label: candidate.rawLabel, candidates: [candidate]))
            }
        }

        return clusters.map { CandidateCluster(id: UUID(), label: $0.label, candidates: $0.candidates) }
    }

    private func findMatchingCluster(
        for candidate: SessionDetectionCandidate,
        in clusters: [MutableCluster]
    ) -> Int? {
        let candidateLoc = decodeLocation(candidate.locationJSON)

        for (index, cluster) in clusters.enumerated() {
            guard cluster.label == candidate.rawLabel else { continue }
            guard let last = cluster.candidates.last else { continue }

            let timeDiff = candidate.timestamp.timeIntervalSince(last.timestamp)
            guard timeDiff <= Self.maxTimeWindowSeconds else { continue }

            if let cLoc = candidateLoc, let lastLoc = decodeLocation(last.locationJSON) {
                let clLast = CLLocation(latitude: lastLoc.latitude, longitude: lastLoc.longitude)
                let clCandidate = CLLocation(latitude: cLoc.latitude, longitude: cLoc.longitude)
                if clLast.distance(from: clCandidate) <= Self.maxDistanceMeters {
                    return index
                }
            } else {
                return index
            }
        }
        return nil
    }

    private func decodeLocation(_ data: Data?) -> CandidateLocation? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(CandidateLocation.self, from: data)
    }

    private struct MutableCluster {
        let label: String
        var candidates: [SessionDetectionCandidate]
    }
}
