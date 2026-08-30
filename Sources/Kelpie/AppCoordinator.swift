import AppKit
import SwiftUI
import KelpieCore
import KelpieClient

@MainActor
final class AppCoordinator {
    private let menuBar = MenuBarController()
    private let model = PopoverModel()

    private var state = SessionState()
    private var backoff = Backoff()
    private var tick = 0
    private var animationTimer: Timer?
    private var connectionTask: Task<Void, Never>?
    private var resyncTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var coalescer = RefreshCoalescer()
    private var events: HerdrEventConnection?
    private var eventStream: AsyncStream<LiveEvent>?

    private static let resyncInterval: Duration = .seconds(300)
    private static let animationInterval: TimeInterval = 0.1
    private static let knownProtocol = 20

    func start() {
        menuBar.install()
        menuBar.setPopoverContent(NSHostingController(rootView: AgentListView(model: model)))
        model.onQuit = { NSApp.terminate(nil) }
        model.onSelect = { [weak self] paneID in self?.jump(to: paneID) }
        model.startAtLogin = LoginItemController.isEnabled
        model.onToggleLoginItem = { [weak self] enabled in
            self?.model.startAtLogin = LoginItemController.setEnabled(enabled)
        }

        NotificationManager.shared.onActivate = { [weak self] paneID in
            self?.jump(to: paneID)
        }
        Task {
            _ = await NotificationManager.shared.requestAuthorization()
            model.notificationsDenied = await NotificationManager.shared.authorizationDenied()
        }

        connectionTask = Task { await runConnectionLoop() }
    }

    // MARK: - Connection

    private func runConnectionLoop() async {
        while !Task.isCancelled {
            model.connection = .connecting
            do {
                try await connectOnce()
                backoff.reset()
                await pumpEvents()
            } catch {
                // herdr not running is ordinary, so this is not logged as a
                // failure — it just schedules the next attempt.
            }
            await teardown()
            model.connection = .disconnected
            refreshUI()
            let delay = backoff.next()
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    /// herdr closes a request connection once it has answered a single
    /// request — verified against 0.8.2, where a second write on the same
    /// socket fails with EPIPE. Every request therefore gets its own
    /// short-lived connection. The event subscription is the opposite: that
    /// connection stays open and streams.
    ///
    /// `T: Sendable` is required by Swift 6.1 (CI's Xcode 16.4), where the
    /// nonisolated `body` call would otherwise send a non-Sendable result
    /// back into this actor; Swift 6.2 no longer flags it.
    private func request<T: Sendable>(_ body: (HerdrRequestConnection) async throws -> T) async throws -> T {
        let connection = HerdrRequestConnection(
            transport: UnixSocketTransport(path: UnixSocketTransport.defaultHerdrSocketPath)
        )
        try await connection.open()
        do {
            let value = try await body(connection)
            await connection.close()
            return value
        } catch {
            await connection.close()
            throw error
        }
    }

    private func connectOnce() async throws {
        let pong = try await request { try await $0.ping() }

        let eventConnection = HerdrEventConnection(
            transport: UnixSocketTransport(path: UnixSocketTransport.defaultHerdrSocketPath)
        )
        // Subscribe before snapshotting so no change slips through the gap.
        let stream = try await eventConnection.subscribe()

        // Adopt the subscription immediately, before anything else can throw.
        // If the snapshot below fails, `connectOnce` exits and `teardown()`
        // must be able to see and close this connection — otherwise an open,
        // already-streaming socket is abandoned on every retry for as long as
        // herdr stays in that failing state.
        events = eventConnection
        eventStream = stream

        let snapshot = try await request { try await $0.snapshot() }

        model.connection = pong.protocolVersion == Self.knownProtocol
            ? .connected
            : .protocolMismatch(pong.protocolVersion)
        // The first snapshot of a connection describes state that already
        // existed, so it is `.bootstrap` and must not notify. This is the only
        // place that phase is produced; everything after it is `.live`.
        applySnapshot(snapshot, phase: .bootstrap)
        startResyncLoop()
    }

    /// The single path from a snapshot to what the user sees. Both callers go
    /// through it so the phase is a real argument rather than something the
    /// call site could quietly get wrong.
    private func applySnapshot(_ snapshot: Snapshot, phase: ApplyPhase) {
        let transitions = state.replace(with: snapshot)
        for transition in NotificationPolicy.notifiable(transitions, phase: phase) {
            NotificationManager.shared.postBlocked(
                workspace: state.label(for: transition.workspaceID),
                title: transition.title,
                paneID: transition.paneID
            )
        }
        refreshUI()
    }

    /// Events say *that* something changed; the snapshot says *what to*. herdr's
    /// `revision` counts stripped-title changes, not state changes, so an event
    /// payload cannot be ordered against what we already hold — and subscribing
    /// replays history that does not converge to the current state. Re-reading
    /// the snapshot sidesteps both.
    private func pumpEvents() async {
        guard let stream = eventStream else { return }
        for await _ in stream {
            scheduleRefresh()
        }
    }

    private func scheduleRefresh() {
        switch coalescer.signal(at: ContinuousClock.now) {
        case .fireNow:
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                await self?.refreshFromSnapshot()
            }
        case .waitFor(let delay):
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                await self.refreshFromSnapshot()
            }
        }
    }

    private func refreshFromSnapshot() async {
        guard let snapshot = try? await request({ try await $0.snapshot() }) else { return }
        applySnapshot(snapshot, phase: .live)
        coalescer.didRefresh()
    }

    /// A Task created inside a `@MainActor` type inherits that isolation, so
    /// everything in here is already on the main actor — no hop needed.
    private func startResyncLoop() {
        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.resyncInterval)
                guard let self else { return }
                // A snapshot this far from bootstrap is `.live`: state is
                // always current, so a diff here is only non-empty when
                // something genuinely changed, and it deserves the same
                // notification any other live change would get.
                await self.refreshFromSnapshot()
            }
        }
    }

    private func teardown() async {
        resyncTask?.cancel(); resyncTask = nil
        refreshTask?.cancel(); refreshTask = nil
        coalescer = RefreshCoalescer()
        eventStream = nil
        await events?.close(); events = nil
        state = SessionState()
    }

    // MARK: - UI

    private func refreshUI() {
        model.groups = AgentGrouping.groups(state: state)
        let counts = StatusCounts(state: state)
        renderMenuBar(counts: counts)
        syncAnimationTimer(counts: counts)
    }

    private func renderMenuBar(counts: StatusCounts) {
        menuBar.render(segments: MenuBarModel.segments(
            counts: counts,
            tick: tick,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ))
    }

    /// The timer exists only while something is working. This is what keeps
    /// Kelpie's cost independent of agent count and of how many clients are
    /// attached to herdr.
    private func syncAnimationTimer(counts: StatusCounts) {
        let wanted = MenuBarModel.needsAnimation(counts)
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if wanted, animationTimer == nil {
            let timer = Timer(timeInterval: Self.animationInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.tick &+= 1
                    self.renderMenuBar(counts: StatusCounts(state: self.state))
                }
            }
            // `.common`, not the default mode: a timer scheduled in the default
            // mode alone stops firing while the run loop is in event tracking,
            // which is precisely when the popover or a menu is open — the
            // spinner would freeze exactly while the user is looking at it.
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else if !wanted {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func jump(to paneID: String) {
        Task {
            try? await request { try await $0.focus(paneID: paneID) }
            await TerminalActivator.activateHerdrHost()
        }
    }
}
