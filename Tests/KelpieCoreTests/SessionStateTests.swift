import Testing
import Foundation
@testable import KelpieCore

@Suite("SessionState")
struct SessionStateTests {

    private func agent(
        _ pane: String,
        _ status: AgentStatus,
        workspace: String = "w0",
        title: String? = "t",
        kind: String? = "claude"
    ) -> AgentRecord {
        AgentRecord(paneID: pane, workspaceID: workspace,
                    status: status, title: title, agentKind: kind)
    }

    @Test("Replace installs agents and workspace labels")
    func replaceInstallsSnapshot() {
        var state = SessionState()
        let transitions = state.replace(with: Snapshot(
            agents: [agent("w0:p1", .working)],
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
        _ = state.replace(with: Snapshot(agents: [agent("w0:p1", .idle)],
                                         workspaces: [], protocolVersion: 20))
        let transitions = state.replace(with: Snapshot(agents: [], workspaces: [], protocolVersion: 20))
        #expect(state.agentPanes.isEmpty)
        #expect(transitions.isEmpty)
    }

    @Test("An unknown workspace falls back to its id")
    func labelFallback() {
        let state = SessionState()
        #expect(state.label(for: "w9") == "w9")
    }

    @Test("Replacing with a snapshot reports a status change as a transition")
    func replaceReportsStatusChange() {
        var state = SessionState()
        _ = state.replace(with: Snapshot(agents: [agent("w0:p1", .done)],
                                         workspaces: [], protocolVersion: 20))
        // A status change with no terminal-title change — exactly the shape
        // herdr emits when a done mark clears. herdr's `revision` does not move
        // for it, which is why the snapshot, not any event ordering, decides.
        let transitions = state.replace(with: Snapshot(
            agents: [agent("w0:p1", .idle)], workspaces: [], protocolVersion: 20
        ))
        #expect(transitions == [StateTransition(
            paneID: "w0:p1", workspaceID: "w0", from: .done, to: .idle, title: "t"
        )])
        #expect(state.agents["w0:p1"]?.status == .idle)
    }

    @Test("Replacing with an unchanged snapshot reports nothing")
    func replaceReportsNothingWhenUnchanged() {
        var state = SessionState()
        let snapshot = Snapshot(agents: [agent("w0:p1", .working)],
                                workspaces: [], protocolVersion: 20)
        _ = state.replace(with: snapshot)
        #expect(state.replace(with: snapshot).isEmpty)
    }

    @Test("Panes with no detected agent are excluded from agentPanes")
    func nonAgentPanesExcluded() {
        var state = SessionState()
        _ = state.replace(with: Snapshot(
            agents: [agent("w0:p1", .working),
                     agent("w0:p2", .unknown, title: nil, kind: nil)],
            workspaces: [], protocolVersion: 20
        ))
        #expect(state.agentPanes.map(\.paneID) == ["w0:p1"])
    }
}
