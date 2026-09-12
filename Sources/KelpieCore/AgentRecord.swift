import Foundation

/// One pane as Kelpie cares about it.
///
/// This decodes the `agents[]` entries of `session.snapshot`, which is the only
/// authority on agent state; event payloads are never decoded. Unused fields
/// are ignored, and every field named here is one herdr can break by renaming,
/// so the list is kept to what is actually read. `revision` used to be here and
/// is deliberately gone: herdr increments it only when a stripped terminal
/// title changes, so it can order nothing, and nothing consumed it.
public struct AgentRecord: Decodable, Equatable, Sendable {
    public let paneID: String
    public let workspaceID: String
    public let status: AgentStatus
    /// `terminal_title_stripped`: the title with the agent's own leading
    /// activity or spinner glyph removed.
    public let title: String?
    /// Absent until herdr detects an agent in the pane.
    public let agentKind: String?

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
        case workspaceID = "workspace_id"
        case status = "agent_status"
        case title = "terminal_title_stripped"
        case agentKind = "agent"
    }

    public init(
        paneID: String,
        workspaceID: String,
        status: AgentStatus,
        title: String?,
        agentKind: String?
    ) {
        self.paneID = paneID
        self.workspaceID = workspaceID
        self.status = status
        self.title = title
        self.agentKind = agentKind
    }

    /// Kelpie only shows panes where herdr has detected an agent.
    ///
    /// Measured against 0.8.2, `session.snapshot`'s `agents[]` already
    /// excludes plain shells — a pane split off with no agent in it never
    /// appears — so this filter is currently redundant. It is kept because
    /// `agent` is declared optional by herdr's own schema, which is the only
    /// promise Kelpie has; a pane arriving with a null `agent` would otherwise
    /// be tallied and, if it reported `blocked`, notified for.
    public var isAgentPane: Bool { agentKind != nil }
}
