import Testing
import Foundation
@testable import KelpieCore

@Suite("ConnectionRestart")
struct ConnectionRestartTests {

    @Test("A fresh connection bootstraps, so a launch with agents already blocked is silent")
    func freshBootstraps() {
        #expect(ConnectionRestart.fresh.phase == .bootstrap)
    }

    @Test("A continuation is live, so a pane that blocked during the rebuild still notifies")
    func continuationIsLive() {
        #expect(ConnectionRestart.continuation.phase == .live)
    }

    @Test("A fresh connection starts from nothing")
    func freshDiscardsState() {
        #expect(ConnectionRestart.fresh.carriesStateForward == false)
    }

    @Test("A continuation keeps what the previous connection knew")
    func continuationKeepsState() {
        #expect(ConnectionRestart.continuation.carriesStateForward)
    }
}
