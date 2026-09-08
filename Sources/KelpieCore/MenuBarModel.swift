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
    /// Draw the segment as its role colour filled in behind white text rather
    /// than as coloured text. Only the blocked segment ever sets it, and only
    /// `BlockedEmphasisLevel` decides when — see `MenuBarModel.inverted`.
    public let inverted: Bool

    public init(text: String, role: MenuBarRole, inverted: Bool = false) {
        self.text = text
        self.role = role
        self.inverted = inverted
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
    public static func content(
        counts: StatusCounts,
        tick: Int,
        reduceMotion: Bool,
        emphasis: BlockedEmphasisLevel
    ) -> MenuBarContent {
        guard !counts.isResting else { return .resting }
        return .segments(segments(
            counts: counts, tick: tick, reduceMotion: reduceMotion, emphasis: emphasis
        ))
    }

    /// Braille frames: every one is the same width, so neighbouring menu bar
    /// items do not shift while the spinner turns.
    public static let spinnerFrames = ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]
    /// Shown instead of the spinner when Reduce Motion is on.
    public static let reducedMotionFrame = "⣿"

    private static let blockedGlyph = "◉"
    private static let doneGlyph = "✓"

    private static func segments(
        counts: StatusCounts,
        tick: Int,
        reduceMotion: Bool,
        emphasis: BlockedEmphasisLevel
    ) -> [MenuBarSegment] {
        var segments: [MenuBarSegment] = []
        if counts.blocked > 0 {
            segments.append(MenuBarSegment(
                text: "\(blockedGlyph)\(counts.blocked)",
                role: .blocked,
                inverted: inverted(emphasis: emphasis, tick: tick, reduceMotion: reduceMotion)
            ))
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

    /// The blink half-period, in animation ticks. The timer runs at 0.1 s, so
    /// gentle is a one-second cycle and insistent a 0.4-second one.
    private static func blinkHalfPeriod(_ emphasis: BlockedEmphasisLevel) -> Int? {
        switch emphasis {
        case .none: return nil
        case .gentle: return 5
        case .insistent: return 2
        }
    }

    /// Reduce Motion keeps the emphasis but drops the motion: the segment sits
    /// inverted instead of flashing, which also means no animation timer is
    /// needed to show it.
    static func inverted(emphasis: BlockedEmphasisLevel, tick: Int, reduceMotion: Bool) -> Bool {
        guard let half = blinkHalfPeriod(emphasis) else { return false }
        guard !reduceMotion else { return true }
        let period = half * 2
        // A monotonically increasing tick can overflow into negatives if the
        // app runs long enough, and modulo alone would then flip the phase.
        return ((tick % period) + period) % period < half
    }

    /// The animation timer runs only while something is working or a blocked
    /// pane is blinking; this is what keeps Kelpie's cost independent of how
    /// many agents and clients exist.
    public static func needsAnimation(_ counts: StatusCounts, emphasis: BlockedEmphasisLevel) -> Bool {
        counts.working > 0 || emphasis != .none
    }

    private static func frame(for tick: Int) -> String {
        let count = spinnerFrames.count
        // A monotonically increasing tick can overflow into negatives if the
        // app runs long enough; modulo alone would then index out of range.
        let index = ((tick % count) + count) % count
        return spinnerFrames[index]
    }
}
