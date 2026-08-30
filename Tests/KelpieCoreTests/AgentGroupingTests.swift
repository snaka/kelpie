import Testing
@testable import KelpieCore

@Suite("AgentGrouping")
struct AgentGroupingTests {

    private func makeState() -> SessionState {
        var s = SessionState()
        _ = s.replace(with: Snapshot(
            agents: [
                AgentRecord(paneID: "wZ:p1", workspaceID: "wZ", revision: 1, status: .blocked,
                            title: "Google Workspace ドメイン設定", agentKind: "claude"),
                AgentRecord(paneID: "w0:p1", workspaceID: "w0", revision: 1, status: .working,
                            title: "Agent状態インジケーター", agentKind: "claude"),
                AgentRecord(paneID: "wX:p1", workspaceID: "wX", revision: 1, status: .working,
                            title: "教材の準備", agentKind: "claude"),
                AgentRecord(paneID: "wY:p1", workspaceID: "wY", revision: 1, status: .done,
                            title: "Split PR #746 review", agentKind: "claude"),
                AgentRecord(paneID: "wQ:p1", workspaceID: "wQ", revision: 1, status: .idle,
                            title: nil, agentKind: "codex"),
                AgentRecord(paneID: "w0:p2", workspaceID: "w0", revision: 1, status: .working,
                            title: nil, agentKind: nil),
            ],
            workspaces: [
                WorkspaceRecord(workspaceID: "w0", label: "herdr"),
                WorkspaceRecord(workspaceID: "wX", label: "larning-math"),
                WorkspaceRecord(workspaceID: "wY", label: "split"),
                WorkspaceRecord(workspaceID: "wZ", label: "googleworkspace"),
            ],
            protocolVersion: 20
        ))
        return s
    }

    @Test("Groups are ordered blocked, working, done, idle and skip empty ones")
    func ordering() {
        let groups = AgentGrouping.groups(state: makeState())
        #expect(groups.map(\.status) == [.blocked, .working, .done, .idle])
    }

    @Test("Rows are sorted by workspace label within a group")
    func rowOrdering() {
        let groups = AgentGrouping.groups(state: makeState())
        let working = groups.first { $0.status == .working }
        #expect(working?.rows.map(\.workspaceLabel) == ["herdr", "larning-math"])
    }

    @Test("Rows carry the workspace label and stripped title")
    func rowContent() {
        let groups = AgentGrouping.groups(state: makeState())
        let blocked = groups.first { $0.status == .blocked }
        #expect(blocked?.rows == [AgentRow(
            paneID: "wZ:p1",
            workspaceLabel: "googleworkspace",
            title: "Google Workspace ドメイン設定"
        )])
    }

    @Test("Panes with no detected agent do not appear")
    func nonAgentPanesExcluded() {
        let groups = AgentGrouping.groups(state: makeState())
        let allPanes = groups.flatMap(\.rows).map(\.paneID)
        #expect(!allPanes.contains("w0:p2"))
    }

    @Test("An empty state produces no groups")
    func emptyState() {
        #expect(AgentGrouping.groups(state: SessionState()).isEmpty)
    }

    private func stateWithTiebreakerTest() -> SessionState {
        var s = SessionState()
        _ = s.replace(with: Snapshot(
            agents: [
                AgentRecord(paneID: "w0:p3", workspaceID: "w0", revision: 1, status: .working,
                            title: "Third pane", agentKind: "claude"),
                AgentRecord(paneID: "w0:p1", workspaceID: "w0", revision: 1, status: .working,
                            title: "First pane", agentKind: "claude"),
            ],
            workspaces: [
                WorkspaceRecord(workspaceID: "w0", label: "workspace"),
            ],
            protocolVersion: 20
        ))
        return s
    }

    @Test("Rows within a workspace are sorted by pane ID for stable ordering")
    func paneIDTiebreaker() {
        let groups = AgentGrouping.groups(state: stateWithTiebreakerTest())
        let working = groups.first { $0.status == .working }
        #expect(working?.rows.map(\.paneID) == ["w0:p1", "w0:p3"])
    }
}
