import AppKit
import SwiftUI
import KelpieCore
import KelpieClient
import os

@MainActor
final class AppCoordinator {
    /// Debug-level breadcrumbs at every stage boundary (connect, event,
    /// snapshot, render). Invisible in normal use; surfaced with
    /// `log stream --predicate 'subsystem == "com.snaka.kelpie"' --level debug`
    /// when diagnosing a stale menu bar.
    private static let log = Logger(subsystem: "com.snaka.kelpie", category: "coordinator")

    private let menuBar = MenuBarController()
    private let model = PopoverModel()

    private var state = SessionState()
    private var backoff = Backoff()
    private var tick = 0
    private var animationTimer: Timer?
    private var connectionTask: Task<Void, Never>?
    private var resyncTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var reminderTask: Task<Void, Never>?
    private var coalescer = RefreshCoalescer()
    /// Re-notifies for panes left sitting in `blocked`. `NotificationPolicy`
    /// covers the first banner; this covers the ones nobody answered.
    private var reminder = BlockedReminder()
    private var events: HerdrEventConnection?
    private var eventStream: AsyncStream<LiveEvent>?
    /// The pane set the live event connection was built for. herdr only
    /// delivers agent status changes through per-pane subscriptions, so when
    /// the actual pane set drifts from this, the connection is rebuilt.
    private var subscribedPaneIDs: Set<String> = []
    /// Set when the event connection is closed on purpose to pick up a changed
    /// pane set; the reconnect then skips the disconnected UI and the backoff.
    private var rebuildRequested = false

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
                Self.log.debug("connected; pumping events")
                await pumpEvents()
                Self.log.debug("event stream ended")
            } catch {
                // herdr not running is ordinary, so this is not logged as a
                // failure — it just schedules the next attempt.
                Self.log.debug("connect failed: \(String(describing: error), privacy: .public)")
            }
            await teardown()
            if rebuildRequested {
                // The stream ended because Kelpie closed it over a pane set
                // change, not because herdr went away: reconnect immediately
                // and leave the current menu bar contents up meanwhile.
                rebuildRequested = false
                continue
            }
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

        // Status changes only arrive through per-pane subscriptions (see
        // SubscriptionPlan), so the pane list has to exist before the
        // subscription can. This snapshot is only a plan — a second one below
        // closes the gap. If a planned pane disappears before the subscribe
        // lands, herdr rejects the whole subscription; that throw falls into
        // the reconnect loop, which replans from a fresh snapshot.
        let planning = try await request { try await $0.snapshot() }
        let plannedPanes = Set(planning.agents.map(\.paneID))

        let eventConnection = HerdrEventConnection(
            transport: UnixSocketTransport(path: UnixSocketTransport.defaultHerdrSocketPath),
            subscriptions: SubscriptionPlan.subscriptions(paneIDs: plannedPanes)
        )
        let stream = try await eventConnection.subscribe()

        // Adopt the subscription immediately, before anything else can throw.
        // If the snapshot below fails, `connectOnce` exits and `teardown()`
        // must be able to see and close this connection — otherwise an open,
        // already-streaming socket is abandoned on every retry for as long as
        // herdr stays in that failing state.
        events = eventConnection
        eventStream = stream
        subscribedPaneIDs = plannedPanes

        // Snapshot again after subscribing so no change slips through the gap
        // between the planning snapshot and the live subscription.
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
        if events != nil, !rebuildRequested,
           SubscriptionPlan.needsRebuild(subscribed: subscribedPaneIDs,
                                         current: Set(state.agents.keys)) {
            Self.log.debug("pane set changed; rebuilding the event subscription")
            rebuildRequested = true
            Task { [events] in await events?.close() }
        }
        let notifiable = NotificationPolicy.notifiable(transitions, phase: phase)
        for transition in notifiable {
            NotificationManager.shared.postBlocked(
                workspace: state.label(for: transition.workspaceID),
                title: transition.title,
                paneID: transition.paneID
            )
        }
        // Sweep before arming: a pane can leave `blocked` — or vanish from the
        // session entirely — without any transition for it reaching this far.
        reminder.retain(blocked: Set(state.agentPanes.filter { $0.status == .blocked }.map(\.paneID)))
        reminder.arm(notifiable, at: ContinuousClock.now)
        scheduleReminder()
        refreshUI()
    }

    /// Like the animation timer, this exists only while there is something to
    /// fire for: with nothing blocked there is no deadline and no task at all.
    private func scheduleReminder() {
        reminderTask?.cancel()
        guard let deadline = reminder.nextDeadline else {
            reminderTask = nil
            return
        }
        reminderTask = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: ContinuousClock())
            guard !Task.isCancelled, let self else { return }
            self.fireDueReminders()
        }
    }

    /// Reads the title from the current snapshot rather than replaying the one
    /// captured when the pane blocked, which is minutes stale by the time a
    /// later reminder fires.
    private func fireDueReminders() {
        let due = reminder.due(at: ContinuousClock.now)
        if !due.isEmpty {
            Self.log.debug("reminding \(due.count) blocked pane(s)")
        }
        for paneID in due {
            guard let record = state.agents[paneID] else { continue }
            NotificationManager.shared.postBlocked(
                workspace: state.label(for: record.workspaceID),
                title: record.title,
                paneID: paneID
            )
        }
        scheduleReminder()
    }

    /// Events say *that* something changed; the snapshot says *what to*. herdr's
    /// `revision` counts stripped-title changes, not state changes, so an event
    /// payload cannot be ordered against what we already hold — and subscribing
    /// replays history that does not converge to the current state. Re-reading
    /// the snapshot sidesteps both.
    private func pumpEvents() async {
        guard let stream = eventStream else { return }
        for await _ in stream {
            Self.log.debug("event received")
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
        guard let snapshot = try? await request({ try await $0.snapshot() }) else {
            Self.log.debug("live snapshot request failed")
            return
        }
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
        reminderTask?.cancel(); reminderTask = nil
        reminder = BlockedReminder()
        coalescer = RefreshCoalescer()
        eventStream = nil
        await events?.close(); events = nil
        subscribedPaneIDs = []
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
        let content = MenuBarModel.content(
            counts: counts,
            tick: tick,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        if case .resting = content {
            Self.log.debug("render: resting")
        } else {
            Self.log.debug("render: b\(counts.blocked) w\(counts.working) d\(counts.done)")
        }
        menuBar.render(content)
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
