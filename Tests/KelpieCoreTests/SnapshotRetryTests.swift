import Testing
import Foundation
@testable import KelpieCore

@Suite("SnapshotRetry")
struct SnapshotRetryTests {

    @Test("The first failure retries almost immediately")
    func firstFailureRetriesQuickly() {
        var retry = SnapshotRetry()
        #expect(retry.nextDelay() == .milliseconds(250))
    }

    @Test("Successive failures back off")
    func successiveFailuresBackOff() {
        var retry = SnapshotRetry()
        #expect(retry.nextDelay() == .milliseconds(250))
        #expect(retry.nextDelay() == .milliseconds(500))
        #expect(retry.nextDelay() == .seconds(1))
    }

    @Test("The budget runs out rather than retrying forever")
    func budgetRunsOut() {
        var retry = SnapshotRetry()
        for _ in 0..<3 { _ = retry.nextDelay() }
        #expect(retry.nextDelay() == nil)
        // Still exhausted when asked again.
        #expect(retry.nextDelay() == nil)
    }

    @Test("The schedule is the caller's to choose")
    func scheduleIsInjectable() {
        var retry = SnapshotRetry(delays: [.milliseconds(10)])
        #expect(retry.nextDelay() == .milliseconds(10))
        #expect(retry.nextDelay() == nil)
    }
}
