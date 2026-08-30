import Foundation

/// Turns a burst of change signals into one refresh, without ever starving.
///
/// Debouncing alone is not enough here: herdr's connect-time replay burst
/// arrives about 70 ms apart, denser than the debounce window, so a plain
/// restart-on-every-signal timer would keep deferring and leave the UI stale
/// for as long as the burst lasted. `maxWait` bounds that.
public struct RefreshCoalescer: Sendable {
    public enum Decision: Equatable, Sendable {
        /// Refresh immediately — the window has been open long enough.
        case fireNow
        /// Wait this long, and if no further signal arrives, refresh.
        case waitFor(Duration)
    }

    private let debounce: Duration
    private let maxWait: Duration
    private var windowStart: ContinuousClock.Instant?

    public init(debounce: Duration = .milliseconds(150), maxWait: Duration = .seconds(1)) {
        self.debounce = debounce
        self.maxWait = maxWait
    }

    /// Records a change signal and says what the caller should do.
    public mutating func signal(at now: ContinuousClock.Instant) -> Decision {
        let start = windowStart ?? now
        windowStart = start
        if now - start >= maxWait {
            windowStart = nil
            return .fireNow
        }
        return .waitFor(debounce)
    }

    /// Call once a refresh has run, so the next burst opens a fresh window.
    public mutating func didRefresh() {
        windowStart = nil
    }
}
