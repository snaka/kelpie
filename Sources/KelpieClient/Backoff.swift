import Foundation

/// Exponential reconnect backoff with jitter.
///
/// herdr not running is a normal state, not an error, so Kelpie retries
/// forever rather than giving up — the ceiling keeps that cheap.
public struct Backoff: Sendable {
    private let initial: TimeInterval
    private let ceiling: TimeInterval
    private let jitter: ClosedRange<Double>
    private var current: TimeInterval

    public init(
        initial: TimeInterval = 1,
        ceiling: TimeInterval = 30,
        jitter: ClosedRange<Double> = 0.8...1.2
    ) {
        self.initial = initial
        self.ceiling = ceiling
        self.jitter = jitter
        self.current = initial
    }

    public mutating func next(
        random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
    ) -> TimeInterval {
        let base = current
        current = min(current * 2, ceiling)
        return min(base * random(jitter), ceiling)
    }

    public mutating func reset() {
        current = initial
    }
}
