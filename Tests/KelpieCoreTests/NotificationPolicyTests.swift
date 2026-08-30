import Testing
@testable import KelpieCore

@Suite("NotificationPolicy")
struct NotificationPolicyTests {

    private func transition(from: AgentStatus?, to: AgentStatus, pane: String = "w0:p1") -> StateTransition {
        StateTransition(paneID: pane, workspaceID: "w0", from: from, to: to, title: "t")
    }

    @Test("A live transition into blocked is notifiable")
    func liveBlocked() {
        let result = NotificationPolicy.notifiable([transition(from: .working, to: .blocked)], phase: .live)
        #expect(result.count == 1)
    }

    @Test("A newly seen pane that is already blocked is notifiable when live")
    func liveNewlySeenBlocked() {
        let result = NotificationPolicy.notifiable([transition(from: nil, to: .blocked)], phase: .live)
        #expect(result.count == 1)
    }

    @Test("Bootstrap never notifies, so launching Kelpie is silent")
    func bootstrapSilent() {
        #expect(NotificationPolicy.notifiable([transition(from: nil, to: .blocked)], phase: .bootstrap).isEmpty)
    }

    @Test("Transitions to other states are not notifiable")
    func otherStates() {
        let transitions = [
            transition(from: .working, to: .done),
            transition(from: .blocked, to: .working),
            transition(from: .idle, to: .working),
            transition(from: .working, to: .idle),
        ]
        #expect(NotificationPolicy.notifiable(transitions, phase: .live).isEmpty)
    }

    @Test("Blocked to blocked is not a transition worth re-notifying")
    func stayingBlocked() {
        #expect(NotificationPolicy.notifiable([transition(from: .blocked, to: .blocked)], phase: .live).isEmpty)
    }

    @Test("Only the blocked transitions survive a mixed batch")
    func mixedBatch() {
        let transitions = [
            transition(from: .working, to: .done, pane: "w0:p1"),
            transition(from: .working, to: .blocked, pane: "w0:p2"),
            transition(from: .idle, to: .working, pane: "w0:p3"),
            transition(from: .idle, to: .blocked, pane: "w0:p4"),
        ]
        let result = NotificationPolicy.notifiable(transitions, phase: .live)
        #expect(result.map(\.paneID) == ["w0:p2", "w0:p4"])
    }
}
