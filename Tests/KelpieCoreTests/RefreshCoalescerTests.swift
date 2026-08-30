import Testing
import Foundation
@testable import KelpieCore

@Suite("RefreshCoalescer")
struct RefreshCoalescerTests {

    @Test("The first signal asks the caller to wait out the debounce")
    func firstSignalWaits() {
        var coalescer = RefreshCoalescer()
        let t0 = ContinuousClock.now
        #expect(coalescer.signal(at: t0) == .waitFor(.milliseconds(150)))
    }

    @Test("Signals denser than the debounce keep deferring until the cap")
    func densSignalsDeferUntilCap() {
        var coalescer = RefreshCoalescer(debounce: .milliseconds(150), maxWait: .seconds(1))
        let t0 = ContinuousClock.now
        // The replay burst's real cadence: about 70 ms apart.
        for step in stride(from: 0, to: 1000, by: 70) {
            #expect(coalescer.signal(at: t0.advanced(by: .milliseconds(step)))
                    == .waitFor(.milliseconds(150)))
        }
        // Once the window has been open for the cap, the next signal fires.
        #expect(coalescer.signal(at: t0.advanced(by: .milliseconds(1000))) == .fireNow)
    }

    @Test("Firing opens a fresh window")
    func firingResetsTheWindow() {
        var coalescer = RefreshCoalescer(debounce: .milliseconds(150), maxWait: .seconds(1))
        let t0 = ContinuousClock.now
        _ = coalescer.signal(at: t0)
        #expect(coalescer.signal(at: t0.advanced(by: .seconds(1))) == .fireNow)
        // The window reset when it fired, so the next signal waits again.
        #expect(coalescer.signal(at: t0.advanced(by: .seconds(1))) == .waitFor(.milliseconds(150)))
    }

    @Test("An explicit refresh also opens a fresh window")
    func didRefreshResetsTheWindow() {
        var coalescer = RefreshCoalescer(debounce: .milliseconds(150), maxWait: .seconds(1))
        let t0 = ContinuousClock.now
        _ = coalescer.signal(at: t0)
        coalescer.didRefresh()
        #expect(coalescer.signal(at: t0.advanced(by: .seconds(5))) == .waitFor(.milliseconds(150)))
    }
}
