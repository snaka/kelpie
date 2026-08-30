import Foundation

/// POSIX `AF_UNIX` stream socket.
///
/// Network.framework has no first-class Unix-domain client, and herdr's socket
/// is a plain stream, so the POSIX API is both the simplest and the most
/// predictable choice here. Blocking reads run on a dedicated queue.
public actor UnixSocketTransport: Transport {
    private let path: String
    private var descriptor: Int32 = -1
    private let readQueue = DispatchQueue(label: "dev.snaka.kelpie.socket-read")

    public init(path: String) {
        self.path = path
    }

    public static var defaultHerdrSocketPath: String {
        // herdr resolves this the same way when no HERDR_* override is set,
        // which is the condition a GUI launch runs under.
        (NSHomeDirectory() as NSString).appendingPathComponent(".config/herdr/herdr.sock")
    }

    public func connect() async throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TransportError.connectFailed(errno: errno) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        // sun_path is a fixed C array; leave room for the NUL terminator.
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(fd)
            throw TransportError.connectFailed(errno: ENAMETOOLONG)
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { destination in
                for (offset, byte) in pathBytes.enumerated() {
                    destination[offset] = CChar(bitPattern: byte)
                }
                destination[pathBytes.count] = 0
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                Darwin.connect(fd, generic, size)
            }
        }
        guard result == 0 else {
            let failure = errno
            Darwin.close(fd)
            throw TransportError.connectFailed(errno: failure)
        }
        descriptor = fd
    }

    public func send(_ data: Data) async throws {
        guard descriptor >= 0 else { throw TransportError.notConnected }
        let fd = descriptor
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written <= 0 {
                    if errno == EINTR { continue }
                    throw TransportError.sendFailed(errno: errno)
                }
                offset += written
            }
        }
    }

    public nonisolated func chunks() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            // An abandoned stream must take the socket down with it. Between
            // chunks() and the point where a connection is handed to its owner
            // there are throwing steps — the subscribe handshake is one — and
            // if the stream is simply dropped there, nothing else holds a
            // reference to this transport: the descriptor stays open and the
            // read queue stays parked in a blocking read() forever.
            continuation.onTermination = { _ in
                Task { await self.close() }
            }
            Task {
                let fd = await self.currentDescriptor
                guard fd >= 0 else {
                    continuation.finish(throwing: TransportError.notConnected)
                    return
                }
                self.readQueue.async {
                    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                    while true {
                        let count = buffer.withUnsafeMutableBytes {
                            Darwin.read(fd, $0.baseAddress, $0.count)
                        }
                        if count > 0 {
                            continuation.yield(Data(buffer[0..<count]))
                        } else if count == 0 {
                            continuation.finish()   // peer closed
                            return
                        } else if errno == EINTR {
                            continue
                        } else {
                            continuation.finish(throwing: TransportError.closed)
                            return
                        }
                    }
                }
            }
        }
    }

    private var currentDescriptor: Int32 { descriptor }

    public func close() {
        guard descriptor >= 0 else { return }
        // shutdown() first. A reader may be parked in a blocking read() on the
        // read queue, and closing the descriptor alone does not reliably wake
        // it: on some platforms the read never returns, and the freed
        // descriptor number can be reused by an unrelated socket while that
        // stale read is still in flight. Kelpie reconnects on a backoff loop
        // for as long as herdr is down, so a reader that never wakes leaks a
        // thread on every cycle.
        shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
        descriptor = -1
    }

    deinit {
        // Safety net for an instance dropped without close() — for example a
        // reconnect that replaces the transport on an error path. Actor deinit
        // is nonisolated but no concurrent access is possible at this point.
        // shutdown() first for the same reason close() does it: a reader parked
        // in a blocking read() is not reliably woken by close() alone, and a
        // deinit is exactly the case where nobody is left to notice.
        if descriptor >= 0 {
            shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
    }
}
