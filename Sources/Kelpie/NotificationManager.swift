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
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func authorizationDenied() async -> Bool {
        // `UNNotificationSettings` is not Sendable under Swift 6.1 (CI's
        // Xcode 16.4), so go through the completion-handler API and send
        // back only the status enum.
        let status = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
        return status == .denied
    }

    /// Posted only for genuine live transitions into `blocked`;
    /// `NotificationPolicy` has already filtered bootstrap and resync out.
    func postBlocked(workspace: String, title: String?, paneID: String) {
        let content = UNMutableNotificationContent()
        content.title = workspace
        content.body = title ?? "Waiting for input"
        content.sound = .default
        content.userInfo = [Self.paneIDKey: paneID]

        center.add(UNNotificationRequest(
            identifier: "blocked-\(paneID)-\(Date().timeIntervalSince1970)",
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
