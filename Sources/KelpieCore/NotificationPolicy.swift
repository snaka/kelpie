import Foundation

/// Decides which state changes deserve a macOS notification.
///
/// Kept as a pure function so the rules that actually matter — that a fresh
/// launch is silent, that a reconnect is silent, and that an agent sitting in
/// `blocked` does not nag — are testable without a notification centre.
public enum NotificationPolicy {
    public static func notifiable(_ transitions: [StateTransition], phase: ApplyPhase) -> [StateTransition] {
        // Bootstrap and resync describe state that already existed. Notifying
        // for them would fire every blocked agent at once on every launch and
        // every reconnect.
        guard phase == .live else { return [] }
        return transitions.filter { $0.to == .blocked && $0.from != .blocked }
    }
}
