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
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
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
