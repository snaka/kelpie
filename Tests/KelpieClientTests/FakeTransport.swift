import Foundation
@testable import KelpieClient

/// Scriptable transport. Chunk boundaries are deliberately under the test's
/// control so connection logic can be exercised against split lines.
final class FakeTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [Data] = []
    private var continuation: AsyncThrowingStream<Data, any Error>.Continuation?
    private var pending: [Data]
    private(set) var closed = false
    private var finished = false

    init(scriptedChunks: [Data] = []) {
        self.pending = scriptedChunks
    }

    /// `NSLock.lock()`/`unlock()` are marked unavailable from `async`
    /// contexts (they can suspend across an actor hop and invite priority
    /// inversion), so every locked section is routed through this
    /// synchronous helper instead of calling them inline from `async` methods.
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var sentLines: [Data] {
        withLock { sent }
    }

    func connect() async throws {}

    /// Mirrors a real socket: a write after the peer has gone fails. Without
    /// this, a test for "a request after termination must not hang" would hang
    /// on the very regression it exists to catch, because the request would be
    /// registered and then silently never answered.
    func send(_ data: Data) async throws {
        let isClosed = withLock { () -> Bool in
            let isClosed = closed || finished
            if !isClosed { sent.append(data) }
            return isClosed
        }
        if isClosed { throw TransportError.closed }
    }

    func chunks() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            let queued = withLock { () -> [Data] in
                self.continuation = continuation
                let queued = pending
                pending = []
                return queued
            }
            for chunk in queued { continuation.yield(chunk) }
        }
    }

    /// Push another chunk to a live stream, e.g. a response to a request the
    /// connection has just sent.
    func feed(_ chunk: Data) {
        let c = withLock { continuation }
        c?.yield(chunk)
    }

    func finish() {
        let c = withLock { () -> AsyncThrowingStream<Data, any Error>.Continuation? in
            finished = true
            return continuation
        }
        c?.finish()
    }

    func close() async {
        let c = withLock { () -> AsyncThrowingStream<Data, any Error>.Continuation? in
            closed = true
            return continuation
        }
        c?.finish()
    }
}
