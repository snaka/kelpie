import Foundation

/// Thrown by `withDeadline` when `bound` elapses before `operation` returns.
struct TestDeadlineExceeded: Error {}

/// Races `operation` against `bound`, for regression tests that must fail
/// fast rather than hang the suite if the bug they pin ever comes back.
///
/// A `TaskGroup`-based race is the wrong tool here: structured concurrency
/// implicitly awaits every child before `withThrowingTaskGroup` returns, so
/// if `operation` is the exact kind of permanently-parked task these tests
/// exist to catch, the race itself would hang draining it — defeating the
/// bound. Two unstructured tasks resuming one continuation avoid that: the
/// loser is abandoned, not awaited.
func withDeadline<T: Sendable>(
    _ bound: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
        let settled = DeadlineLatch()
        Task {
            do {
                let value = try await operation()
                if await settled.markFirst() { continuation.resume(returning: value) }
            } catch {
                if await settled.markFirst() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(for: bound)
            if await settled.markFirst() { continuation.resume(throwing: TestDeadlineExceeded()) }
        }
    }
}

/// One-shot latch so only the first of `withDeadline`'s two racing tasks
/// resumes the continuation.
private actor DeadlineLatch {
    private var done = false

    func markFirst() -> Bool {
        guard !done else { return false }
        done = true
        return true
    }
}
