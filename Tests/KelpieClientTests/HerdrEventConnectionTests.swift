import Testing
import Foundation
@testable import KelpieClient
@testable import KelpieCore

@Suite("HerdrEventConnection")
struct HerdrEventConnectionTests {

    private func line(_ text: String) -> Data { Data((text + "\n").utf8) }

    private let ack = #"{"id":"kelpie-sub","result":{"type":"subscription_started"}}"#

    private let updated = #"""
    {"data":{"pane":{"agent":"claude","agent_status":"blocked","pane_id":"w0:p1","revision":9,"tab_id":"w0:t1","terminal_id":"t","terminal_title_stripped":"待ち","workspace_id":"w0"},"type":"pane_updated"},"event":"pane_updated"}
    """#

    @Test("Subscribe sends events.subscribe with the documented type list")
    func subscribeRequest() async throws {
        let transport = FakeTransport(scriptedChunks: [line(ack)])
        let connection = HerdrEventConnection(transport: transport)
        _ = try await connection.subscribe()

        let sent = try JSONSerialization.jsonObject(
            with: Data(transport.sentLines[0].dropLast())
        ) as! [String: Any]
        #expect(sent["method"] as? String == "events.subscribe")
        let subs = (sent["params"] as! [String: Any])["subscriptions"] as! [[String: Any]]
        #expect(subs.map { $0["type"] as! String } == HerdrEventConnection.subscriptionTypes)
    }

    @Test("Pane events arrive on the stream after the acknowledgement")
    func streamsEvents() async throws {
        let transport = FakeTransport(scriptedChunks: [line(ack)])
        let connection = HerdrEventConnection(transport: transport)
        let stream = try await connection.subscribe()

        transport.feed(line(updated))
        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()

        #expect(event == .paneUpserted(AgentRecord(
            paneID: "w0:p1", workspaceID: "w0", revision: 9,
            status: .blocked, title: "待ち", agentKind: "claude"
        )))
    }

    @Test("Uninteresting events are filtered out rather than delivered")
    func filtersUninteresting() async throws {
        let transport = FakeTransport(scriptedChunks: [line(ack)])
        let connection = HerdrEventConnection(transport: transport)
        let stream = try await connection.subscribe()

        transport.feed(line(#"{"data":{"type":"workspace_focused","workspace_id":"w0"},"event":"workspace_focused"}"#))
        transport.feed(line(updated))

        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        // The focus event was dropped, so the first delivered event is the
        // pane update.
        if case .paneUpserted(let record) = event {
            #expect(record.paneID == "w0:p1")
        } else {
            Issue.record("expected a pane upsert, got \(String(describing: event))")
        }
    }

    @Test("A rejected subscription throws instead of returning a dead stream")
    func rejectedSubscription() async {
        let transport = FakeTransport(scriptedChunks: [
            line(#"{"id":"kelpie-sub","error":{"code":"invalid_request","message":"missing field pane_id"}}"#)
        ])
        let connection = HerdrEventConnection(transport: transport)

        await #expect(throws: EventConnectionError.subscriptionRejected(
            code: "invalid_request", message: "missing field pane_id"
        )) {
            _ = try await connection.subscribe()
        }
    }

    @Test("A rejected subscription closes the transport instead of leaking it")
    func rejectedSubscriptionClosesTransport() async {
        let transport = FakeTransport(scriptedChunks: [
            line(#"{"id":"kelpie-sub","error":{"code":"invalid_request","message":"missing field pane_id"}}"#)
        ])
        let connection = HerdrEventConnection(transport: transport)

        do {
            _ = try await connection.subscribe()
            Issue.record("expected the rejected subscription to throw")
        } catch {
            // Expected; what matters is what happened to the socket.
        }
        // The caller never sees this connection, so if subscribe() does not
        // close it here nothing ever will.
        #expect(transport.closed)
    }

    @Test("A subscribe that fails before the handshake still closes the transport")
    func failedSendClosesTransport() async {
        let transport = FakeTransport()
        transport.finish()      // the peer is already gone, so the write fails
        let connection = HerdrEventConnection(transport: transport)

        do {
            _ = try await connection.subscribe()
            Issue.record("expected subscribe() to throw when the write fails")
        } catch {
            // Expected.
        }
        #expect(transport.closed)
    }

    @Test("A malformed event line does not tear down the stream")
    func malformedLineTolerated() async throws {
        let transport = FakeTransport(scriptedChunks: [line(ack)])
        let connection = HerdrEventConnection(transport: transport)
        let stream = try await connection.subscribe()

        transport.feed(line("not json at all"))
        transport.feed(line(updated))

        var iterator = stream.makeAsyncIterator()
        if case .paneUpserted(let record) = await iterator.next() {
            #expect(record.paneID == "w0:p1")
        } else {
            Issue.record("expected the stream to survive a malformed line")
        }
    }

    @Test("The stream finishes when herdr closes the connection")
    func streamFinishes() async throws {
        let transport = FakeTransport(scriptedChunks: [line(ack)])
        let connection = HerdrEventConnection(transport: transport)
        let stream = try await connection.subscribe()

        transport.finish()

        var seen = 0
        for await _ in stream { seen += 1 }
        #expect(seen == 0)
    }
}
