import Testing
import Foundation
@testable import KelpieCore

@Suite("BlockedEmphasis")
struct BlockedEmphasisTests {

    @Test("Nothing blocked means no emphasis and no deadline to wake for")
    func nothingBlocked() {
        var emphasis = BlockedEmphasis()
        let t0 = ContinuousClock.now
        emphasis.retain(blocked: [], at: t0)
        #expect(emphasis.level(at: t0) == .none)
        #expect(emphasis.nextDeadline(at: t0) == nil)
    }

    @Test("A pane that just blocked stays unemphasised for the first minute")
    func quietForTheFirstMinute() {
        var emphasis = BlockedEmphasis()
        let t0 = ContinuousClock.now
        emphasis.retain(blocked: ["w0:p1"], at: t0)
        #expect(emphasis.level(at: t0) == .none)
        #expect(emphasis.level(at: t0.advanced(by: .seconds(59))) == .none)
    }

    @Test("A minute of being ignored raises the emphasis to gentle")
    func gentleAfterOneMinute() {
        var emphasis = BlockedEmphasis()
        let t0 = ContinuousClock.now
        emphasis.retain(blocked: ["w0:p1"], at: t0)
        #expect(emphasis.level(at: t0.advanced(by: .seconds(60))) == .gentle)
        #expect(emphasis.level(at: t0.advanced(by: .seconds(299))) == .gentle)
    }

    @Test("Five minutes of being ignored raises the emphasis to insistent")
    func insistentAfterFiveMinutes() {
        var emphasis = BlockedEmphasis()
        let t0 = ContinuousClock.now
        emphasis.retain(blocked: ["w0:p1"], at: t0)
        #expect(emphasis.level(at: t0.advanced(by: .seconds(300))) == .insistent)
        #expect(emphasis.level(at: t0.advanced(by: .seconds(3600))) == .insistent)
    }

    @Test("Emphasis follows the longest-blocked pane, not the newest one")
    func oldestPaneWins() {
        var emphasis = BlockedEmphasis()
        let t0 = ContinuousClock.now
        emphasis.retain(blocked: ["w0:p1"], at: t0)
        emphasis.retain(blocked: ["w0:p1", "w0:p2"], at: t0.advanced(by: .seconds(290)))
        #expect(emphasis.level(at: t0.advanced(by: .seconds(300))) == .insistent)
    }

    @Test("A pane that keeps being blocked does not have its clock restarted")
    func clockDoesNotRestart() {
        var emphasis = BlockedEmphasis()
        let t0 = ContinuousClock.now
        emphasis.retain(blocked: ["w0:p1"], at: t0)
        emphasis.retain(blocked: ["w0:p1"], at: t0.advanced(by: .seconds(30)))
        #expect(emphasis.level(at: t0.advanced(by: .seconds(60))) == .gentle)
    }

    @Test("Leaving blocked and returning to it starts the clock over")
    func leavingBlockedResetsTheClock() {
        var emphasis = BlockedEmphasis()
        let t0 = ContinuousClock.now
        emphasis.retain(blocked: ["w0:p1"], at: t0)
        emphasis.retain(blocked: [], at: t0.advanced(by: .seconds(50)))
        emphasis.retain(blocked: ["w0:p1"], at: t0.advanced(by: .seconds(55)))
        #expect(emphasis.level(at: t0.advanced(by: .seconds(60))) == .none)
        #expect(emphasis.level(at: t0.advanced(by: .seconds(115))) == .gentle)
    }

    @Test("The next deadline is the moment the emphasis would rise")
    func nextDeadlineIsTheNextThreshold() {
        var emphasis = BlockedEmphasis()
        let t0 = ContinuousClock.now
        emphasis.retain(blocked: ["w0:p1"], at: t0)
        #expect(emphasis.nextDeadline(at: t0) == t0.advanced(by: .seconds(60)))
        #expect(emphasis.nextDeadline(at: t0.advanced(by: .seconds(60)))
                == t0.advanced(by: .seconds(300)))
    }

    @Test("Once insistent there is nothing left to wake up for")
    func noDeadlineAtTheTopLevel() {
        var emphasis = BlockedEmphasis()
        let t0 = ContinuousClock.now
        emphasis.retain(blocked: ["w0:p1"], at: t0)
        #expect(emphasis.nextDeadline(at: t0.advanced(by: .seconds(300))) == nil)
    }
}
