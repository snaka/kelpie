import Foundation

/// One pane as Kelpie cares about it.
///
/// The same shape decodes both the `agents[]` entries of `session.snapshot`
/// and the `pane` payload of `pane_created` / `pane_updated` events, because
/// herdr uses the same field names in both. Unused fields are ignored.
public struct AgentRecord: Decodable, Equatable, Sendable {
    public let paneID: String
    public let workspaceID: String
    public let revision: UInt64
    public let status: AgentStatus
    /// `terminal_title_stripped`: the title with the agent's own leading
    /// activity or spinner glyph removed.
    public let title: String?
    /// Absent until herdr detects an agent in the pane.
    public let agentKind: String?

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
        case workspaceID = "workspace_id"
        case revision
        case status = "agent_status"
        case title = "terminal_title_stripped"
        case agentKind = "agent"
    }

    public init(
        paneID: String,
        workspaceID: String,
        revision: UInt64,
        status: AgentStatus,
        title: String?,
        agentKind: String?
    ) {
        self.paneID = paneID
        self.workspaceID = workspaceID
        self.revision = revision
        self.status = status
        self.title = title
        self.agentKind = agentKind
    }

    /// Panes running a plain shell are reported too; Kelpie only shows panes
    /// where herdr has detected an agent.
    public var isAgentPane: Bool { agentKind != nil }
}
