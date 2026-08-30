# Kelpie — Design

Date: 2026-08-30
Status: implemented

**Amended 2026-08-30 — superseded by Task 20.** This spec originally had Kelpie
apply event payloads to its state, ordering them by herdr's `revision`. Testing
against a live herdr 0.8.2 server proved that unsound: herdr increments
`revision` only when the *stripped terminal title* changes, so it cannot order
status transitions, and the subscribe-time replay burst does not converge to the
current state — a stale burst event and the authoritative snapshot were observed
carrying the same `revision` with different statuses. Events are now a change
signal only; a debounced `session.snapshot` is the sole authority for agent
state. The sections below are amended in place; the original reasoning and the
evidence are preserved in the plan's Task 20.

## Purpose

Kelpie is a macOS menu bar app that shows the live state of the coding agents
running under [herdr](https://github.com/herdrdev/herdr), animated, from outside
herdr itself.

herdr removed its animated agent spinners in commit `81f355fa` (released in
v0.8.0) and now conveys agent state with static marks and color. The removal was
well-founded: herdrdev/herdr#1862 measured the headless server sustaining 16–23%
of a CPU core with three attached clients and two working panes, with 97.8% of
runnable samples inside `render_and_stream`, because a single working pane armed
a 128 ms animation tick that forced a full render per attached client.
herdrdev/herdr#967 reported the focused pane's hardware cursor flickering in
lockstep with the sidebar spinner. Both are consequences of animation living on a
path whose cost multiplies by pane count and attached client count.

Kelpie restores the at-a-glance motion cue without reintroducing that cost. Its
rendering is one process updating a few glyphs in the menu bar; the work scales
with neither pane count nor the number of attached herdr clients.

Secondary benefit: herdr's own macOS `system` notification delivery falls back to
`osascript` when `terminal-notifier` is absent, which appears in Notification
Center as "Script Editor" and cannot activate the hosting terminal. Kelpie is a
real app bundle, so its notifications carry a correct identity and can bring the
user all the way to the waiting pane.

## Non-goals

- Kelpie does not patch, fork, or change herdr's rendering in any way.
- Kelpie is not a herdr controller. The only write operation it performs is
  `agent.focus`.
- v1 observes the default herdr session only. Named sessions are deferred.
- No settings window. "Start at login" is the only preference, and it lives as a
  single toggle in the popover footer.

## herdr interface contract

All facts below were verified against herdr 0.8.2 (wire protocol 20) on
2026-08-30.

### Transport

Newline-delimited JSON over a Unix domain socket at `~/.config/herdr/herdr.sock`
(mode `srw-------`, owned by the user). One JSON request per line; the response
carries the same `id`. `~/.config` is not a TCC-protected location, so a
non-sandboxed GUI process opens it without any permission prompt. Verified: the
herdr CLI resolves and uses the socket correctly with every `HERDR_*` environment
variable removed, which is the condition a GUI launch runs under.

### Methods used

| Method | Use |
| --- | --- |
| `ping` | Returns `version`, `protocol`, `capabilities`. Used for the compatibility check on connect and reconnect. |
| `session.snapshot` | Bootstrap. Returns `agents`, `workspaces`, `panes`, `tabs`, `layouts`, focused ids, `version`, `protocol`. |
| `events.subscribe` | Live updates. Keeps the connection open after the acknowledgement. |
| `agent.focus` | The only write. Moves herdr's focus to a pane. |

### Records

An `agents[]` record carries `agent`, `agent_status`, `cwd`, `focused`,
`foreground_cwd`, `pane_id`, `revision`, `state_change_seq`, `tab_id`,
`terminal_id`, `terminal_title`, `terminal_title_stripped`, `workspace_id`.

`agent_status` is one of `idle`, `working`, `blocked`, `done`, `unknown`.

Agent records carry `workspace_id` (`wX`) but not the workspace's display name.
The name comes from the `workspaces[]` records in `session.snapshot`, which carry
`label` (e.g. `larning-math`), `workspace_id`, `agent_status`, `focused`,
`number`, `pane_count`, `tab_count`. Kelpie keeps a `workspace_id → label` map
from the snapshot and maintains it from workspace events.

### Subscriptions

Global (no `pane_id` required), and the set Kelpie subscribes to:

- `pane.updated` — carries the full pane record including `agent_status` and
  `terminal_title_stripped`. This is the primary status channel.
- `pane.created`, `pane.closed`, `pane.agent_detected`
- `workspace.created`, `workspace.renamed`, `workspace.closed`,
  `workspace.updated` — for the label map.

`pane.agent_status_changed` is **not** usable: it requires a `pane_id` and
rejects a global subscription with
`invalid request: missing field 'pane_id'`. `pane.updated` covers the same
information for every pane.

### Observed behaviour that the docs do not describe

The socket API documentation states that lifecycle subscriptions "do not replay
events retained before that point". In practice, subscribing emitted a burst of
historical events — `pane_created` records with `revision` 0 and 1 for panes that
already existed, and past `workspace_focused` events — before live events began.

Kelpie must therefore not assume the stream starts empty. This is handled in
`KelpieCore` by treating `(pane_id, revision)` as the authority and discarding any
event whose `revision` is not greater than the one already held, and by
suppressing notifications for everything that arrives before the bootstrap
completes (see Notifications).

## Architecture

Three layers, following the structure already established in `snaka/invixray`.

### `KelpieCore` — pure logic

Owns `AgentStatus`, `AgentRecord`, `WorkspaceLabel`, and `SessionState`. Knows
nothing about sockets, AppKit, or notifications, so its entire surface is
testable with `swift test` and without a running herdr.

Responsibilities:

- `SessionState.replace(with: Snapshot)` — the only way state changes. It
  installs a snapshot and reports the transitions between the old state and the
  new one. There is no per-event application and no `revision` guard: `revision`
  counts stripped-title changes, not state changes, so it cannot order status.
- `RefreshCoalescer` — decides when a burst of change signals becomes one
  refresh. herdr's replay burst arrives about 70 ms apart, denser than the
  debounce, so the coalescer caps how long it will defer.
- `StatusCounts` — the blocked/working/done/idle tallies the menu bar renders.
- Grouping and ordering for the popover.
- `NotificationPolicy.notifiable(_:phase:)` — the pure decision of which
  transitions deserve a notification. Bootstrap is silent because it describes
  state that already existed; everything after it is a real change.

### `KelpieClient` — herdr socket client

Owns two socket connections, NDJSON framing, request/response correlation by
`id`, the subscription stream, `agent.focus`, the protocol compatibility check,
and the reconnect backoff.

Two connections are required, not an implementation preference: an
`events.subscribe` connection stays open streaming events, so request/response
calls cannot share it. herdr's own documentation prescribes opening the
subscription on one connection and calling `session.snapshot` on another. Kelpie
therefore holds a long-lived **event connection** and a short-lived **request
connection** used for `ping`, `session.snapshot`, and `agent.focus`.

The transport is behind a protocol so tests can drive it with a scripted byte
stream instead of a real socket. This is the only layer that breaks if herdr
changes its wire format, and confining that blast radius to one module is the
point of the split.

### `Kelpie` — app target

`AppDelegate` starts an `AppCoordinator`, which feeds `KelpieClient` output into
`SessionState` and fans the result out to:

- `MenuBarController` — `NSStatusItem` rendering and the animation timer.
- `AgentListView` — SwiftUI, hosted in an `NSPopover`.
- `NotificationManager` — `UNUserNotificationCenter`.
- `TerminalActivator` — process tree walk and terminal activation.
- `LoginItemController` — `SMAppService`.

The app target is deliberately thin. It contains no decision logic that could be
expressed in `KelpieCore`.

## Data flow

1. **Connect.** Open the request connection. Send `ping`. Compare `protocol`
   against the known-good value (20). A mismatch does not abort; it raises a
   warning banner.
2. **Subscribe first, then snapshot.** Open the event connection, send
   `events.subscribe`, and wait for its acknowledgement, buffering everything
   that arrives after it. Only then call `session.snapshot` on the request
   connection, install it as the authoritative state, and replay the buffered
   events in order. This ordering is what herdr's documentation prescribes to
   avoid a bootstrap gap, and it is why the two connections exist.
3. **Live.** Apply events as they arrive. Only from this point do transitions
   become eligible for notifications.
4. **Resync.** Every 5 minutes, take a fresh `session.snapshot` and replace the
   state. Notifications are suppressed for the resulting diff.
5. **Reconnect.** Losing the event connection means the state is no longer live,
   so it tears the cycle down and retries with exponential backoff (1 s doubling
   to a 30 s ceiling, with jitter), restarting from step 1 on success. A failure
   on the short-lived request connection only fails that one call; the next
   scheduled resync retries it.

## Menu bar

The status item renders an `NSAttributedString` of up to three segments —
`◉n` in red for blocked, `⣾n` in yellow for working, `✓n` in green for done —
omitting any segment whose count is zero. Idle agents are not counted in the menu
bar; they appear in the popover. When every agent is idle the item shows a single
grey glyph, so Kelpie does not compete for attention at rest — but it has to stay
legible. Rendered at `tertiaryLabelColor` it proved to be past restraint and into
invisibility against a busy menu bar, with no way to tell Kelpie was running at
all, so the resting glyph uses `secondaryLabelColor`.

Two measures keep the menu bar from shifting:

- Counts use `monospacedDigitSystemFont`, so 9 → 10 does not change the width.
- The spinner uses the eight braille frames `⣾⣽⣻⢿⡿⣟⣯⣷`, which are all the same
  width, so neighbouring menu bar items do not move while it turns.

The animation timer runs at 100 ms **only while at least one agent is working**
and stops at zero. This is the property that distinguishes Kelpie from what herdr
removed: the update cost is one process rewriting a few characters, independent of
pane count and of how many clients are attached to herdr.

When the system's Reduce Motion accessibility setting is on, the spinner is
replaced by a static glyph and the timer never starts.

## Popover

An `NSPopover` hosting a SwiftUI `AgentListView`, with sections ordered BLOCKED,
WORKING, DONE, IDLE. A section with no members is omitted along with its heading.
Each row shows the workspace label with `terminal_title_stripped` beneath it,
truncated to one line. Agent kind is deliberately not shown.

Clicking a row jumps to that pane.

The footer carries the connection state, a "Start at login" toggle, and Quit.
When herdr is not running the footer says so and shows the retry state, while the
status item falls back to the muted grey glyph.

Two conditional banners appear above the footer: a protocol mismatch warning, and
a hint when notification permission has been denied.

## Jump

Clicking a row (or a notification) sends `agent.focus` for that `pane_id`, then
brings the hosting terminal forward.

Finding the terminal, verified on this machine:

```
15272  herdr                                              ← TUI client
  └ 15156  bash
      └ 15154  /usr/bin/login
          └ 1381  /Applications/Ghostty.app/.../ghostty   ← activate this
15273  /opt/homebrew/bin/herdr server                     ← server, excluded by args
```

Enumerate processes whose executable is the herdr binary and whose arguments do
**not** include the `server` subcommand; those are TUI clients. Walk each one's
parent chain until reaching a process whose executable path lies inside
`.app/Contents/MacOS/`, then activate it with
`NSRunningApplication(processIdentifier:)`. No special entitlement is needed for
a non-sandboxed app inspecting the user's own processes.

If no client is attached, send `agent.focus` and skip activation — the correct
pane will be focused the next time herdr is opened. If several clients are
attached, v1 activates the first one found.

## Notifications

Kelpie posts a notification only when an agent transitions **into** `blocked`
from some other status. A pane that stays blocked across further updates does not
re-notify.

The critical rule: **transitions derived from bootstrap or from a periodic resync
never notify.** Without this, launching Kelpie — or herdr restarting — would fire
every currently-blocked agent at once. `SessionState` therefore distinguishes a
bootstrap application from a live one, and `notificationsToPost(for:phase:)`
returns nothing for the former.

The notification title is the workspace label and the body is the stripped
terminal title. Activating it performs the same jump as a popover row. When
authorization has been denied, the popover shows a hint rather than failing
silently.

herdr can also deliver its own notifications, so README will note that adjusting
`ui.toast.delivery` on the herdr side avoids duplicates.

## Start at login

`SMAppService.mainApp.register()` / `.unregister()`, surfaced as the single
toggle in the popover footer, with its state read back from
`SMAppService.mainApp.status`. A menu bar app that does not come back after a
reboot is not doing its job, and this needs no settings window.

## Error handling

The governing principle is that a menu bar app must not die.

- **herdr not running** is a normal state, not an error. Kelpie shows the muted
  glyph and keeps retrying on the backoff schedule.
- **Protocol mismatch** does not abort. Kelpie keeps running and shows a warning
  banner. Having the status app die because herdr was updated would be the worst
  possible behaviour.
- **Decoding is lenient.** Unknown JSON fields are ignored. An unrecognised
  `agent_status` is treated as `unknown`: the row still appears, but it is
  excluded from the counts.
- **Dropped events** are not chased. Each event is self-contained per pane, and
  the 5-minute resync repairs any divergence.

## Testing

`KelpieCoreTests` covers the logic that actually decides behaviour: that
replacing with a snapshot reports a status change even when `revision` has not
moved — the exact shape herdr emits when a `done` mark clears — and reports
nothing when nothing changed; count aggregation; grouping and ordering, including
the pane-id tiebreaker that keeps rows stable; the refresh coalescer's cap at the
replay burst's real cadence; and the notification rules — that bootstrap-derived
blocked states are silent, that a genuine transition into blocked fires exactly
once, and that staying blocked does not re-fire.

`KelpieClientTests` focuses on NDJSON framing against a fake transport: several
lines arriving in one read, a line split across reads, a very long line,
correlation of responses by `id`, subscription acknowledgement followed by
streamed events, and the backoff schedule.

The UI layer has no tests; it is kept thin enough that this is honest rather than
convenient. A manual verification checklist against a real herdr session goes in
the README.

## Build and distribution

XcodeGen generates `Kelpie.xcodeproj` from `project.yml`; the project file is
gitignored, matching `snaka/invixray`. A local SwiftPM package provides
`KelpieCore` and `KelpieClient` with their test targets.

Bundle identifier `com.snaka.kelpie`. `LSUIElement: true`. App sandbox **off** —
required to read `~/.config/herdr/herdr.sock`. Hardened runtime on.

There are **no third-party dependencies**. Foundation, AppKit, SwiftUI,
UserNotifications, and ServiceManagement cover everything, so no supply-chain
review is required.

Distribution is a `.dmg` on a GitHub Release plus a cask in
`snaka/homebrew-tap`, reusing the `release.yml` workflow already running in
`snaka/invixray` and `snaka/Bokashi` and the same Apple Developer assets.

**Every published build is signed with Developer ID and notarized, starting from
the first release.** Shipping unsigned is no longer viable: Homebrew removed
`--no-quarantine` (Homebrew/brew#20755, PR #20973), so cask installs carry the
quarantine attribute with no supported way to strip it; homebrew/cask requires
signed and notarized casks from 2026-09-01; macOS 15 removed the Control-click
Gatekeeper override in favour of a System Settings trip, and reports indicate
15.1 offers no override at all for unsigned apps; and an ad-hoc signature
(`CODE_SIGN_IDENTITY="-"`) is still not notarized, so it is blocked the same way
once quarantined. Ad-hoc signing remains fine for local development builds, which
never acquire the quarantine attribute.

## Deferred

Recorded in ROADMAP.md at implementation time, not built in v1:

- Named herdr sessions. v1 watches the default session only; the machine this was
  designed on has no named sessions.
- Choosing which client to activate when several are attached.
- Notifications for `done`.
- A settings window, if preferences ever outgrow the single login toggle.

## Risks

- **herdr wire protocol changes.** Contained to `KelpieClient` and degraded
  gracefully via the banner rather than a crash, but a breaking change still
  requires a Kelpie release.
- **The subscribe-time replay burst contradicts herdr's documentation**, which
  means it is unspecified behaviour that could change in either direction. The
  `revision` guard is correct whether the burst appears or not.
- **Terminal discovery is heuristic.** A herdr client started somewhere other
  than under a terminal app — over SSH, or from a launch agent — has no `.app`
  ancestor. Kelpie falls back to focusing without activating.
