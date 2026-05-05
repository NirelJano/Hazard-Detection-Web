import Foundation
import SwiftData

final class HazardModelContainer {
    static let shared = HazardModelContainer()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            PendingReport.self,
            DetectionSession.self,
            SessionDetectionCandidate.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create HazardModelContainer: \(error)")
        }
    }
}
