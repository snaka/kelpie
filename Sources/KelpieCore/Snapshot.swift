import Foundation

/// The bootstrap payload from `session.snapshot`, reduced to what Kelpie uses.
///
/// herdr's numbered `protocol` is deliberately not read: it versions the
/// binary protocol between herdr's own client and server, not the JSON API,
/// and herdr bumps it for changes Kelpie never sees.
public struct Snapshot: Decodable, Equatable, Sendable {
    public let agents: [AgentRecord]
    public let workspaces: [WorkspaceRecord]

    public init(agents: [AgentRecord], workspaces: [WorkspaceRecord]) {
        self.agents = agents
        self.workspaces = workspaces
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
