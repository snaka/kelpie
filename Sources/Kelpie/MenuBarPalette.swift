import AppKit
import KelpieCore

/// The only place that maps Kelpie's semantic roles to colour. Keeping it here
/// leaves `KelpieCore` free of AppKit.
enum MenuBarPalette {
    /// An inverted segment is the role colour filled in behind white text.
    /// White rather than a system label colour because the fill is always a
    /// saturated system colour, in both the light and the dark menu bar.
    static func foreground(for segment: MenuBarSegment) -> NSColor {
        segment.inverted ? .white : color(for: segment.role)
    }

    static func background(for segment: MenuBarSegment) -> NSColor? {
        segment.inverted ? color(for: segment.role) : nil
    }

    private static func color(for role: MenuBarRole) -> NSColor {
        switch role {
        case .blocked: return .systemRed
        case .working: return .systemYellow
        case .done: return .systemGreen
        }
    }
}
