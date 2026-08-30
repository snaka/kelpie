import Foundation
import KelpieCore

public enum RequestError: Error, Equatable {
    case herdr(code: String, message: String)
    case streamEnded
    case malformedResponse
}

/// The short-lived request/response channel: `ping`, `session.snapshot` and
/// `agent.focus`.
///
/// This is separate from the event connection because `events.subscribe` keeps
/// its connection open streaming, so request/response calls cannot share it.
public actor HerdrRequestConnection {
    private let transport: any Transport
    private var framer = NDJSONFramer()
    private var waiters: [String: CheckedContinuation<WireMessage, any Error>] = [:]
    private var readerTask: Task<Void, Never>?
    private var nextID = 0

    public init(transport: any Transport) {
        self.transport = transport
    }

    public func open() async throws {
        try await transport.connect()
        let stream = transport.chunks()
        readerTask = Task { [weak self] in
            do {
                for try await chunk in stream {
                    await self?.ingest(chunk)
                }
                await self?.failAll(with: RequestError.streamEnded)
            } catch {
                await self?.failAll(with: error)
            }
        }
    }

    public func ping() async throws -> PongPayload {
        let payload = try await call(method: "ping", params: EmptyParams())
        guard let pong = try? JSONDecoder().decode(PongPayload.self, from: payload) else {
            throw RequestError.malformedResponse
        }
        return pong
    }

    public func snapshot() async throws -> Snapshot {
        let payload = try await call(method: "session.snapshot", params: EmptyParams())
        guard let snapshot = try? SnapshotEnvelope.decode(resultPayload: payload) else {
            throw RequestError.malformedResponse
        }
        return snapshot
    }

    public func focus(paneID: String) async throws {
        _ = try await call(method: "agent.focus", params: AgentTargetParams(target: paneID))
    }

    public func close() async {
        readerTask?.cancel()
        readerTask = nil
        await transport.close()
        failAll(with: RequestError.streamEnded)
    }

    private func call(method: String, params: some Encodable) async throws -> Data {
        nextID += 1
        let id = "kelpie-\(nextID)"
        let line = try Wire.encodeRequest(id: id, method: method, params: params)

        let message: WireMessage = try await withCheckedThrowingContinuation { continuation in
            waiters[id] = continuation
            Task {
                do {
                    try await transport.send(line)
                } catch {
                    self.fail(id: id, with: error)
                }
            }
        }

        switch message {
        case .result(_, let payload):
            return payload
        case .failure(_, let code, let text):
            throw RequestError.herdr(code: code, message: text)
        case .event:
            throw RequestError.malformedResponse
        }
    }

    private func ingest(_ chunk: Data) {
        for line in framer.push(chunk) {
            // A malformed or unknown line must never take the connection down;
            // a request that never gets an answer fails when the stream ends.
            guard let message = try? Wire.decode(line: line) else { continue }
            switch message {
            case .result(let id, _), .failure(let id, _, _):
                if let waiter = waiters.removeValue(forKey: id) {
                    waiter.resume(returning: message)
                }
            case .event:
                continue    // events belong to the other connection
            }
        }
    }

    private func fail(id: String, with error: any Error) {
        waiters.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func failAll(with error: any Error) {
        let pending = waiters
        waiters.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
    }
}
