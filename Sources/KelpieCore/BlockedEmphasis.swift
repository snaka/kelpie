import Foundation

/// How loudly the menu bar should be shouting about a blocked pane.
public enum BlockedEmphasisLevel: Equatable, Sendable {
    /// The resting appearance: a red count, no inversion.
    case none
    /// Slow inversion — someone has not looked in a minute.
    case gentle
    /// Fast inversion — this one has genuinely been forgotten.
    case insistent
}

/// Escalates the menu bar's blocked count from a static red number to an
/// inverting one, based on how long the oldest blocked pane has been waiting.
///
/// `BlockedReminder` covers the same ground with notifications and this
/// deliberately keeps in step with it: the thresholds here are that type's
/// first two intervals, so the item starts blinking as the first re-notify
/// lands and speeds up as the second one does. What it does *not* share is
/// the once-only filtering. `BlockedReminder` is armed from
/// `NotificationPolicy.notifiable`, which drops panes that were already
/// blocked when Kelpie launched — a banner for those would be noise. Emphasis
/// is not a banner: a pane that was already blocked at launch is exactly the
/// forgotten kind, so this type is fed the raw blocked set and counts from
/// whenever Kelpie first saw the pane blocked.
///
/// Pure and clock-injected like `BlockedReminder`, so every threshold is
/// exercised by `swift test` without waiting five real minutes for one.
public struct BlockedEmphasis: Sendable {
    private var blockedSince: [String: ContinuousClock.Instant] = [:]
    private let thresholds: [Duration]

    /// One threshold per level above `.none`, ascending.
    public init(thresholds: [Duration] = [.seconds(60), .seconds(300)]) {
        precondition(thresholds.count == 2, "the level ladder has exactly two steps")
        self.thresholds = thresholds
    }

    /// The single entry point: hand it the currently blocked pane ids on every
    /// snapshot. Panes it has not seen start their clock at `now`, panes it
    /// already holds keep theirs, and panes no longer in the set are dropped —
    /// so a pane that unblocks and blocks again starts over, which is what
    /// someone who just dealt with it should get.
    public mutating func retain(blocked paneIDs: Set<String>, at now: ContinuousClock.Instant) {
        var updated: [String: ContinuousClock.Instant] = [:]
        updated.reserveCapacity(paneIDs.count)
        for paneID in paneIDs {
            updated[paneID] = blockedSince[paneID] ?? now
        }
        blockedSince = updated
    }

    /// Driven by the oldest blocked pane: one pane forgotten for ten minutes
    /// should keep shouting even as newer ones come and go around it.
    public func level(at now: ContinuousClock.Instant) -> BlockedEmphasisLevel {
        guard let oldest = blockedSince.values.min() else { return .none }
        let waited = oldest.duration(to: now)
        if waited >= thresholds[1] { return .insistent }
        if waited >= thresholds[0] { return .gentle }
        return .none
    }

    /// When the level would next rise, or `nil` when nothing is blocked or the
    /// top level is already reached. The caller schedules a single wake for
    /// this rather than polling, which is what keeps the animation timer off
    /// during the quiet first minute.
    public func nextDeadline(at now: ContinuousClock.Instant) -> ContinuousClock.Instant? {
        guard let oldest = blockedSince.values.min() else { return nil }
        for threshold in thresholds where oldest.advanced(by: threshold) > now {
            return oldest.advanced(by: threshold)
        }
        return nil
    }
}
