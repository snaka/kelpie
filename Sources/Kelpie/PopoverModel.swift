import Foundation
import KelpieCore

/// Connection lifecycle as the popover needs to show it.
enum ConnectionState: Equatable {
    case connecting
    case connected
    case disconnected
    case protocolMismatch(Int)
}

/// The popover's view model. Owned and mutated by `AppCoordinator`; the view
/// only reads it and forwards user actions through the closures.
@MainActor
final class PopoverModel: ObservableObject {
    @Published var groups: [AgentGroup] = []
    @Published var connection: ConnectionState = .connecting
    @Published var notificationsDenied = false
    @Published var startAtLogin = false

    var onSelect: ((String) -> Void)?
    var onQuit: (() -> Void)?
    var onToggleLoginItem: ((Bool) -> Void)?
}
