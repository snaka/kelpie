import Testing
import Foundation
@testable import KelpieClient

@Suite("Wire")
struct WireTests {

    @Test("A request encodes to one newline-terminated JSON line")
    func encodeRequest() throws {
        let data = try Wire.encodeRequest(id: "f1", method: "agent.focus",
                                          params: AgentTargetParams(target: "w0:p1"))
        let text = String(data: data, encoding: .utf8)!
        #expect(text.hasSuffix("\n"))
        #expect(!text.dropLast().contains("\n"))

        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["id"] as? String == "f1")
        #expect(object["method"] as? String == "agent.focus")
        #expect((object["params"] as? [String: Any])?["target"] as? String == "w0:p1")
    }

    @Test("Methods with no parameters still send an empty params object")
    func encodeEmptyParams() throws {
        let data = try Wire.encodeRequest(id: "s1", method: "session.snapshot", params: EmptyParams())
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["params"] as? [String: Any] != nil)
    }

    @Test("Subscribe params encode as a list of typed subscriptions")
    func encodeSubscribe() throws {
        let data = try Wire.encodeRequest(id: "sub1", method: "events.subscribe",
                                          params: SubscribeParams(types: ["pane.updated", "pane.closed"]))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let params = object["params"] as! [String: Any]
        let subs = params["subscriptions"] as! [[String: Any]]
        #expect(subs.map { $0["type"] as! String } == ["pane.updated", "pane.closed"])
    }

    @Test("A success response decodes to a result carrying its raw payload")
    func decodeResult() throws {
        let line = Data(#"{"id":"p1","result":{"type":"pong","version":"0.8.2","protocol":20,"capabilities":{"live_handoff":true}}}"#.utf8)
        guard case .result(let id, let payload) = try Wire.decode(line: line) else {
            Issue.record("expected a result"); return
        }
        #expect(id == "p1")
        let pong = try JSONDecoder().decode(PongPayload.self, from: payload)
        #expect(pong.version == "0.8.2")
        #expect(pong.protocolVersion == 20)
    }

    @Test("An error response decodes to a failure with its code and message")
    func decodeFailure() throws {
        let line = Data(#"{"id":"sub1","error":{"code":"invalid_request","message":"missing field pane_id"}}"#.utf8)
        guard case .failure(let id, let code, let message) = try Wire.decode(line: line) else {
            Issue.record("expected a failure"); return
        }
        #expect(id == "sub1")
        #expect(code == "invalid_request")
        #expect(message == "missing field pane_id")
    }

    @Test("A subscription event decodes to an event carrying the whole line")
    func decodeEvent() throws {
        let line = Data(#"{"data":{"pane_id":"w0:p1","type":"pane_closed","workspace_id":"w0"},"event":"pane_closed"}"#.utf8)
        guard case .event(let kind, let raw) = try Wire.decode(line: line) else {
            Issue.record("expected an event"); return
        }
        #expect(kind == "pane_closed")
        #expect(raw == line)
    }

    @Test("An event is recognised even though it also has no id")
    func eventTakesPrecedence() throws {
        let line = Data(#"{"data":{"type":"workspace_focused","workspace_id":"w0"},"event":"workspace_focused"}"#.utf8)
        if case .event = try Wire.decode(line: line) {} else {
            Issue.record("expected an event")
        }
    }

    @Test("A line that is neither a response nor an event throws")
    func decodeGarbage() {
        #expect(throws: (any Error).self) {
            try Wire.decode(line: Data(#"{"nonsense":true}"#.utf8))
        }
    }
}
