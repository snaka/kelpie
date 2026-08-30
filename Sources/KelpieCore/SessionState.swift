import Foundation

/// The authoritative local view of what herdr is running.
///
/// This type is a pure reducer: it holds no connection, performs no I/O, and
/// every behaviour Kelpie depends on can be exercised without herdr running.
public struct SessionState: Equatable, Sendable {
    public private(set) var agents: [String: AgentRecord] = [:]
    public private(set) var workspaceLabels: [String: String] = [:]

    public init() {}

    /// Installs a snapshot wholesale, replacing everything. This is the only
    /// way state changes: an event means something changed, and only a fresh
    /// snapshot says what it changed to. See `AppCoordinator.refreshFromSnapshot`.
    public mutating func replace(with snapshot: Snapshot) -> [StateTransition] {
        let previous = agents
        agents = Dictionary(uniqueKeysWithValues: snapshot.agents.map { ($0.paneID, $0) })
        workspaceLabels = Dictionary(
            uniqueKeysWithValues: snapshot.workspaces.map { ($0.workspaceID, $0.label) }
        )
        return snapshot.agents.compactMap { record in
            // Only panes with a detected agent, matching `agentPanes`. herdr
            // reports plain shells too, and one of those reporting `blocked`
            // would otherwise post a notification for a row that appears
            // nowhere in the counts or the popover.
            guard record.isAgentPane else { return nil }
            return transition(from: previous[record.paneID], to: record)
        }
    }

    /// Falls back to the raw id so a row is never blank while a rename or a
    /// missing workspace record is in flight.
    public func label(for workspaceID: String) -> String {
        workspaceLabels[workspaceID] ?? workspaceID
    }

    /// Only panes where herdr has detected an agent.
    public var agentPanes: [AgentRecord] {
        agents.values.filter(\.isAgentPane)
    }

    private func transition(from previous: AgentRecord?, to record: AgentRecord) -> StateTransition? {
        guard previous?.status != record.status else { return nil }
        return StateTransition(
            paneID: record.paneID,
            workspaceID: record.workspaceID,
            from: previous?.status,
            to: record.status,
            title: record.title
        )
    }
}
