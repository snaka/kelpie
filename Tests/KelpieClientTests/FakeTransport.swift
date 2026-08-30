import Foundation
@testable import KelpieClient

/// Scriptable transport. Chunk boundaries are deliberately under the test's
/// control so connection logic can be exercised against split lines.
final class FakeTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [Data] = []
    private var continuation: AsyncThrowingStream<Data, any Error>.Continuation?
    private var pending: [Data]
    private(set) var connectCount = 0
    private(set) var closed = false

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

    func connect() async throws {
        withLock { connectCount += 1 }
    }

    func send(_ data: Data) async throws {
        withLock { sent.append(data) }
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
        let c = withLock { continuation }
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
