# Roadmap

Work deliberately deferred from the v1 release, each with the reason it was
left out rather than an oversight.

- **Named herdr sessions.** v1 watches the default session's socket at
  `~/.config/herdr/herdr.sock` only. Named sessions live under
  `~/.config/herdr/sessions/<name>/herdr.sock` and would need discovery
  (enumerating that directory, presenting a chooser or a per-session menu)
  plus one connection pair — request and event — per session Kelpie watches.

- **Choosing which client to activate.** When several herdr clients are
  attached at once, `TerminalActivator` activates the first one it finds
  while walking the process list. Picking the "right" one — e.g. the client
  actually showing the target pane, or the most recently focused one — needs
  information Kelpie does not currently have a way to ask herdr for.

- **Notifications for `done`.** Deliberately omitted. Blocked is the state
  that needs you; adding a second notification-worthy status would make
  notifications frequent enough that they stop being worth reading, which is
  the property the current rules are built to protect.

- **Getting through a Focus mode without an allow-list entry.** Marking the
  notification `.timeSensitive` is the documented way past a Focus mode, but
  macOS honours that interruption level only for apps carrying
  `com.apple.developer.usernotifications.time-sensitive`. Measured on 0.1.4
  under the Sleep focus with a signed, notarized build: `usernoted` delivered
  and filed the notification and never presented it, exactly as without the
  level, so it was removed rather than left in as decoration. Earning the
  entitlement means adding the capability to the App ID and confirming a
  Developer ID build still signs and notarizes with it — worth doing only if
  adding Kelpie to a focus mode's allowed apps proves to be a real obstacle,
  which on one machine it is not.

- **A settings window.** Only if preferences ever outgrow the single
  "Start at login" toggle already in the popover footer. Adding a window for
  one boolean would be more surface than the feature deserves.

- **Re-reading Reduce Motion on the OS notification.** `AppCoordinator`
  currently reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
  only inside `refreshUI()`, which runs on state changes (connect, live
  events, resync) — not in response to
  `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`. Toggling
  Reduce Motion mid-session while agents are working therefore leaves the
  spinner animating (or static) until the next state change flips it, rather
  than reacting immediately. Low priority since the setting rarely changes
  while Kelpie is running, but worth fixing if it turns out to matter more in
  practice.

- **Notifications suppressed across a subscription rebuild.** When the pane
  set changes, the event connection is rebuilt through the reconnect path,
  which resets `SessionState` and applies the next snapshot as `.bootstrap` —
  so a pane that turned `blocked` inside that ~1 s window never notifies.
  Accepted for now because pane lifecycle changes are rare and the window is
  short; fixing it means carrying state across the rebuild, which reopens the
  stale-notification questions the reset exists to avoid.

- **A failed live-snapshot refresh waits for the next signal.** If the
  debounced `session.snapshot` after an event fails (observed once, transiently,
  while herdr was mid-replay), nothing retries it: the UI stays as it was until
  the next event or the 300 s resync. A bounded retry would close this, but the
  failure needs herdr up enough to accept subscriptions while failing requests,
  which has not been seen outside the replay burst.
