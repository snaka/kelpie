import Foundation

/// Re-notifies for a pane that has been left sitting in `blocked`.
///
/// `NotificationPolicy` fires exactly once, on the transition into `blocked`,
/// and that once-only rule is what keeps notifications worth reading. This is
/// the deliberate exception to it: a pane still waiting on you twenty minutes
/// later was never dealt with, so the single banner it got did not do its job.
/// It lives in its own type rather than as a relaxation of
/// `NotificationPolicy` so the once-only rule stays stated — and tested — in
/// one place.
///
/// The interval widens (one minute, then five, then fifteen and fifteen
/// thereafter) so a pane you are already walking over to does not nag, while
/// one you have genuinely forgotten keeps a slow heartbeat going. Only leaving
/// `blocked` stops it: activating the notification just brings the terminal
/// forward, and going to look is not the same as answering.
///
/// Pure and clock-injected like `RefreshCoalescer`, so every interval here is
/// exercised by `swift test` without waiting a real minute for any of them.
public struct BlockedReminder: Sendable {
    private struct Pending {
        var nextFireAt: ContinuousClock.Instant
        var fired: Int
    }

    private var pending: [String: Pending] = [:]
    private let schedule: [Duration]

    /// The last interval repeats for as long as the pane stays blocked.
    public init(schedule: [Duration] = [.seconds(60), .seconds(300), .seconds(900)]) {
        precondition(!schedule.isEmpty, "a reminder schedule needs at least one interval")
        self.schedule = schedule
    }

    /// Starts the clock for panes that just entered `blocked`.
    ///
    /// Pass what `NotificationPolicy.notifiable` returned. Feeding it the
    /// already-filtered transitions is what keeps bootstrap silent here too:
    /// panes that were blocked before Kelpie launched are never armed, so they
    /// do not start reminding a minute after every launch — which would undo
    /// the reason bootstrap is silent in the first place.
    ///
    /// Arming a pane that is already pending restarts its schedule, which is
    /// what a pane that went `blocked` → `working` → `blocked` should get.
    public mutating func arm(_ transitions: [StateTransition], at now: ContinuousClock.Instant) {
        for transition in transitions {
            pending[transition.paneID] = Pending(nextFireAt: now.advanced(by: schedule[0]), fired: 0)
        }
    }

    /// Drops panes that are no longer blocked. Call it with every snapshot:
    /// a pane can leave `blocked` — or disappear entirely — without any
    /// transition reaching this type.
    public mutating func retain(blocked paneIDs: Set<String>) {
        pending = pending.filter { paneIDs.contains($0.key) }
    }

    /// The pane ids whose next reminder has come due, oldest interval first
    /// by id so a batch is ordered rather than however the dictionary hashed.
    ///
    /// The next fire time is measured from `now` rather than from the deadline
    /// that just passed, so a machine waking after an hour asleep delivers one
    /// reminder and not the whole backlog at once.
    public mutating func due(at now: ContinuousClock.Instant) -> [String] {
        var ready: [String] = []
        for (paneID, entry) in pending where entry.nextFireAt <= now {
            ready.append(paneID)
            let fired = entry.fired + 1
            pending[paneID] = Pending(
                nextFireAt: now.advanced(by: schedule[min(fired, schedule.count - 1)]),
                fired: fired
            )
        }
        return ready.sorted()
    }

    /// When the caller should next wake to check, or `nil` when nothing is
    /// blocked and the timer can stay off entirely.
    public var nextDeadline: ContinuousClock.Instant? {
        pending.values.map(\.nextFireAt).min()
    }
}
