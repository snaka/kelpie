import Foundation

/// A bounded retry budget for a live snapshot that failed.
///
/// Events say only *that* something changed, so a failed `session.snapshot`
/// leaves the UI showing the previous state until the next event or the 300 s
/// resync. That failure is not the rarity it first looked like: measured
/// against a live 0.8.2, a snapshot request in flight fails within about ten
/// milliseconds of *every* subscription rebuild, and recovers on the first
/// retry. So this hands out a short run of delays, then gives up — the failure
/// clears in well under a second, and the resync is the backstop for anything
/// longer. Retrying forever would only compete with it.
public struct SnapshotRetry: Sendable {
    private var remaining: [Duration]

    public init(delays: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1)]) {
        self.remaining = delays
    }

    /// How long to wait before the next attempt, or `nil` once the budget is
    /// spent.
    public mutating func nextDelay() -> Duration? {
        remaining.isEmpty ? nil : remaining.removeFirst()
    }
}
