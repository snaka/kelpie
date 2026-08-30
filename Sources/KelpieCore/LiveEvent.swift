import Foundation

/// A herdr subscription event reduced to the only thing Kelpie acts on: that
/// something changed, and roughly what kind of thing changed.
///
/// An event is a signal, never a source of truth. herdr replays history that
/// does not converge to the current state, and `revision` cannot order that
/// replay, so the coordinator answers any signal with a debounced
/// `session.snapshot` and discards the payload entirely.
///
/// Classifying on the event kind alone is therefore deliberate. Gating the
/// signal on decoding the pane payload — as this type used to — made every
/// herdr field rename a silent failure: the decode threw, the signal was
/// dropped, and Kelpie degraded to five-minute polling with nothing on screen
/// to say so. That is exactly the stale-menu-bar bug the snapshot-as-authority
/// redesign exists to prevent, re-entering through the decoder.
public enum LiveEvent: Equatable, Sendable {
    case paneChanged
    case workspaceChanged

    /// Returns `nil` for events Kelpie does not react to. Subscribing to a
    /// narrow set is not a guarantee: herdr may emit others on the same
    /// stream, and an unknown event must never break the connection.
    ///
    /// The kinds are the underscored forms herdr puts in the `event` field,
    /// which are not the dotted forms `events.subscribe` takes.
    public static func classify(eventKind: String) -> LiveEvent? {
        switch eventKind {
        case "pane_created", "pane_updated", "pane_closed":
            return .paneChanged
        case "workspace_created", "workspace_updated", "workspace_renamed", "workspace_closed":
            return .workspaceChanged
        default:
            return nil
        }
    }
}
