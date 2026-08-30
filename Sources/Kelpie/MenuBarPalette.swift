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
        // secondaryLabel, not tertiary. At tertiary the resting glyph is
        // effectively invisible against a busy menu bar — the user could not
        // tell Kelpie was running at all. "Does not compete for attention"
        // has to stop short of "absent".
        case .resting: return .secondaryLabelColor
        }
    }
}
