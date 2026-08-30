import Testing
import Foundation
@testable import KelpieCore

@Suite("Decoding")
struct DecodingTests {

    /// Captured verbatim from `herdr api snapshot` on herdr 0.8.2.
    static let agentJSON = Data(#"""
    {"agent":"claude","agent_status":"idle","cwd":"/Users/snaka/ghq/github.com/snaka/larning-math","focused":false,"foreground_cwd":"/Users/snaka/ghq/github.com/snaka/larning-math","pane_id":"wX:p1","revision":2,"state_change_seq":9,"tab_id":"wX:t1","terminal_id":"term_65a3e58eee69c1","terminal_title":"✳ 教材の準備","terminal_title_stripped":"教材の準備","workspace_id":"wX"}
    """#.utf8)

    static let workspaceJSON = Data(#"""
    {"active_tab_id":"wX:t1","agent_status":"idle","focused":false,"label":"larning-math","number":1,"pane_count":1,"tab_count":1,"workspace_id":"wX"}
    """#.utf8)

    @Test("Agent record decodes the fields Kelpie uses and ignores the rest")
    func agentRecord() throws {
        let record = try JSONDecoder().decode(AgentRecord.self, from: Self.agentJSON)
        #expect(record.paneID == "wX:p1")
        #expect(record.workspaceID == "wX")
        #expect(record.status == .idle)
        #expect(record.title == "教材の準備")
        #expect(record.agentKind == "claude")
        #expect(record.isAgentPane)
    }

    @Test("A pane with no detected agent is not an agent pane")
    func nonAgentPane() throws {
        let json = Data(#"{"agent_status":"unknown","pane_id":"w0:p2","revision":0,"tab_id":"w0:t1","terminal_id":"term_x","workspace_id":"w0"}"#.utf8)
        let record = try JSONDecoder().decode(AgentRecord.self, from: json)
        #expect(record.agentKind == nil)
        #expect(!record.isAgentPane)
        #expect(record.title == nil)
    }

    @Test("Workspace record decodes id and label")
    func workspaceRecord() throws {
        let record = try JSONDecoder().decode(WorkspaceRecord.self, from: Self.workspaceJSON)
        #expect(record.workspaceID == "wX")
        #expect(record.label == "larning-math")
    }

    @Test("Snapshot envelope unwraps the nested snapshot object")
    func snapshotEnvelope() throws {
        let payload = Data(#"""
        {"type":"session_snapshot","snapshot":{"protocol":20,"version":"0.8.2","agents":[\#(String(data: Self.agentJSON, encoding: .utf8)!)],"workspaces":[\#(String(data: Self.workspaceJSON, encoding: .utf8)!)],"panes":[],"tabs":[],"layouts":[]}}
        """#.utf8)
        let snapshot = try SnapshotEnvelope.decode(resultPayload: payload)
        #expect(snapshot.protocolVersion == 20)
        #expect(snapshot.agents.count == 1)
        #expect(snapshot.agents[0].paneID == "wX:p1")
        #expect(snapshot.workspaces.count == 1)
        #expect(snapshot.workspaces[0].label == "larning-math")
    }
}

@Suite("LiveEvent classification")
struct LiveEventClassificationTests {

    @Test("Pane event kinds classify as a pane change")
    func paneKinds() {
        #expect(LiveEvent.classify(eventKind: "pane_created") == .paneChanged)
        #expect(LiveEvent.classify(eventKind: "pane_updated") == .paneChanged)
        #expect(LiveEvent.classify(eventKind: "pane_closed") == .paneChanged)
    }

    @Test("Workspace event kinds classify as a workspace change")
    func workspaceKinds() {
        #expect(LiveEvent.classify(eventKind: "workspace_created") == .workspaceChanged)
        #expect(LiveEvent.classify(eventKind: "workspace_updated") == .workspaceChanged)
        #expect(LiveEvent.classify(eventKind: "workspace_renamed") == .workspaceChanged)
        #expect(LiveEvent.classify(eventKind: "workspace_closed") == .workspaceChanged)
    }

    @Test("Uninteresting event kinds classify as nothing")
    func ignoredKinds() {
        #expect(LiveEvent.classify(eventKind: "workspace_focused") == nil)
        #expect(LiveEvent.classify(eventKind: "") == nil)
    }

    @Test("The dotted subscription names are not event kinds")
    func subscriptionNamesAreNotEventKinds() {
        // herdr subscribes by `pane.updated` but emits `pane_updated`. Matching
        // the wrong form would classify nothing at all, so it is pinned here.
        #expect(LiveEvent.classify(eventKind: "pane.updated") == nil)
    }
}
