# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

Kelpie is a macOS menu bar app that shows the live state of the coding agents
running under [herdr](https://github.com/herdrdev/herdr) — blocked / working /
done counts as an `NSStatusItem`, a per-pane popover, click-to-jump, and
best-effort macOS notifications on a genuine live transition into `blocked`.
It talks to herdr over its Unix domain socket at `~/.config/herdr/herdr.sock`
and performs exactly one write operation: `agent.focus`.

Read [`README.md`](README.md) for the user-facing pitch and the manual
verification checklist, and [`ROADMAP.md`](ROADMAP.md) for deferred work with
its reasoning. The original design doc is
`docs/superpowers/specs/2026-08-30-kelpie-design.md`.

## Architecture — three layers

- **`KelpieCore`** — pure logic, no I/O, no AppKit, no `Foundation` socket or
  notification types. `AgentStatus`, `AgentRecord`, `SessionState` (the
  authoritative reducer), `StatusCounts`, `AgentGrouping`, `MenuBarModel`,
  `NotificationPolicy`, `BlockedReminder`. Every behavioral rule Kelpie depends
  on — bootstrap is silent, a live transition into `blocked` notifies exactly
  once, no ordinary update re-fires it, a pane left blocked is reminded about
  on a widening 1/5/15-minute schedule (and one blocked before launch never
  is), and a burst of change signals coalesces into one refresh without
  starving — lives here and is testable with `swift test` and no running
  herdr. New decision logic belongs here, not in the app layer.
- **`KelpieClient`** — the herdr socket client: `UnixSocketTransport`,
  `NDJSONFramer`, `Wire` request/response encode-decode, `HerdrRequestConnection`
  (short-lived, one call), `HerdrEventConnection` (long-lived subscription),
  `Backoff`. This is the only layer that breaks if herdr's wire format
  changes — that blast radius is deliberately confined here.
- **`Kelpie`** (app target) — deliberately thin. `AppCoordinator` owns the
  connect/subscribe/snapshot/resync/reconnect state machine and fans results
  out to `MenuBarController` (`NSStatusItem` + the animation timer),
  `AgentListView` (SwiftUI, hosted in an `NSPopover`), `NotificationManager`
  (`UNUserNotificationCenter`), `TerminalActivator` (process-tree walk to
  find and activate the hosting terminal), and `LoginItemController`
  (`SMAppService`). No decision logic here that could instead live in
  `KelpieCore`.

## Build and test

The Xcode project is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and is gitignored.

```bash
xcodegen generate     # rewrites Sources/Kelpie/Info.plist in place — see Gotchas
open Kelpie.xcodeproj

# pure-Swift core + client tests (fast, no app host needed)
swift test

# full app, unsigned, for local debugging
xcodebuild -project Kelpie.xcodeproj -scheme Kelpie -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

## Gotchas

- **`xcodegen generate` rewrites `Sources/Kelpie/Info.plist` in place, and the
  merged file is tracked on purpose.** Unlike the sibling apps, Kelpie's
  `project.yml` uses `GENERATE_INFOPLIST_FILE: NO` with an `info.path` pointing
  at the checked-in `Info.plist`, so XcodeGen merges `project.yml`'s `info:
  properties` into that file on every `generate` run rather than producing a
  throwaway generated one. Do not treat a post-`generate` diff in
  `Sources/Kelpie/Info.plist` as accidental — only revert it if the merged
  values actually diverged from what `project.yml` declares.
- `*.xcodeproj/` is gitignored; never `git add` the generated project.
- No third-party dependencies. `Package.swift` has no remote packages — if
  `xcodebuild archive` reports a resolution error in CI, regenerate the
  project with `xcodegen generate` rather than chasing a package graph.
- Not sandboxed (`com.apple.security.app-sandbox: false` in
  `Kelpie.entitlements`) — required to open
  `~/.config/herdr/herdr.sock`, which is not a TCC-protected location for a
  non-sandboxed process.

## herdr protocol facts (established by live testing against 0.8.2)

These are not fully discoverable from herdr's own documentation, and two of
them **contradict** it. Re-verify against a live session with
`herdr api snapshot`, `herdr api schema --json`, and a raw
`events.subscribe` session against `~/.config/herdr/herdr.sock` before assuming
they still hold on a newer
herdr.

- **A request connection is spent after one answer.** herdr closes it, and a
  second write on the same socket fails with `EPIPE`. `HerdrRequestConnection`
  is therefore built fresh for every single call (`ping`, `session.snapshot`,
  `agent.focus`) — see the doc comment on `HerdrRequestConnection`. A
  **subscription** connection (`HerdrEventConnection`) is the opposite: it
  stays open and streams for the app's whole lifetime.
- **herdr replays historical events when a subscription opens**, contrary to
  its own documentation, which states lifecycle subscriptions "do not replay
  events retained before that point." In practice, subscribing emits a burst
  of historical events before live events begin, and **that replay does not
  converge to the current state** — it was measured at 16 events over 1.1 s,
  including panes that no longer exist. This is why events are only a signal
  that something changed: a debounced `session.snapshot` is the sole authority.
- **`revision` cannot order state changes.** herdr increments it in exactly one
  place (`src/terminal/state.rs`), when the *stripped terminal title* changes —
  never on a status change. A stale replay event and the authoritative snapshot
  were observed carrying the same `revision` (2) with different statuses. Do not
  reintroduce a `revision` guard on the event path; it silently drops real
  status changes, which is the bug Task 20 fixed. `state_change_seq` would order
  them but exists only on snapshot agent records, not on the event payload.
- **Live agent status changes are emitted only as `pane.agent_status_changed`,
  which must be subscribed per pane.** herdr rejects a global subscription to
  it (`invalid request: missing field 'pane_id'`), and the global
  `pane.updated` **never fires on a status change** — it fires on
  stripped-title changes, agent renames, and metadata expiry only (herdr
  `src/app/api.rs` `emit_pane_state_update`, `src/app/terminal_titles.rs`).
  The connect-time replay does contain `pane.updated` entries carrying varied
  `agent_status` values, which is exactly what misled the original protocol
  testing into believing status flowed through it; live, a status change
  reaches a global-only subscriber never, and the UI degrades to the 300 s
  resync. Kelpie therefore snapshots first, subscribes
  `pane.agent_status_changed` for every known pane, and tears down and
  rebuilds the event connection whenever the pane set changes — see
  `SubscriptionPlan` in `KelpieCore`. Note the delivered `event` field for
  per-pane subscription events is the **dotted** form
  (`pane.agent_status_changed`), unlike the underscored global events.
- **Walking the process tree to find the hosting terminal must read
  `PROC_PIDT_SHORTBSDINFO`, not the full `PROC_PIDTBSDINFO`.** The full struct
  returns `EPERM` for the setuid-root `/usr/bin/login` that sits in a TUI
  client's ancestor chain on this platform, which stops the walk one hop
  short of the `.app`. The short variant exposes only
  pid/ppid/pgid/status/comm and is readable across uids. See
  `TerminalActivator.parentPID(of:)`.

## Development-environment limits (do not waste time rediscovering these)

- **An ad-hoc-signed build launched from `build/` cannot obtain notification
  authorization.** `UNUserNotificationCenter.requestAuthorization` throws
  `UNErrorDomain Code=1` (`notificationsNotAllowed`), and
  `authorizationStatus` stays `.notDetermined` forever. Notification behavior
  can only be verified against a properly signed, installed build — see the
  checklist in `README.md`.
- **`SMAppService` refuses to register an app running from a build
  directory.** `SMAppService.mainApp.status` reads `.notFound` and the toggle
  has no real effect until Kelpie is installed to `/Applications`.

## Commit style

Lowercase conventional commits, no emojis, no AI co-author trailer. An
explanatory body is welcome. Example: `docs: add readme, roadmap and signed
release pipeline`.

## Release

Signed and notarized via `.github/workflows/release.yml`, reusing the Apple
Developer assets already used by `snaka/jubako`, `snaka/Bokashi`, and
`snaka/invixray`, and pushing a cask to `snaka/homebrew-tap`. Full operator
runbook and the secrets list are in [`RELEASE.md`](RELEASE.md). Kelpie has no
unsigned first release to migrate away from — v0.1.0 itself is signed and
notarized.
