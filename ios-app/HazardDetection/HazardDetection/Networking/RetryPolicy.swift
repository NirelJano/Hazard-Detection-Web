import Foundation

enum RetryPolicy {
    /// Maximum number of upload attempts before a pending report is permanently marked failed.
    static let maxAttempts = 6

    /// Backoff delay in seconds before the nth attempt is eligible to run again.
    /// Sequence: 1s, 4s, 16s, 60s, 60s, 60s — with ±10 % jitter.
    static func delay(forAttempt attempt: Int) -> TimeInterval {
        let schedule: [TimeInterval] = [1, 4, 16, 60, 60, 60]
        let index = max(0, min(attempt - 1, schedule.count - 1))
        let base = schedule[index]
        let jitter = Double.random(in: -(base * 0.1)...(base * 0.1))
        return base + jitter
    }

    /// Returns true when a failed pending report is past its next-retry window.
    static func isRetryEligible(_ pending: PendingReport) -> Bool {
        guard pending.attempts < maxAttempts else { return false }
        let origin = pending.lastAttemptAt ?? pending.queuedAt
        let nextEligible = origin.addingTimeInterval(delay(forAttempt: pending.attempts))
        return Date() >= nextEligible
    }
}
