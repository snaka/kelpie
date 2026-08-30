import Foundation

/// One popover row.
public struct AgentRow: Equatable, Sendable {
    public let paneID: String
    public let workspaceLabel: String
    public let title: String?

    public init(paneID: String, workspaceLabel: String, title: String?) {
        self.paneID = paneID
        self.workspaceLabel = workspaceLabel
        self.title = title
    }
}

/// One popover section.
public struct AgentGroup: Equatable, Sendable {
    public let status: AgentStatus
    public let rows: [AgentRow]

    public init(status: AgentStatus, rows: [AgentRow]) {
        self.status = status
        self.rows = rows
    }
}

public enum AgentGrouping {
    /// Sections are always in attention order, and an empty section is omitted
    /// along with its heading.
    private static let order: [AgentStatus] = [.blocked, .working, .done, .idle, .unknown]

    public static func groups(state: SessionState) -> [AgentGroup] {
        let panes = state.agentPanes
        return order.compactMap { status in
            let rows = panes
                .filter { $0.status == status }
                .map { AgentRow(paneID: $0.paneID,
                                workspaceLabel: state.label(for: $0.workspaceID),
                                title: $0.title) }
                // Pane id is the tiebreaker so ordering is stable when two
                // panes share a workspace.
                .sorted { ($0.workspaceLabel, $0.paneID) < ($1.workspaceLabel, $1.paneID) }
            return rows.isEmpty ? nil : AgentGroup(status: status, rows: rows)
        }
    }
}
