import Testing
import Foundation
@testable import KelpieClient

@Suite("Backoff")
struct BackoffTests {

    /// Pin jitter to 1.0 so the doubling schedule is observable.
    private let noJitter: (ClosedRange<Double>) -> Double = { _ in 1.0 }

    @Test("Delays double from the initial value")
    func doubling() {
        var backoff = Backoff()
        let delays = (0..<5).map { _ in backoff.next(random: noJitter) }
        #expect(delays == [1, 2, 4, 8, 16])
    }

    @Test("Delays stop at the ceiling")
    func ceiling() {
        var backoff = Backoff()
        let delays = (0..<8).map { _ in backoff.next(random: noJitter) }
        #expect(delays.last == 30)
        #expect(delays.allSatisfy { $0 <= 30 })
    }

    @Test("Reset returns to the initial delay")
    func reset() {
        var backoff = Backoff()
        _ = backoff.next(random: noJitter)
        _ = backoff.next(random: noJitter)
        backoff.reset()
        #expect(backoff.next(random: noJitter) == 1)
    }

    @Test("Jitter scales the delay within its range")
    func jitter() {
        var low = Backoff()
        var high = Backoff()
        #expect(low.next(random: { $0.lowerBound }) == 0.8)
        #expect(high.next(random: { $0.upperBound }) == 1.2)
    }

    @Test("Jitter never pushes a delay above the ceiling")
    func jitterRespectsCeiling() {
        var backoff = Backoff()
        var last: TimeInterval = 0
        for _ in 0..<10 { last = backoff.next(random: { $0.upperBound }) }
        #expect(last <= 30)
    }
}
