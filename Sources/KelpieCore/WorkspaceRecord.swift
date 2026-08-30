import Foundation

/// Agent records carry only `workspace_id`; the human-readable name lives on
/// the workspace record, so Kelpie keeps a map of the two.
public struct WorkspaceRecord: Decodable, Equatable, Sendable {
    public let workspaceID: String
    public let label: String

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case label
    }

    public init(workspaceID: String, label: String) {
        self.workspaceID = workspaceID
        self.label = label
    }
}
