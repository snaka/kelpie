import Foundation

/// The authoritative local view of what herdr is running.
///
/// This type is a pure reducer: it holds no connection, performs no I/O, and
/// every behaviour Kelpie depends on can be exercised without herdr running.
public struct SessionState: Equatable, Sendable {
    public private(set) var agents: [String: AgentRecord] = [:]
    public private(set) var workspaceLabels: [String: String] = [:]

    public init() {}

    /// Installs a snapshot wholesale, replacing everything. Used for the
    /// initial bootstrap and for the periodic resync.
    public mutating func replace(with snapshot: Snapshot) -> [StateTransition] {
        let previous = agents
        agents = Dictionary(uniqueKeysWithValues: snapshot.agents.map { ($0.paneID, $0) })
        workspaceLabels = Dictionary(
            uniqueKeysWithValues: snapshot.workspaces.map { ($0.workspaceID, $0.label) }
        )
        return snapshot.agents.compactMap { record in
            transition(from: previous[record.paneID], to: record)
        }
    }

    public mutating func apply(_ event: LiveEvent) -> [StateTransition] {
        switch event {
        case .paneUpserted(let record):
            // herdr replays historical events when a subscription opens, so a
            // revision that has not advanced carries nothing new.
            if let existing = agents[record.paneID], existing.revision >= record.revision {
                return []
            }
            let previous = agents[record.paneID]
            agents[record.paneID] = record
            return [transition(from: previous, to: record)].compactMap { $0 }

        case .paneClosed(let paneID):
            agents[paneID] = nil
            return []

        case .workspaceUpserted(let workspace):
            workspaceLabels[workspace.workspaceID] = workspace.label
            return []

        case .workspaceClosed(let workspaceID):
            workspaceLabels[workspaceID] = nil
            return []
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
