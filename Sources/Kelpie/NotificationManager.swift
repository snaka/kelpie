import Foundation

/// Stub for this task. Filled in by Task 16 with `UNUserNotificationCenter`
/// integration; `AppCoordinator` already calls this on every live transition
/// into `blocked`.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    func postBlocked(workspace: String, title: String?, paneID: String) {}
}
