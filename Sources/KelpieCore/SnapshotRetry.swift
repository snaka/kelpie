import Foundation

/// A bounded retry budget for a live snapshot that failed.
///
/// Events say only *that* something changed, so a failed `session.snapshot`
/// leaves the UI showing the previous state until the next event or the 300 s
/// resync — observed once, transiently, while herdr was mid-replay. This hands
/// out a short run of delays to retry over, then gives up: the failure seen in
/// practice clears in well under a second, and the resync is the backstop for
/// anything longer. Retrying forever would only compete with it.
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
