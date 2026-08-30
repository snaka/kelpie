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
        #expect(record.revision == 2)
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

@Suite("LiveEvent decoding")
struct LiveEventDecodingTests {

    @Test("pane_updated yields a pane upsert")
    func paneUpdated() throws {
        let line = Data(#"""
        {"data":{"pane":{"agent":"claude","agent_status":"working","pane_id":"w0:p1","revision":5,"tab_id":"w0:t1","terminal_id":"t","terminal_title":"◑ 作業中","terminal_title_stripped":"作業中","workspace_id":"w0"},"type":"pane_updated"},"event":"pane_updated"}
        """#.utf8)
        let event = try LiveEvent.decode(eventLine: line)
        #expect(event == .paneUpserted(AgentRecord(
            paneID: "w0:p1", workspaceID: "w0", revision: 5,
            status: .working, title: "作業中", agentKind: "claude"
        )))
    }

    @Test("pane_created yields a pane upsert")
    func paneCreated() throws {
        let line = Data(#"""
        {"data":{"pane":{"agent_status":"unknown","pane_id":"w0:p2","revision":0,"tab_id":"w0:t1","terminal_id":"t","workspace_id":"w0"},"type":"pane_created"},"event":"pane_created"}
        """#.utf8)
        let event = try LiveEvent.decode(eventLine: line)
        #expect(event == .paneUpserted(AgentRecord(
            paneID: "w0:p2", workspaceID: "w0", revision: 0,
            status: .unknown, title: nil, agentKind: nil
        )))
    }

    @Test("pane_closed yields a pane removal")
    func paneClosed() throws {
        let line = Data(#"{"data":{"pane_id":"w0:p2","type":"pane_closed","workspace_id":"w0"},"event":"pane_closed"}"#.utf8)
        #expect(try LiveEvent.decode(eventLine: line) == .paneClosed(paneID: "w0:p2"))
    }

    @Test("workspace_renamed yields a workspace upsert with the new label")
    func workspaceRenamed() throws {
        let line = Data(#"{"data":{"label":"kelpie","type":"workspace_renamed","workspace_id":"w0"},"event":"workspace_renamed"}"#.utf8)
        #expect(try LiveEvent.decode(eventLine: line)
            == .workspaceUpserted(WorkspaceRecord(workspaceID: "w0", label: "kelpie")))
    }

    @Test("workspace_created yields a workspace upsert")
    func workspaceCreated() throws {
        let line = Data(#"""
        {"data":{"type":"workspace_created","workspace":{"active_tab_id":"w0:t1","agent_status":"idle","focused":true,"label":"herdr","number":1,"pane_count":1,"tab_count":1,"workspace_id":"w0"}},"event":"workspace_created"}
        """#.utf8)
        #expect(try LiveEvent.decode(eventLine: line)
            == .workspaceUpserted(WorkspaceRecord(workspaceID: "w0", label: "herdr")))
    }

    @Test("workspace_closed yields a workspace removal")
    func workspaceClosed() throws {
        let line = Data(#"{"data":{"type":"workspace_closed","workspace_id":"w0"},"event":"workspace_closed"}"#.utf8)
        #expect(try LiveEvent.decode(eventLine: line) == .workspaceClosed(workspaceID: "w0"))
    }

    @Test("Uninteresting events decode to nil rather than throwing")
    func ignoredEvent() throws {
        let line = Data(#"{"data":{"type":"workspace_focused","workspace_id":"w0"},"event":"workspace_focused"}"#.utf8)
        #expect(try LiveEvent.decode(eventLine: line) == nil)
    }
}
