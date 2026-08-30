import Foundation

/// Where a state change came from. Notifications are only ever posted for
/// `.live`. `.bootstrap` describes state that already existed — it is the
/// first snapshot after connecting, so notifying for it would fire every
/// currently blocked agent at once every time Kelpie launches. Everything
/// after it is `.live`, because state is always current: a diff is only
/// non-empty when something genuinely changed, so a periodic or
/// event-triggered refresh is exactly as notifiable as any other change.
public enum ApplyPhase: Sendable, Equatable {
    case bootstrap
    case live
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
