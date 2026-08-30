import Foundation

/// The bootstrap payload from `session.snapshot`, reduced to what Kelpie uses.
public struct Snapshot: Decodable, Equatable, Sendable {
    public let agents: [AgentRecord]
    public let workspaces: [WorkspaceRecord]
    public let protocolVersion: Int

    enum CodingKeys: String, CodingKey {
        case agents
        case workspaces
        case protocolVersion = "protocol"
    }

    public init(agents: [AgentRecord], workspaces: [WorkspaceRecord], protocolVersion: Int) {
        self.agents = agents
        self.workspaces = workspaces
        self.protocolVersion = protocolVersion
    }
}

/// herdr nests the snapshot one level down inside the response `result`.
public enum SnapshotEnvelope {
    private struct Envelope: Decodable {
        let snapshot: Snapshot
    }

    public static func decode(resultPayload: Data) throws -> Snapshot {
        try JSONDecoder().decode(Envelope.self, from: resultPayload).snapshot
    }
}
