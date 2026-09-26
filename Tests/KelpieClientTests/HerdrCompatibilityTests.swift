import Testing
import Foundation
@testable import KelpieClient

@Suite("HerdrCompatibility")
struct HerdrCompatibilityTests {

    @Test("A request herdr could not parse means the wire formats disagree")
    func invalidRequest() {
        #expect(HerdrCompatibility.isIncompatibility(
            RequestError.herdr(code: "invalid_request", message: "unknown variant `session.snapshot`")))
    }

    @Test("An answer Kelpie could not decode means the wire formats disagree")
    func malformedResponse() {
        #expect(HerdrCompatibility.isIncompatibility(RequestError.malformedResponse))
    }

    @Test("A subscription herdr could not parse means the wire formats disagree")
    func invalidSubscription() {
        #expect(HerdrCompatibility.isIncompatibility(
            EventConnectionError.subscriptionRejected(code: "invalid_request", message: "missing field `pane_id`")))
    }

    @Test("A planned pane closing before the subscribe lands is an ordinary race")
    func vanishedPane() {
        #expect(!HerdrCompatibility.isIncompatibility(
            EventConnectionError.subscriptionRejected(code: "pane_not_found", message: "pane not found")))
        #expect(!HerdrCompatibility.isIncompatibility(
            RequestError.herdr(code: "pane_not_found", message: "pane not found")))
    }

    @Test("herdr going away is not an incompatibility")
    func connectionLoss() {
        #expect(!HerdrCompatibility.isIncompatibility(RequestError.streamEnded))
        #expect(!HerdrCompatibility.isIncompatibility(RequestError.timedOut))
        #expect(!HerdrCompatibility.isIncompatibility(EventConnectionError.streamEnded))
        #expect(!HerdrCompatibility.isIncompatibility(EventConnectionError.handshakeTimedOut))
        #expect(!HerdrCompatibility.isIncompatibility(POSIXError(.ECONNREFUSED)))
    }
}
