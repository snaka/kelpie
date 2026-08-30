import Foundation
import KelpieCore

public enum EventConnectionError: Error, Equatable {
    case subscriptionRejected(code: String, message: String)
    case streamEnded
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

    private let transport: any Transport
    /// The framer lives inside the reader task, not here, because exactly one
    /// task ever touches it.
    private var readerTask: Task<Void, Never>?

    public init(transport: any Transport) {
        self.transport = transport
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
        do {
            return try await performSubscribe()
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
                            case .event(_, let raw):
                                // `try?` flattens the throwing `LiveEvent?`
                                // return into a single optional: nil covers
                                // both a decode failure and an event Kelpie
                                // does not model.
                                if let event = try? LiveEvent.decode(eventLine: raw) {
                                    continuation.yield(event)
                                }
                            }
                        }
                    }
                } catch {
                    // Losing the stream is reported by finishing it; the
                    // coordinator reconnects.
                }

                if !acknowledged {
                    handshake.resume(throwing: EventConnectionError.streamEnded)
                }
                continuation.finish()
            }
        }
    }

    public func close() async {
        readerTask?.cancel()
        readerTask = nil
        await transport.close()
    }
}
