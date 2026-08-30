import Foundation

/// A herdr subscription event reduced to the four things Kelpie reacts to.
public enum LiveEvent: Equatable, Sendable {
    case paneUpserted(AgentRecord)
    case paneClosed(paneID: String)
    case workspaceUpserted(WorkspaceRecord)
    case workspaceClosed(workspaceID: String)

    private struct Envelope: Decodable {
        let event: String
        let data: EventData
    }

    private struct EventData: Decodable {
        let pane: AgentRecord?
        let workspace: WorkspaceRecord?
        let paneID: String?
        let workspaceID: String?
        let label: String?

        enum CodingKeys: String, CodingKey {
            case pane, workspace, label
            case paneID = "pane_id"
            case workspaceID = "workspace_id"
        }
    }

    /// Returns `nil` for events Kelpie does not model. Subscribing to a
    /// narrow set is not a guarantee: herdr may emit others on the same
    /// stream, and an unknown event must never break the connection.
    public static func decode(eventLine: Data) throws -> LiveEvent? {
        let envelope = try JSONDecoder().decode(Envelope.self, from: eventLine)
        switch envelope.event {
        case "pane_created", "pane_updated":
            return envelope.data.pane.map { .paneUpserted($0) }
        case "pane_closed":
            return envelope.data.paneID.map { .paneClosed(paneID: $0) }
        case "workspace_created", "workspace_updated":
            return envelope.data.workspace.map { .workspaceUpserted($0) }
        case "workspace_renamed":
            guard let id = envelope.data.workspaceID, let label = envelope.data.label else { return nil }
            return .workspaceUpserted(WorkspaceRecord(workspaceID: id, label: label))
        case "workspace_closed":
            return envelope.data.workspaceID.map { .workspaceClosed(workspaceID: $0) }
        default:
            return nil
        }
    }
}
