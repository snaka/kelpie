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
    private func request<T>(_ body: (HerdrRequestConnection) async throws -> T) async throws -> T {
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

        let snapshot = try await request { try await $0.snapshot() }
        _ = state.replace(with: snapshot)

        events = eventConnection
        eventStream = stream
        model.connection = pong.protocolVersion == Self.knownProtocol
            ? .connected
            : .protocolMismatch(pong.protocolVersion)
        refreshUI()
        startResyncLoop()
    }

    private func pumpEvents() async {
        guard let stream = eventStream else { return }
        for await event in stream {
            let transitions = state.apply(event)
            let notifiable = NotificationPolicy.notifiable(transitions, phase: .live)
            for transition in notifiable {
                NotificationManager.shared.postBlocked(
                    workspace: state.label(for: transition.workspaceID),
                    title: transition.title,
                    paneID: transition.paneID
                )
            }
            refreshUI()
        }
    }

    /// A Task created inside a `@MainActor` type inherits that isolation, so
    /// everything in here is already on the main actor — no hop needed.
    private func startResyncLoop() {
        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.resyncInterval)
                guard let self else { return }
                guard let snapshot = try? await self.request({ try await $0.snapshot() })
                else { continue }
                // Resync transitions are deliberately discarded: they describe
                // state that already existed, and notifying for them would fire
                // every blocked agent again every five minutes.
                _ = self.state.replace(with: snapshot)
                self.refreshUI()
            }
        }
    }

    private func teardown() async {
        resyncTask?.cancel(); resyncTask = nil
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
            animationTimer = Timer.scheduledTimer(
                withTimeInterval: Self.animationInterval, repeats: true
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.tick &+= 1
                    self.renderMenuBar(counts: StatusCounts(state: self.state))
                }
            }
        } else if !wanted {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func jump(to paneID: String) {
        Task {
            try? await request { try await $0.focus(paneID: paneID) }
            TerminalActivator.activateHerdrHost()
        }
    }
}
