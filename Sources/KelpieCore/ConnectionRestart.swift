import Foundation

/// Why Kelpie is opening an event connection, and what that implies for the
/// snapshot that follows.
///
/// The two cases look identical from the socket's side — connect, subscribe,
/// snapshot — but they mean opposite things. A `.fresh` connection is a first
/// sighting: herdr was not there, or has only just come back, so the state it
/// reports already existed and notifying for it would fire every blocked agent
/// at once. A `.continuation` is the same session seen through a new socket:
/// Kelpie itself closed the previous one to change its subscriptions, herdr
/// never went away, and the couple of hundred milliseconds in between are an
/// implementation detail the user should not be able to detect.
///
/// Treating a continuation as a first sighting is what made a pane that turned
/// `blocked` inside that window notify never — and, because the reminder state
/// went with it, silenced the reminders for panes that were already blocked.
public enum ConnectionRestart: Sendable, Equatable {
    /// herdr was unreachable, or this is the first connection of the session.
    case fresh
    /// Kelpie closed the previous connection on purpose, to subscribe to a
    /// changed set of panes.
    case continuation

    /// How the first snapshot of the new connection is applied.
    public var phase: ApplyPhase {
        switch self {
        case .fresh: .bootstrap
        case .continuation: .live
        }
    }

    /// Whether `SessionState` — and with it the blocked reminders and the
    /// menu bar's blocked emphasis — survives into the new connection. It has
    /// to for a continuation: the transitions that notify are the difference
    /// between what Kelpie knew and what the new snapshot says, and a cleared
    /// state has no difference to offer.
    public var carriesStateForward: Bool {
        self == .continuation
    }
}
