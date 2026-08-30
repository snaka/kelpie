import Testing
import Foundation
@testable import KelpieCore

@Suite("SessionState")
struct SessionStateTests {

    private func agent(
        _ pane: String,
        _ status: AgentStatus,
        revision: UInt64,
        workspace: String = "w0",
        title: String? = "t",
        kind: String? = "claude"
    ) -> AgentRecord {
        AgentRecord(paneID: pane, workspaceID: workspace, revision: revision,
                    status: status, title: title, agentKind: kind)
    }

    @Test("Replace installs agents and workspace labels")
    func replaceInstallsSnapshot() {
        var state = SessionState()
        let transitions = state.replace(with: Snapshot(
            agents: [agent("w0:p1", .working, revision: 3)],
            workspaces: [WorkspaceRecord(workspaceID: "w0", label: "herdr")],
            protocolVersion: 20
        ))
        #expect(state.agentPanes.count == 1)
        #expect(state.label(for: "w0") == "herdr")
        #expect(transitions == [StateTransition(
            paneID: "w0:p1", workspaceID: "w0", from: nil, to: .working, title: "t"
        )])
    }

    @Test("Replace drops panes that are gone and reports no transition for them")
    func replaceDropsMissingPanes() {
        var state = SessionState()
        _ = state.replace(with: Snapshot(agents: [agent("w0:p1", .idle, revision: 1)],
                                         workspaces: [], protocolVersion: 20))
        let transitions = state.replace(with: Snapshot(agents: [], workspaces: [], protocolVersion: 20))
        #expect(state.agentPanes.isEmpty)
        #expect(transitions.isEmpty)
    }

    @Test("A newer revision updates the pane and reports the transition")
    func newerRevisionApplies() {
        var state = SessionState()
        _ = state.replace(with: Snapshot(agents: [agent("w0:p1", .working, revision: 3)],
                                         workspaces: [], protocolVersion: 20))
        let transitions = state.apply(.paneUpserted(agent("w0:p1", .blocked, revision: 4)))
        #expect(state.agents["w0:p1"]?.status == .blocked)
        #expect(transitions == [StateTransition(
            paneID: "w0:p1", workspaceID: "w0", from: .working, to: .blocked, title: "t"
        )])
    }

    @Test("A replayed lower revision is discarded")
    func staleRevisionDiscarded() {
        var state = SessionState()
        _ = state.replace(with: Snapshot(agents: [agent("w0:p1", .blocked, revision: 4)],
                                         workspaces: [], protocolVersion: 20))
        let transitions = state.apply(.paneUpserted(agent("w0:p1", .unknown, revision: 0)))
        #expect(state.agents["w0:p1"]?.status == .blocked)
        #expect(transitions.isEmpty)
    }

    @Test("A repeated identical revision is discarded")
    func equalRevisionDiscarded() {
        var state = SessionState()
        _ = state.replace(with: Snapshot(agents: [agent("w0:p1", .working, revision: 4)],
                                         workspaces: [], protocolVersion: 20))
        #expect(state.apply(.paneUpserted(agent("w0:p1", .blocked, revision: 4))).isEmpty)
        #expect(state.agents["w0:p1"]?.status == .working)
    }

    @Test("A newer revision with an unchanged status reports no transition")
    func unchangedStatusIsNotATransition() {
        var state = SessionState()
        _ = state.replace(with: Snapshot(agents: [agent("w0:p1", .working, revision: 3)],
                                         workspaces: [], protocolVersion: 20))
        let transitions = state.apply(.paneUpserted(agent("w0:p1", .working, revision: 4, title: "new")))
        #expect(transitions.isEmpty)
        #expect(state.agents["w0:p1"]?.title == "new")
    }

    @Test("Closing a pane removes it and reports no transition")
    func paneClosedRemoves() {
        var state = SessionState()
        _ = state.replace(with: Snapshot(agents: [agent("w0:p1", .working, revision: 1)],
                                         workspaces: [], protocolVersion: 20))
        #expect(state.apply(.paneClosed(paneID: "w0:p1")).isEmpty)
        #expect(state.agents["w0:p1"] == nil)
    }

    @Test("Workspace upsert and close maintain the label map")
    func workspaceLabels() {
        var state = SessionState()
        _ = state.apply(.workspaceUpserted(WorkspaceRecord(workspaceID: "w0", label: "old")))
        _ = state.apply(.workspaceUpserted(WorkspaceRecord(workspaceID: "w0", label: "new")))
        #expect(state.label(for: "w0") == "new")
        _ = state.apply(.workspaceClosed(workspaceID: "w0"))
        #expect(state.label(for: "w0") == "w0")
    }

    @Test("An unknown workspace falls back to its id")
    func labelFallback() {
        let state = SessionState()
        #expect(state.label(for: "w9") == "w9")
    }

    @Test("Panes with no detected agent are excluded from agentPanes")
    func nonAgentPanesExcluded() {
        var state = SessionState()
        _ = state.replace(with: Snapshot(
            agents: [agent("w0:p1", .working, revision: 1),
                     agent("w0:p2", .unknown, revision: 1, title: nil, kind: nil)],
            workspaces: [], protocolVersion: 20
        ))
        #expect(state.agentPanes.map(\.paneID) == ["w0:p1"])
    }
}
