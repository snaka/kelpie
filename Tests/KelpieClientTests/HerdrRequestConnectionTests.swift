import Testing
import Foundation
@testable import KelpieClient
@testable import KelpieCore

@Suite("HerdrRequestConnection")
struct HerdrRequestConnectionTests {

    private func line(_ text: String) -> Data { Data((text + "\n").utf8) }

    private func requestObject(_ data: Data) throws -> [String: Any] {
        let trimmed = data.dropLast()   // strip the newline
        return try JSONSerialization.jsonObject(with: Data(trimmed)) as! [String: Any]
    }

    @Test("Ping sends the ping method and returns the parsed pong")
    func ping() async throws {
        let transport = FakeTransport()
        let connection = HerdrRequestConnection(transport: transport)
        try await connection.open()

        async let pong = connection.ping()
        try await Task.sleep(for: .milliseconds(20))
        let sent = try requestObject(transport.sentLines[0])
        transport.feed(line(#"{"id":"\#(sent["id"] as! String)","result":{"type":"pong","version":"0.8.2","protocol":20}}"#))

        let result = try await pong
        #expect(sent["method"] as? String == "ping")
        #expect(result.version == "0.8.2")
        #expect(result.protocolVersion == 20)
    }

    @Test("Snapshot unwraps the nested snapshot payload")
    func snapshot() async throws {
        let transport = FakeTransport()
        let connection = HerdrRequestConnection(transport: transport)
        try await connection.open()

        async let snapshot = connection.snapshot()
        try await Task.sleep(for: .milliseconds(20))
        let id = try requestObject(transport.sentLines[0])["id"] as! String
        transport.feed(line("""
        {"id":"\(id)","result":{"type":"session_snapshot","snapshot":{"protocol":20,"version":"0.8.2","agents":[{"agent":"claude","agent_status":"blocked","pane_id":"w0:p1","revision":7,"tab_id":"w0:t1","terminal_id":"t","terminal_title_stripped":"待ち","workspace_id":"w0"}],"workspaces":[{"active_tab_id":"w0:t1","agent_status":"blocked","focused":true,"label":"herdr","number":1,"pane_count":1,"tab_count":1,"workspace_id":"w0"}]}}}
        """))

        let result = try await snapshot
        #expect(result.protocolVersion == 20)
        #expect(result.agents.map(\.paneID) == ["w0:p1"])
        #expect(result.workspaces.map(\.label) == ["herdr"])
    }

    @Test("Focus sends agent.focus with the pane id as the target")
    func focus() async throws {
        let transport = FakeTransport()
        let connection = HerdrRequestConnection(transport: transport)
        try await connection.open()

        async let focusing: Void = connection.focus(paneID: "w0:p1")
        try await Task.sleep(for: .milliseconds(20))
        let sent = try requestObject(transport.sentLines[0])
        transport.feed(line(#"{"id":"\#(sent["id"] as! String)","result":{"type":"ok"}}"#))
        try await focusing

        #expect(sent["method"] as? String == "agent.focus")
        #expect((sent["params"] as? [String: Any])?["target"] as? String == "w0:p1")
    }

    @Test("A herdr error response surfaces as a typed error")
    func errorResponse() async throws {
        let transport = FakeTransport()
        let connection = HerdrRequestConnection(transport: transport)
        try await connection.open()

        async let focusing: Void = connection.focus(paneID: "nope")
        try await Task.sleep(for: .milliseconds(20))
        let id = try requestObject(transport.sentLines[0])["id"] as! String
        transport.feed(line(#"{"id":"\#(id)","error":{"code":"not_found","message":"no such agent"}}"#))

        // `#expect(throws:)` can't take an `async let` capture directly (the
        // macro's closure can't capture async-let bindings on this
        // toolchain), so the error is checked with do/catch instead.
        do {
            try await focusing
            Issue.record("expected focus(paneID:) to throw")
        } catch let error as RequestError {
            #expect(error == .herdr(code: "not_found", message: "no such agent"))
        }
    }

    @Test("Responses arriving out of order are matched by id")
    func outOfOrderResponses() async throws {
        let transport = FakeTransport()
        let connection = HerdrRequestConnection(transport: transport)
        try await connection.open()

        async let first = connection.ping()
        try await Task.sleep(for: .milliseconds(20))
        async let second = connection.ping()
        try await Task.sleep(for: .milliseconds(20))

        let idA = try requestObject(transport.sentLines[0])["id"] as! String
        let idB = try requestObject(transport.sentLines[1])["id"] as! String
        #expect(idA != idB)

        transport.feed(line(#"{"id":"\#(idB)","result":{"type":"pong","version":"B","protocol":20}}"#))
        transport.feed(line(#"{"id":"\#(idA)","result":{"type":"pong","version":"A","protocol":20}}"#))

        #expect(try await first.version == "A")
        #expect(try await second.version == "B")
    }

    @Test("A response split across chunks is still matched")
    func splitResponse() async throws {
        let transport = FakeTransport()
        let connection = HerdrRequestConnection(transport: transport)
        try await connection.open()

        async let pong = connection.ping()
        try await Task.sleep(for: .milliseconds(20))
        let id = try requestObject(transport.sentLines[0])["id"] as! String
        let whole = #"{"id":"\#(id)","result":{"type":"pong","version":"0.8.2","protocol":20}}"# + "\n"
        let bytes = Array(whole.utf8)
        transport.feed(Data(bytes[..<10]))
        transport.feed(Data(bytes[10...]))

        #expect(try await pong.protocolVersion == 20)
    }

    @Test("A closed stream fails the pending request instead of hanging")
    func streamEnds() async throws {
        let transport = FakeTransport()
        let connection = HerdrRequestConnection(transport: transport)
        try await connection.open()

        async let pong = connection.ping()
        try await Task.sleep(for: .milliseconds(20))
        transport.finish()

        // See the note in `errorResponse()` above: do/catch instead of the
        // `#expect(throws:)` closure form, which can't capture `async let`.
        do {
            _ = try await pong
            Issue.record("expected ping() to throw once the stream ends")
        } catch let error as RequestError {
            #expect(error == .streamEnded)
        }
    }

    @Test("A call made after the stream has already ended fails immediately instead of hanging")
    func callAfterStreamEnded() async throws {
        let transport = FakeTransport()
        let connection = HerdrRequestConnection(transport: transport)
        try await connection.open()

        transport.finish()
        // Give the reader task a moment to observe the finished stream and
        // mark the connection terminated before the next call is made.
        try await Task.sleep(for: .milliseconds(20))

        do {
            _ = try await connection.ping()
            Issue.record("expected ping() to throw once the connection has already terminated")
        } catch let error as RequestError {
            #expect(error == .streamEnded)
        }
    }

    @Test("A call made after close() fails immediately instead of hanging")
    func callAfterClose() async throws {
        let transport = FakeTransport()
        let connection = HerdrRequestConnection(transport: transport)
        try await connection.open()

        await connection.close()

        do {
            _ = try await connection.ping()
            Issue.record("expected ping() to throw after close()")
        } catch let error as RequestError {
            #expect(error == .streamEnded)
        }
    }
}
