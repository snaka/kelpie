import Foundation

public enum TransportError: Error, Equatable {
    case connectFailed(errno: Int32)
    case sendFailed(errno: Int32)
    case notConnected
    case closed
}

/// A bidirectional byte stream. Abstracted so the connection logic can be
/// tested against scripted bytes instead of a live herdr server.
public protocol Transport: Sendable {
    func connect() async throws
    func send(_ data: Data) async throws
    /// Finishes when the peer closes the connection.
    ///
    /// Assumes a single reader: calling this more than once on the same
    /// transport would start two concurrent reads on one underlying
    /// descriptor.
    func chunks() -> AsyncThrowingStream<Data, any Error>
    func close() async
}
