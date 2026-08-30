import Foundation

/// Semantic agent state as reported by herdr.
///
/// Decoding is deliberately lenient: an unrecognised value becomes `.unknown`
/// rather than throwing, so a newer herdr that adds a state does not stop
/// Kelpie from running.
public enum AgentStatus: String, Codable, Sendable, CaseIterable {
    case blocked
    case working
    case done
    case idle
    case unknown

    public init(wire: String) {
        self = AgentStatus(rawValue: wire) ?? .unknown
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(wire: raw)
    }

    /// Idle and unknown agents are listed in the popover but never tallied in
    /// the menu bar, which is reserved for states that want attention.
    public var countsInMenuBar: Bool {
        switch self {
        case .blocked, .working, .done: return true
        case .idle, .unknown: return false
        }
    }
}
