import Testing
import Foundation
@testable import KelpieClient

@Suite("NDJSONFramer")
struct NDJSONFramerTests {

    private func text(_ lines: [Data]) -> [String] {
        lines.map { String(data: $0, encoding: .utf8)! }
    }

    @Test("A single complete line is emitted")
    func singleLine() {
        var framer = NDJSONFramer()
        #expect(text(framer.push(Data((#"{"a":1}"# + "\n").utf8))) == [#"{"a":1}"#])
    }

    @Test("Several lines in one chunk are all emitted in order")
    func multipleLinesInOneChunk() {
        var framer = NDJSONFramer()
        let chunk = Data(#"{"a":1}"#.utf8) + Data("\n".utf8)
            + Data(#"{"a":2}"#.utf8) + Data("\n".utf8)
            + Data(#"{"a":3}"#.utf8) + Data("\n".utf8)
        #expect(text(framer.push(chunk)) == [#"{"a":1}"#, #"{"a":2}"#, #"{"a":3}"#])
    }

    @Test("A line split across chunks is emitted only once complete")
    func lineSplitAcrossChunks() {
        var framer = NDJSONFramer()
        #expect(framer.push(Data(#"{"a":"#.utf8)).isEmpty)
        #expect(framer.push(Data(#"1}"#.utf8)).isEmpty)
        #expect(text(framer.push(Data("\n".utf8))) == [#"{"a":1}"#])
    }

    @Test("A trailing partial line is held for the next chunk")
    func trailingPartialHeld() {
        var framer = NDJSONFramer()
        let emitted = framer.push(Data((#"{"a":1}"# + "\n" + #"{"b":"#).utf8))
        #expect(text(emitted) == [#"{"a":1}"#])
        #expect(framer.pendingByteCount > 0)
        #expect(text(framer.push(Data((#"2}"# + "\n").utf8))) == [#"{"b":2}"#])
    }

    @Test("Blank lines are skipped rather than emitted as empty messages")
    func blankLinesSkipped() {
        var framer = NDJSONFramer()
        let chunk = Data("\n".utf8) + Data(#"{"a":1}"#.utf8) + Data("\n\n".utf8)
        #expect(text(framer.push(chunk)) == [#"{"a":1}"#])
    }

    @Test("A large line is reassembled correctly across many chunks")
    func largeLine() {
        var framer = NDJSONFramer()
        let payload = #"{"big":""# + String(repeating: "x", count: 200_000) + #""}"#
        var emitted: [Data] = []
        var bytes = Array(payload.utf8) + Array("\n".utf8)
        while !bytes.isEmpty {
            let take = min(4096, bytes.count)
            emitted += framer.push(Data(bytes.prefix(take)))
            bytes.removeFirst(take)
        }
        #expect(text(emitted) == [payload])
    }

    @Test("Multibyte UTF-8 split across a chunk boundary survives")
    func multibyteSplit() {
        var framer = NDJSONFramer()
        let full = Array(#"{"t":"教材の準備"}"#.utf8)
        // Cut inside the first Japanese character's byte sequence.
        let cut = full.count / 2
        #expect(framer.push(Data(full[..<cut])).isEmpty)
        #expect(text(framer.push(Data(full[cut...]) + Data("\n".utf8))) == [#"{"t":"教材の準備"}"#])
    }

    @Test("An empty chunk emits nothing and is harmless")
    func emptyChunk() {
        var framer = NDJSONFramer()
        #expect(framer.push(Data()).isEmpty)
    }
}
