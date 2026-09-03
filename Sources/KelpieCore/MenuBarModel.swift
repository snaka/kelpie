import Foundation

/// What a menu bar segment means. The app layer maps this to a colour; the
/// model itself stays free of AppKit.
public enum MenuBarRole: Equatable, Sendable {
    case blocked
    case working
    case done
}

public struct MenuBarSegment: Equatable, Sendable {
    public let text: String
    public let role: MenuBarRole

    public init(text: String, role: MenuBarRole) {
        self.text = text
        self.role = role
    }
}

/// What the status item should show. At rest that is an icon, not text: the
/// app layer draws it as a template image so macOS keeps it legible against
/// any menu bar background — a dim text glyph was invisible over colourful
/// wallpapers.
public enum MenuBarContent: Equatable, Sendable {
    case resting
    case segments([MenuBarSegment])
}

public enum MenuBarModel {
    public static func content(counts: StatusCounts, tick: Int, reduceMotion: Bool) -> MenuBarContent {
        guard !counts.isResting else { return .resting }
        return .segments(segments(counts: counts, tick: tick, reduceMotion: reduceMotion))
    }

    /// Braille frames: every one is the same width, so neighbouring menu bar
    /// items do not shift while the spinner turns.
    public static let spinnerFrames = ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]
    /// Shown instead of the spinner when Reduce Motion is on.
    public static let reducedMotionFrame = "⣿"

    private static let blockedGlyph = "◉"
    private static let doneGlyph = "✓"

    private static func segments(counts: StatusCounts, tick: Int, reduceMotion: Bool) -> [MenuBarSegment] {
        var segments: [MenuBarSegment] = []
        if counts.blocked > 0 {
            segments.append(MenuBarSegment(text: "\(blockedGlyph)\(counts.blocked)", role: .blocked))
        }
        if counts.working > 0 {
            let glyph = reduceMotion ? reducedMotionFrame : frame(for: tick)
            segments.append(MenuBarSegment(text: "\(glyph)\(counts.working)", role: .working))
        }
        if counts.done > 0 {
            segments.append(MenuBarSegment(text: "\(doneGlyph)\(counts.done)", role: .done))
        }
        return segments
    }

    /// The animation timer runs only while something is working; this is what
    /// keeps Kelpie's cost independent of how many agents and clients exist.
    public static func needsAnimation(_ counts: StatusCounts) -> Bool {
        counts.working > 0
    }

    private static func frame(for tick: Int) -> String {
        let count = spinnerFrames.count
        // A monotonically increasing tick can overflow into negatives if the
        // app runs long enough; modulo alone would then index out of range.
        let index = ((tick % count) + count) % count
        return spinnerFrames[index]
    }
}
