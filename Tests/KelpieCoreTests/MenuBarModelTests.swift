import Testing
@testable import KelpieCore

@Suite("MenuBarModel")
struct MenuBarModelTests {

    private func counts(blocked: Int = 0, working: Int = 0, done: Int = 0) -> StatusCounts {
        StatusCounts(blocked: blocked, working: working, done: done, idle: 0, unknown: 0)
    }

    /// Unwraps the segments of an active state; fails the test if the content
    /// turned out to be `.resting`.
    private func segments(_ counts: StatusCounts, tick: Int = 0, reduceMotion: Bool = false) -> [MenuBarSegment] {
        guard case .segments(let segments) = MenuBarModel.content(
            counts: counts, tick: tick, reduceMotion: reduceMotion
        ) else {
            Issue.record("expected .segments for \(counts)")
            return []
        }
        return segments
    }

    @Test("All-idle renders as the resting icon, not text segments")
    func restingContent() {
        let content = MenuBarModel.content(counts: counts(), tick: 0, reduceMotion: false)
        #expect(content == .resting)
    }

    @Test("Zero-count segments are omitted entirely")
    func zeroSegmentsOmitted() {
        #expect(segments(counts(working: 2)).map(\.role) == [.working])
    }

    @Test("Segments appear in blocked, working, done order")
    func segmentOrder() {
        let segments = segments(counts(blocked: 1, working: 2, done: 3))
        #expect(segments.map(\.role) == [.blocked, .working, .done])
        #expect(segments[0].text == "◉1")
        #expect(segments[2].text == "✓3")
    }

    @Test("The working segment advances through the spinner frames")
    func spinnerAdvances() {
        let frames = (0..<8).map { segments(counts(working: 1), tick: $0)[0].text }
        #expect(frames == MenuBarModel.spinnerFrames.map { $0 + "1" })
    }

    @Test("The spinner wraps around and tolerates a negative tick")
    func spinnerWraps() {
        let first = segments(counts(working: 1), tick: 0)[0].text
        let wrapped = segments(counts(working: 1), tick: 8)[0].text
        let negative = segments(counts(working: 1), tick: -1)[0].text
        #expect(first == wrapped)
        #expect(MenuBarModel.spinnerFrames.contains { negative.hasPrefix($0) })
    }

    @Test("Reduce Motion pins the working glyph to a static frame")
    func reduceMotion() {
        let a = segments(counts(working: 1), reduceMotion: true)[0].text
        let b = segments(counts(working: 1), tick: 5, reduceMotion: true)[0].text
        #expect(a == MenuBarModel.reducedMotionFrame + "1")
        #expect(a == b)
    }

    @Test("All spinner frames are single characters so the width never shifts")
    func uniformFrameWidth() {
        #expect(MenuBarModel.spinnerFrames.count == 8)
        #expect(MenuBarModel.spinnerFrames.allSatisfy { $0.count == 1 })
    }

    @Test("Animation is needed only while something is working")
    func animationNeeded() {
        #expect(MenuBarModel.needsAnimation(counts(working: 1)))
        #expect(!MenuBarModel.needsAnimation(counts(blocked: 3, done: 2)))
        #expect(!MenuBarModel.needsAnimation(counts()))
    }
}
