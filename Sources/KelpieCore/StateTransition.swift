import Foundation

/// Where a state change came from. Notifications are only ever posted for
/// `.live`; bootstrap and resync would otherwise fire every currently blocked
/// agent at once, every time Kelpie or herdr restarts.
public enum ApplyPhase: Sendable, Equatable {
    case bootstrap
    case live
    case resync
}

/// One pane's status changing. `from` is `nil` when the pane is newly seen.
public struct StateTransition: Equatable, Sendable {
    public let paneID: String
    public let workspaceID: String
    public let from: AgentStatus?
    public let to: AgentStatus
    public let title: String?

    public init(paneID: String, workspaceID: String, from: AgentStatus?, to: AgentStatus, title: String?) {
        self.paneID = paneID
        self.workspaceID = workspaceID
        self.from = from
        self.to = to
        self.title = title
    }
}
