import Foundation
import ServiceManagement

/// A menu bar app that does not come back after a reboot is not doing its job.
/// `SMAppService` needs no helper bundle and no settings window.
enum LoginItemController {

    @MainActor
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting state, so the toggle reflects reality rather than
    /// the request when registration is refused.
    @MainActor
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration fails when the app is not in a stable location,
            // e.g. run straight from a build directory.
        }
        return isEnabled
    }
}
