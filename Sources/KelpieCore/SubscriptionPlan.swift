import Foundation

/// One entry of an `events.subscribe` request: a kind, and for the per-pane
/// kinds, the pane it applies to. Pure data — the client layer owns the wire
/// encoding.
public struct SubscriptionRequest: Equatable, Sendable {
    public let type: String
    public let paneID: String?

    public init(type: String, paneID: String?) {
        self.type = type
        self.paneID = paneID
    }
}

/// Decides what Kelpie subscribes to for a given set of panes.
///
/// herdr emits agent status changes only as `pane.agent_status_changed`,
/// which can only be subscribed per pane — the global `pane.updated` fires on
/// stripped-title changes, renames, and metadata expiry, but never on a status
/// change (verified against herdr 0.8.2's source, `emit_pane_state_update`).
/// So the plan pairs the global lifecycle kinds, which tell Kelpie when the
/// pane set itself changes, with one status subscription per known pane.
public enum SubscriptionPlan {
    /// The kind that requires a `pane_id`.
    public static let agentStatusType = "pane.agent_status_changed"

    /// Globally subscribable kinds. `pane.updated` stays for the changes it
    /// does fire on; `pane.created` / `pane.closed` are what trigger a
    /// subscription rebuild via `needsRebuild`.
    public static let globalTypes = [
        "pane.updated",
        "pane.created",
        "pane.closed",
        "workspace.created",
        "workspace.updated",
        "workspace.renamed",
        "workspace.closed",
    ]

    public static func subscriptions(paneIDs: some Sequence<String>) -> [SubscriptionRequest] {
        globalTypes.map { SubscriptionRequest(type: $0, paneID: nil) }
            + Set(paneIDs).sorted().map { SubscriptionRequest(type: agentStatusType, paneID: $0) }
    }

    /// A subscription connection carries a fixed list, so a change to the pane
    /// set means tearing the connection down and building a new one.
    public static func needsRebuild(subscribed: Set<String>, current: Set<String>) -> Bool {
        subscribed != current
    }
}
