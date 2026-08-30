import Foundation

/// The menu bar tallies. Only panes with a detected agent are counted.
public struct StatusCounts: Equatable, Sendable {
    public let blocked: Int
    public let working: Int
    public let done: Int
    public let idle: Int
    public let unknown: Int

    public init(blocked: Int, working: Int, done: Int, idle: Int, unknown: Int) {
        self.blocked = blocked
        self.working = working
        self.done = done
        self.idle = idle
        self.unknown = unknown
    }

    public init(state: SessionState) {
        var tally: [AgentStatus: Int] = [:]
        for pane in state.agentPanes {
            tally[pane.status, default: 0] += 1
        }
        self.init(
            blocked: tally[.blocked] ?? 0,
            working: tally[.working] ?? 0,
            done: tally[.done] ?? 0,
            idle: tally[.idle] ?? 0,
            unknown: tally[.unknown] ?? 0
        )
    }

    /// Nothing wants attention, so the menu bar shows a single muted glyph.
    public var isResting: Bool {
        blocked == 0 && working == 0 && done == 0
    }
}
