import Testing
import Foundation
@testable import KelpieCore

@Suite("AgentStatus")
struct AgentStatusTests {

    @Test("Known wire values map to their case")
    func knownValues() {
        #expect(AgentStatus(wire: "idle") == .idle)
        #expect(AgentStatus(wire: "working") == .working)
        #expect(AgentStatus(wire: "blocked") == .blocked)
        #expect(AgentStatus(wire: "done") == .done)
        #expect(AgentStatus(wire: "unknown") == .unknown)
    }

    @Test("Unrecognised wire values decode to unknown instead of failing")
    func unrecognisedValue() {
        #expect(AgentStatus(wire: "compacting") == .unknown)
        #expect(AgentStatus(wire: "") == .unknown)
    }

    @Test("Decoding an unrecognised value does not throw")
    func lenientDecoding() throws {
        let json = Data(#"{"agent_status":"some_future_state"}"#.utf8)
        struct Holder: Decodable {
            let agentStatus: AgentStatus
            enum CodingKeys: String, CodingKey { case agentStatus = "agent_status" }
        }
        let holder = try JSONDecoder().decode(Holder.self, from: json)
        #expect(holder.agentStatus == .unknown)
    }
}
