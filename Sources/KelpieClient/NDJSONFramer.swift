import Foundation

/// Reassembles newline-delimited JSON from arbitrary socket reads.
///
/// A read may deliver several messages, half a message, or a single byte in
/// the middle of a multibyte character. The framer works on bytes and never
/// decodes text, so a split inside a UTF-8 sequence is not a special case.
public struct NDJSONFramer: Sendable {
    private var buffer = Data()
    private static let newline = UInt8(ascii: "\n")

    public init() {}

    /// Bytes held back waiting for their terminating newline.
    public var pendingByteCount: Int { buffer.count }

    public mutating func push(_ chunk: Data) -> [Data] {
        guard !chunk.isEmpty else { return [] }
        buffer.append(chunk)

        var lines: [Data] = []
        while let index = buffer.firstIndex(of: Self.newline) {
            let line = buffer[buffer.startIndex..<index]
            buffer = buffer[buffer.index(after: index)...]
            // herdr never sends blank lines, but tolerating them costs nothing
            // and keeps a stray keepalive from becoming a decode error.
            if !line.isEmpty {
                lines.append(Data(line))
            }
        }
        // Re-base so the buffer's start index does not drift over a long run.
        buffer = Data(buffer)
        return lines
    }
}
