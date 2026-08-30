import Testing
@testable import KelpieCore

@Suite("StatusCounts")
struct StatusCountsTests {

    private func state(_ statuses: [(String, AgentStatus, String?)]) -> SessionState {
        var s = SessionState()
        _ = s.replace(with: Snapshot(
            agents: statuses.map { pane, status, kind in
                AgentRecord(paneID: pane, workspaceID: "w0", revision: 1,
                            status: status, title: nil, agentKind: kind)
            },
            workspaces: [], protocolVersion: 20
        ))
        return s
    }

    @Test("Counts tally each status")
    func tallies() {
        let counts = StatusCounts(state: state([
            ("p1", .blocked, "claude"), ("p2", .working, "claude"),
            ("p3", .working, "claude"), ("p4", .done, "claude"),
            ("p5", .idle, "claude"), ("p6", .unknown, "claude"),
        ]))
        #expect(counts == StatusCounts(blocked: 1, working: 2, done: 1, idle: 1, unknown: 1))
    }

    @Test("Panes with no detected agent are not counted")
    func nonAgentPanesIgnored() {
        let counts = StatusCounts(state: state([("p1", .working, "claude"), ("p2", .working, nil)]))
        #expect(counts.working == 1)
    }

    @Test("Resting means nothing blocked, working or done")
    func resting() {
        #expect(StatusCounts(blocked: 0, working: 0, done: 0, idle: 4, unknown: 1).isResting)
        #expect(!StatusCounts(blocked: 0, working: 1, done: 0, idle: 0, unknown: 0).isResting)
        #expect(!StatusCounts(blocked: 0, working: 0, done: 1, idle: 0, unknown: 0).isResting)
    }
}
