import Foundation
import KelpieCore

public enum EventConnectionError: Error, Equatable {
    case subscriptionRejected(code: String, message: String)
    case streamEnded
    case handshakeTimedOut
}

/// The long-lived subscription channel.
///
/// `pane.agent_status_changed` is deliberately absent: herdr requires a
/// `pane_id` for it and rejects a global subscription, and `pane.updated`
/// carries the same status information for every pane.
public actor HerdrEventConnection {
    public static let subscriptionTypes = [
        "pane.updated",
        "pane.created",
        "pane.closed",
        "workspace.created",
        "workspace.updated",
        "workspace.renamed",
        "workspace.closed",
    ]

    /// herdr acknowledges `events.subscribe` in single-digit milliseconds over
    /// a local Unix socket, so ten seconds is far beyond any legitimate local
    /// latency while still recovering quickly. The bound exists because an
    /// unbounded handshake is the one failure Kelpie cannot escape: a herdr
    /// that holds the socket open and answers nothing parks `connectOnce()`
    /// forever, so the reconnect backoff is never reached and the menu bar
    /// reads "Connecting to herdr…" for the rest of the session.
    public static let defaultHandshakeTimeout: Duration = .seconds(10)

    private let transport: any Transport
    private let handshakeTimeout: Duration
    /// The framer lives inside the reader task, not here, because exactly one
    /// task ever touches it.
    private var readerTask: Task<Void, Never>?
    /// Set before the transport is closed on expiry, so the reader reports the
    /// timeout rather than the stream end that the close itself causes.
    private var handshakeExpired = false

    public init(
        transport: any Transport,
        handshakeTimeout: Duration = HerdrEventConnection.defaultHandshakeTimeout
    ) {
        self.transport = transport
        self.handshakeTimeout = handshakeTimeout
    }

    /// Connects, subscribes, waits for the acknowledgement, and then returns a
    /// stream of the events Kelpie models.
    ///
    /// One task owns the byte iterator for the whole lifetime of the
    /// connection. Handing an iterator between the handshake and a second
    /// streaming task would not survive strict concurrency checking, so the
    /// handshake result is delivered through a continuation that the same
    /// reader resumes.
    public func subscribe() async throws -> AsyncStream<LiveEvent> {
        let timeout = handshakeTimeout
        do {
            return try await withThrowingTaskGroup(of: AsyncStream<LiveEvent>.self) { group in
                group.addTask { try await self.performSubscribe() }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    // Closing the transport is what actually unblocks the
                    // handshake: its continuation is only ever resumed from the
                    // reader task, which is parked on the socket, so cancelling
                    // the group alone would leave that sibling task running
                    // forever and this group would never return.
                    await self.expireHandshake()
                    throw EventConnectionError.handshakeTimedOut
                }
                guard let stream = try await group.next() else {
                    throw EventConnectionError.handshakeTimedOut
                }
                group.cancelAll()
                return stream
            }
        } catch {
            // Every throwing step below `connect()` leaves an open descriptor
            // and a reader parked in a blocking read(). The coordinator adopts
            // this connection only once `subscribe()` has returned, so on a
            // throw nothing else holds a reference that could close it — and a
            // subscription herdr keeps rejecting is retried forever on a
            // backoff, leaking one descriptor and one thread per cycle.
            await close()
            throw error
        }
    }

    private func performSubscribe() async throws -> AsyncStream<LiveEvent> {
        try await transport.connect()
        let chunks = transport.chunks()
        try await transport.send(
            Wire.encodeRequest(id: "kelpie-sub", method: "events.subscribe",
                               params: SubscribeParams(types: Self.subscriptionTypes))
        )

        let (stream, continuation) = AsyncStream<LiveEvent>.makeStream()

        return try await withCheckedThrowingContinuation { handshake in
            readerTask = Task {
                var framer = NDJSONFramer()
                var acknowledged = false

                do {
                    for try await chunk in chunks {
                        for line in framer.push(chunk) {
                            // A line Kelpie cannot parse is skipped, never fatal.
                            guard let message = try? Wire.decode(line: line) else { continue }
                            switch message {
                            case .result:
                                if !acknowledged {
                                    acknowledged = true
                                    // AsyncStream buffers, so events decoded
                                    // before the caller starts iterating are
                                    // held rather than dropped.
                                    handshake.resume(returning: stream)
                                }
                            case .failure(_, let code, let text):
                                if !acknowledged {
                                    acknowledged = true
                                    handshake.resume(throwing: EventConnectionError
                                        .subscriptionRejected(code: code, message: text))
                                    continuation.finish()
                                    return
                                }
                            case .event(let kind, _):
                                // Classified by kind alone. The payload is
                                // never read, so a renamed pane field cannot
                                // silently stop the refreshes — the caller only
                                // needs to know that something changed, and
                                // answers with a fresh snapshot.
                                if let signal = LiveEvent.classify(eventKind: kind) {
                                    continuation.yield(signal)
                                }
                            }
                        }
                    }
                } catch {
                    // Losing the stream is reported by finishing it; the
                    // coordinator reconnects.
                }

                if !acknowledged {
                    handshake.resume(throwing: self.handshakeExpired
                        ? EventConnectionError.handshakeTimedOut
                        : EventConnectionError.streamEnded)
                }
                continuation.finish()
            }
        }
    }

    /// Flags the expiry before closing, so whichever of the two racing tasks
    /// reports first reports the same thing: the timeout, not the stream end
    /// the close produces a moment later.
    private func expireHandshake() async {
        handshakeExpired = true
        await transport.close()
    }

    public func close() async {
        readerTask?.cancel()
        readerTask = nil
        await transport.close()
    }
}
