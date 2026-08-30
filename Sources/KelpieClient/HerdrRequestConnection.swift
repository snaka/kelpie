import Foundation
import KelpieCore

public enum RequestError: Error, Equatable {
    case herdr(code: String, message: String)
    case streamEnded
    case malformedResponse
    case timedOut
}

/// The short-lived request/response channel: `ping`, `session.snapshot` and
/// `agent.focus`.
///
/// This is separate from the event connection because `events.subscribe` keeps
/// its connection open streaming, so request/response calls cannot share it.
///
/// **One request per instance.** herdr closes a request connection once it has
/// answered — verified against 0.8.2, where a second write on the same socket
/// fails with EPIPE. Construct a fresh connection for every request.
public actor HerdrRequestConnection {
    /// herdr answers `ping`, `session.snapshot` and `agent.focus` in
    /// single-digit milliseconds over a local Unix socket, so ten seconds is
    /// far beyond any legitimate local latency. The bound exists because a
    /// herdr that keeps the socket open and never answers would otherwise park
    /// the caller forever: a snapshot request has no other way to fail, and the
    /// coordinator's periodic refresh would then open a fresh socket per signal
    /// with none of them ever closing.
    public static let defaultTimeout: Duration = .seconds(10)

    private let transport: any Transport
    private let timeout: Duration
    private var framer = NDJSONFramer()
    private var waiters: [String: CheckedContinuation<WireMessage, any Error>] = [:]
    private var readerTask: Task<Void, Never>?
    private var nextID = 0
    private var terminated = false
    /// Set before the transport is closed on expiry, so a waiter resolved by
    /// that close reports the timeout rather than the stream end it caused.
    private var timedOut = false

    public init(
        transport: any Transport,
        timeout: Duration = HerdrRequestConnection.defaultTimeout
    ) {
        self.transport = transport
        self.timeout = timeout
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
        // Without this, a call made after the connection has already ended
        // would register a waiter nothing will ever resolve — a permanent
        // hang. herdr closes the socket after one answer, so a second call on
        // the same instance lands here rather than on a live connection.
        guard !terminated else { throw terminationError }

        nextID += 1
        let id = "kelpie-\(nextID)"
        let line = try Wire.encodeRequest(id: id, method: method, params: params)
        let timeout = self.timeout

        let message: WireMessage = try await withThrowingTaskGroup(of: WireMessage.self) { group in
            group.addTask { try await self.awaitAnswer(id: id, line: line) }
            group.addTask {
                try await Task.sleep(for: timeout)
                // Closing the transport is what actually resolves the waiter:
                // it is only ever resumed by the reader, which is parked on the
                // socket, so cancelling the group alone would leave that
                // sibling running and this group would never return.
                await self.expire()
                throw RequestError.timedOut
            }
            guard let first = try await group.next() else { throw RequestError.timedOut }
            group.cancelAll()
            return first
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

    /// Registers the waiter and writes the request. Split out of `call` so the
    /// wait itself is one child of the timeout race.
    private func awaitAnswer(id: String, line: Data) async throws -> WireMessage {
        try await withCheckedThrowingContinuation { continuation in
            // Re-checked here because the connection can terminate between
            // `call`'s guard and this registration; a waiter added after
            // `failAll` has run is one nothing will ever resolve.
            guard !terminated else {
                continuation.resume(throwing: terminationError)
                return
            }
            waiters[id] = continuation
            Task {
                do {
                    try await transport.send(line)
                } catch {
                    self.fail(id: id, with: error)
                }
            }
        }
    }

    /// What an unresolvable wait should report.
    private var terminationError: RequestError {
        timedOut ? .timedOut : .streamEnded
    }

    private func expire() async {
        timedOut = true
        readerTask?.cancel()
        readerTask = nil
        await transport.close()
        failAll(with: RequestError.timedOut)
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
        terminated = true
        // Once the connection has expired, every unresolved wait is a
        // consequence of that expiry — including the stream end produced by
        // closing the transport — so they all report the timeout.
        let reported: any Error = timedOut ? RequestError.timedOut : error
        let pending = waiters
        waiters.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: reported)
        }
    }
}
