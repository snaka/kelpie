import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Called with the pane id when the user activates a notification.
    var onActivate: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()
    // Read from the `nonisolated` delegate callback below before hopping to
    // the main actor, so this constant must not inherit the class's
    // `@MainActor` isolation.
    private nonisolated static let paneIDKey = "paneID"

    override private init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        // Completion-handler form for the same reason as below: Swift 6.1
        // won't send the non-Sendable center into the async overload.
        //
        // `@Sendable` is load-bearing: without it, a closure written inside
        // this `@MainActor` class is inferred MainActor-isolated under the
        // Swift 6.1 SDKs, and the compiler plants a dispatch_assert_queue
        // check at its entry. UserNotifications invokes the completion on a
        // background queue, so that check aborts the process at launch —
        // observed as `BUG IN CLIENT OF LIBDISPATCH` on the v0.1.0 release
        // binary. Newer SDKs annotate the parameter themselves, which is why
        // local builds never crashed. `continuation.resume` is thread-safe,
        // so no hop back to the main queue is needed.
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { @Sendable granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func authorizationDenied() async -> Bool {
        // `UNNotificationSettings` is not Sendable under Swift 6.1 (CI's
        // Xcode 16.4), so go through the completion-handler API and send
        // back only the status enum. `@Sendable` for the same reason as
        // above — this callback also arrives on a background queue.
        let status = await withCheckedContinuation { continuation in
            center.getNotificationSettings { @Sendable settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
        return status == .denied
    }

    /// Posted for a genuine live transition into `blocked`, and again for each
    /// reminder while the pane stays there. `NotificationPolicy` and
    /// `BlockedReminder` decide which is which; this only delivers.
    ///
    /// The identifier is the pane and deliberately carries no timestamp.
    /// Reminders say the same thing about the same pane, so each replaces the
    /// last instead of stacking another identical row in Notification Center —
    /// with a timestamp in it, an agent left blocked overnight would leave a
    /// column of duplicates behind.
    func postBlocked(workspace: String, title: String?, paneID: String) {
        let content = UNMutableNotificationContent()
        content.title = workspace
        content.body = title ?? "Waiting for input"
        content.sound = .default
        content.userInfo = [Self.paneIDKey: paneID]

        center.add(UNNotificationRequest(
            identifier: "blocked-\(paneID)",
            content: content,
            trigger: nil
        ))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let paneID = userInfo[Self.paneIDKey] as? String else { return }
        await MainActor.run { self.onActivate?(paneID) }
    }

    /// Show the banner even when Kelpie is frontmost; the user is usually
    /// looking at a different app entirely.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
