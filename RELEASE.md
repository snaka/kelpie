# Releasing Kelpie

The release pipeline lives in [`.github/workflows/release.yml`](.github/workflows/release.yml).
It signs, notarizes, packages a `.dmg`, publishes a GitHub Release, and bumps the
[`snaka/homebrew-tap`](https://github.com/snaka/homebrew-tap) formula.

## One-time setup

The Apple Developer assets are the **same account** already used by
`snaka/jubako`, `snaka/Bokashi`, and `snaka/invixray` — you can reuse the
certificate, Team ID, and app-specific password. They still have to be added
as repository secrets on `snaka/kelpie` (secrets are per-repo).

### 1. Apple Developer assets

- A **Developer ID Application** certificate, exported as a `.p12` from Keychain
  Access (right-click → Export) with a password.
- Your **Team ID** (10-char string, Apple Developer → Account → Membership).
- An **app-specific password** for `notarytool`
  ([appleid.apple.com](https://appleid.apple.com) → Sign-in and Security →
  App-Specific Passwords), e.g. labelled `kelpie-notarytool`.

### 2. GitHub PAT for the tap

A **fine-grained personal access token** restricted to `snaka/homebrew-tap`
with `Contents: Read and write`. The token jubako uses is scoped to the same
tap repo — if it is still valid you can reuse the value.

### 3. Add repository secrets to `snaka/kelpie`

`Settings → Secrets and variables → Actions → New repository secret`:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | `base64 -i cert.p12 \| pbcopy` and paste |
| `DEVELOPER_ID_CERT_PASSWORD` | The .p12 export password |
| `KEYCHAIN_PASSWORD` | Any random string (`openssl rand -hex 32`); only used for the temp keychain |
| `AC_USERNAME` | Your Apple ID email |
| `AC_PASSWORD` | The app-specific password from step 1 |
| `AC_TEAM_ID` | Your 10-char Team ID |
| `TAP_PUSH_TOKEN` | The fine-grained PAT from step 2 |

## Cutting a release

> **v0.1.0 is signed and notarized from the start.** Unlike `snaka/invixray`,
> there is no earlier unsigned manual zip to migrate away from — Kelpie's first
> published release already goes through this pipeline.

### Dry-run (recommended before the first real tag)

Actions tab → **Release** → **Run workflow** → enter a version like `0.1.0-dryrun`.
This builds, signs, notarizes, and creates the `.dmg`, uploads it as a workflow
**artifact**, and **skips** the GitHub Release + tap bump. Use it to validate
signing/notarization without polluting Releases or the tap.

### Real release

```bash
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

(Tags must be annotated — the repo has `tag.gpgSign = true` globally; lightweight
tags fail to sign.)

The workflow will:

1. Resolve version from the tag (`v0.1.0` → `0.1.0`).
2. Build a Release archive with `MARKETING_VERSION=0.1.0`.
3. Sign with Developer ID and notarize the `.app`.
4. Build a `.dmg`, notarize and staple it.
5. Create a GitHub Release with auto-generated notes, attach the `.dmg`.
6. Push an updated `Casks/kelpie.rb` to `snaka/homebrew-tap`.

After it succeeds, `brew install --cask snaka/tap/kelpie` should work.

## Manual verification

Kelpie's logic is covered by automated tests (`KelpieCore`/`KelpieClient`), but
two areas depend on OS-level state that exists only once Kelpie is installed as
a real, signed app bundle. No ad-hoc-signed development build can exercise
them, so they cannot be checked earlier in development. Run both against a
signed, installed build before considering a release verified.

### 1. Notification delivery and click-to-jump

An ad-hoc-signed build launched from `build/` cannot obtain notification
authorization at all: `requestAuthorization` throws `UNErrorDomain Code=1`
(`notificationsNotAllowed`), and `authorizationStatus` stays `.notDetermined`
forever.

The valuable part to check is the *silence* rules, since those are what keep
notifications worth reading:

- [ ] With an agent already blocked before Kelpie launches, start Kelpie and
      confirm **no** notification fires (bootstrap must be silent).
- [ ] With Kelpie already running, drive an agent into `blocked` and confirm
      **exactly one** notification fires.
- [ ] Click the notification and confirm it brings the terminal hosting herdr
      forward, focused on the blocked pane.
- [ ] Leave the agent blocked past a 5-minute resync and confirm the resync
      itself produces nothing — the only notifications in that window are the
      reminders below.
- [ ] Leave an agent blocked and confirm reminders arrive roughly one minute,
      six minutes and twenty-one minutes after it blocked, then every fifteen.
- [ ] Answer the blocked agent and confirm the reminders stop.
- [ ] With an agent already blocked before Kelpie launches, confirm **no**
      reminder fires for it either.
- [ ] With a Focus mode active and Kelpie in that mode's allowed apps, confirm
      a reminder breaks through rather than going straight to Notification
      Center. (Without the allow-list entry it will not.)
- [ ] After several reminders for one agent, confirm Notification Center holds
      a single row for it rather than one row per reminder.

### 2. Start at login

`SMAppService` refuses to register an app that is running from a build
directory — `SMAppService.mainApp.status` reads `.notFound` and the toggle has
no real effect. This can only be verified once Kelpie is installed to
`/Applications`.

- [ ] Toggle "Start at login" on in the popover footer.
- [ ] Confirm the registration with:
      ```bash
      sfltool dumpbtm | grep -i kelpie
      ```
- [ ] Toggle it off and confirm the entry disappears from `sfltool dumpbtm`.

### Other checks worth doing by hand

- [ ] Menu bar segments match the agent counts shown in the popover.
- [ ] Popover sections appear in BLOCKED, WORKING, DONE, IDLE order, and an
      empty section (and its heading) is omitted.
- [ ] Quitting herdr shows the resting dog icon and "herdr server not
      running — retrying" in the popover footer; restarting herdr recovers
      automatically without restarting Kelpie.
- [ ] With Reduce Motion enabled in System Settings, the working segment shows
      a static glyph instead of the animated spinner.

## Troubleshooting

- **`security: SecKeychainItemImport: error -25257`** — the `.p12` password in
  `DEVELOPER_ID_CERT_PASSWORD` is wrong.
- **`No identity found`** — the certificate didn't import cleanly. Verify the
  `.p12` contains both the cert and the private key.
- **Notarization rejected** — inspect with:
  ```bash
  xcrun notarytool log <submission-id> \
    --apple-id "$AC_USERNAME" --password "$AC_PASSWORD" --team-id "$AC_TEAM_ID"
  ```
  Common cause: missing hardened runtime, or signing with a non-Developer-ID
  identity. `ENABLE_HARDENED_RUNTIME` is already `YES` in `project.yml`.
- **Tap push fails with 403** — the PAT scope is wrong; it needs
  `Contents: Read and write` for `snaka/homebrew-tap`.
- **Package resolution errors in CI** — Kelpie's SwiftPM packages are local
  (`path: .`) with no remote dependencies, so there is nothing to resolve. If
  `xcodebuild archive` complains, regenerate the project with `xcodegen generate`.

## Future migrations

- Replace `AC_USERNAME` / `AC_PASSWORD` with an App Store Connect API key for
  `notarytool` (`--key` / `--key-id` / `--issuer`) once the project is mature.
- Consider an original drawn icon before a v1.0 release — the current icon
  composes a CC0 dog silhouette from Openclipart onto a green rounded rect.
  Regenerate it with `swift scripts/make-icon.swift` from the repository root;
  it writes all seven sizes into the asset catalogue directly.
