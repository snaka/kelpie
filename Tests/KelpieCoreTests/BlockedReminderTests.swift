import Testing
import Foundation
@testable import KelpieCore

@Suite("BlockedReminder")
struct BlockedReminderTests {

    private func blocked(_ pane: String = "w0:p1") -> StateTransition {
        StateTransition(paneID: pane, workspaceID: "w0", from: .working, to: .blocked, title: "t")
    }

    @Test("A pane still blocked after the first interval is due for a reminder")
    func firstReminderAfterOneMinute() {
        var reminder = BlockedReminder()
        let t0 = ContinuousClock.now
        reminder.arm([blocked()], at: t0)
        #expect(reminder.due(at: t0.advanced(by: .seconds(60))) == ["w0:p1"])
    }

    @Test("A reminder does not repeat before the next interval has passed")
    func noRepeatWithinInterval() {
        var reminder = BlockedReminder()
        let t0 = ContinuousClock.now
        reminder.arm([blocked()], at: t0)
        _ = reminder.due(at: t0.advanced(by: .seconds(60)))
        #expect(reminder.due(at: t0.advanced(by: .seconds(61))).isEmpty)
    }

    @Test("The second reminder lands five minutes after the first")
    func secondReminderAfterFiveMinutes() {
        var reminder = BlockedReminder()
        let t0 = ContinuousClock.now
        reminder.arm([blocked()], at: t0)
        _ = reminder.due(at: t0.advanced(by: .seconds(60)))
        #expect(reminder.due(at: t0.advanced(by: .seconds(360))) == ["w0:p1"])
    }

    @Test("From the third reminder on, the interval stays at fifteen minutes")
    func laterRemindersStayFifteenMinutesApart() {
        var reminder = BlockedReminder()
        let t0 = ContinuousClock.now
        reminder.arm([blocked()], at: t0)
        _ = reminder.due(at: t0.advanced(by: .seconds(60)))
        _ = reminder.due(at: t0.advanced(by: .seconds(360)))
        #expect(reminder.due(at: t0.advanced(by: .seconds(1260))) == ["w0:p1"])
        #expect(reminder.due(at: t0.advanced(by: .seconds(2160))) == ["w0:p1"])
    }

    @Test("Panes blocked at different times advance independently")
    func panesAdvanceIndependently() {
        var reminder = BlockedReminder()
        let t0 = ContinuousClock.now
        reminder.arm([blocked("w0:p1")], at: t0)
        reminder.arm([blocked("w0:p2")], at: t0.advanced(by: .seconds(120)))
        #expect(reminder.due(at: t0.advanced(by: .seconds(60))) == ["w0:p1"])
        #expect(reminder.due(at: t0.advanced(by: .seconds(180))) == ["w0:p2"])
    }

    @Test("A pane that stops being blocked stops reminding")
    func resolvedPanesStopReminding() {
        var reminder = BlockedReminder()
        let t0 = ContinuousClock.now
        reminder.arm([blocked()], at: t0)
        reminder.retain(blocked: [])
        #expect(reminder.due(at: t0.advanced(by: .seconds(60))).isEmpty)
    }

    @Test("A pane still blocked survives the retain sweep")
    func stillBlockedPanesSurviveRetain() {
        var reminder = BlockedReminder()
        let t0 = ContinuousClock.now
        reminder.arm([blocked()], at: t0)
        reminder.retain(blocked: ["w0:p1"])
        #expect(reminder.due(at: t0.advanced(by: .seconds(60))) == ["w0:p1"])
    }

    @Test("The next deadline is the earliest pending reminder")
    func nextDeadlineIsTheEarliestPending() {
        var reminder = BlockedReminder()
        let t0 = ContinuousClock.now
        reminder.arm([blocked("w0:p1")], at: t0)
        reminder.arm([blocked("w0:p2")], at: t0.advanced(by: .seconds(30)))
        #expect(reminder.nextDeadline == t0.advanced(by: .seconds(60)))
    }

    @Test("Nothing pending means there is no deadline to wake for")
    func noDeadlineWhenNothingPending() {
        let reminder = BlockedReminder()
        #expect(reminder.nextDeadline == nil)
    }

    @Test("A pane blocked again starts its schedule over")
    func rearmingRestartsTheSchedule() {
        var reminder = BlockedReminder()
        let t0 = ContinuousClock.now
        reminder.arm([blocked()], at: t0)
        _ = reminder.due(at: t0.advanced(by: .seconds(60)))
        reminder.retain(blocked: [])
        reminder.arm([blocked()], at: t0.advanced(by: .seconds(120)))
        // One minute after being blocked again, not five after the last reminder.
        #expect(reminder.due(at: t0.advanced(by: .seconds(180))) == ["w0:p1"])
    }

    @Test("A long gap between checks still fires only once")
    func longGapFiresOnce() {
        var reminder = BlockedReminder()
        let t0 = ContinuousClock.now
        reminder.arm([blocked()], at: t0)
        // Waking from sleep an hour later must not deliver the backlog at once.
        #expect(reminder.due(at: t0.advanced(by: .seconds(3600))) == ["w0:p1"])
        #expect(reminder.due(at: t0.advanced(by: .seconds(3601))).isEmpty)
    }
}
