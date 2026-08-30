import AppKit
import KelpieCore

/// The only place that maps Kelpie's semantic roles to colour. Keeping it here
/// leaves `KelpieCore` free of AppKit.
enum MenuBarPalette {
    static func color(for role: MenuBarRole) -> NSColor {
        switch role {
        case .blocked: return .systemRed
        case .working: return .systemYellow
        case .done: return .systemGreen
        case .resting: return .tertiaryLabelColor
        }
    }
}
