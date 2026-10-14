# Alcove Recreation

An independent Swift/SwiftUI recreation of **Alcove 1.7.7** (`/Applications/Alcove.app`), the
macOS app that turns the notch into a Dynamic-Island-style surface. It was rebuilt from static
analysis of the shipped app with REA + Ghidra; no code, artwork, sounds or video from the
original is included, and its licensing/trial system is deliberately not reproduced.

## Build and run

Only the Command Line Tools are needed (no Xcode project):

```bash
Scripts/build-app.sh
```

```bash
open "build/Alcove Recreation.app"
```

The app is a menu-bar agent (no Dock icon). Permissions it may ask for: **Automation** (Spotify /
Music), **Calendar**, and **Accessibility** (only to replace the system volume/brightness HUD).
The build script signs with your Apple Development certificate when one is in the keychain, so
those grants survive rebuilds; with no certificate it falls back to ad-hoc signing and macOS
forgets them on every build.

URL scheme, handy for trying states without the hardware event:

```bash
open "alcove-recreation://preview/volume"
```

Other hosts: `expand`, `collapse`, `settings` (or `settings/<tab>`), `permissions`, and `preview/` + `brightness`, `charging`,
`low-battery`, `low-power`, `connectivity`, `focus`.

## What is recreated

| Area | Behaviour |
| --- | --- |
| Notch surface | Overlay panel per display; physical notch, 140 pt simulated notch, or 74 pt pill; hover lift, press, tap to expand, click-away to close |
| Gestures | Swipe down/up to open/close, down again to cycle Now Playing → Calendar → Duo, up to dismiss an activity, sideways to skip tracks, optional expand-on-hover |
| HUD notifications | Volume, brightness, charging, low battery, low power mode, audio device connected, Focus — each with its own duration/style options |
| Live activities | Now Playing (artwork + waveform, quick peek on track change), next calendar event countdown, lock |
| Stepping aside | Now Playing hides while its own player app is frontmost; the whole notch hides on a display showing something fullscreen (native fullscreen Space or a borderless window covering the screen) and, optionally, while a game is frontmost. Volume/brightness HUDs still appear while hidden |
| Expanded views | Media player (scrubber, transport, shuffle/repeat/favorite/copy-link slot), calendar week strip + agenda, Duo |
| Claude Code status | Optional (Settings → Developer): shows whether a Claude Code session is coding, finished or waiting for you, with plan-limit or context-window usage; not part of the original |
| Settings | Sidebar window with the original's tabs and option names, backed by the same `UserDefaults` keys and default values |
| Menu bar | Status item with About / Settings / Reset Onboarding / Quit; first-launch intro |

## Evidence behind it

Taken directly from the shipped binary and bundle (observed):

- **Settings model** — 134 `Defaults` keys with their types and default values, read out of the
  key-initializer functions (e.g. `batteryDuration` 5 s, `volumeDuration` 1.5 s,
  `lowBatteryThreshold` 10, `peekDuration` 2 s, `showOnDisplay` = main screen). Option enums and
  their case order come from the Swift reflection metadata.
- **Notch sizing** — the dimension routine: physical notch = screen width minus the two auxiliary
  top areas, tall as the top safe-area inset, expanding to `max(w + 160, 345) × max(h + 142, 175)`;
  simulated notch 140 wide expanding to 345 × 175; pill 74 wide expanding to 321 × 175.
- **Overlay window** — non-activating borderless panel, 624 × 320 anchored top-centre, clear,
  shadowless, joined to all Spaces / stationary / fullscreen-auxiliary, at the shielding window
  level, sharing type switched by "Hide from screen capture".
- **Architecture** — manager/controller/view names and stored properties (346 app types), the
  notification / live-activity / quick-peek state enums, Focus mode identifiers, lock and
  screensaver notification names, and all user-facing strings.

Design choices where the binary did not give a clean answer (inferred or mine): corner radii,
spring timings, side-slot widths, swipe thresholds, the settings window's visual styling, the
waveform's motion, and artwork colour extraction.

## Not recreated

- **System-wide Now Playing.** The original gets it from the private MediaRemote framework via
  an XPC helper signed with a `com.apple.*` bundle identifier. That identity trick was not
  reproduced; this build follows Spotify and Music through AppleScript and their distributed
  notifications instead, so browser and other-app playback is not shown.
- **Lock screen widgets**, which the original draws above the login window using private
  window-server Spaces. Lock state is tracked for the lock activity and sounds only.
- **Weather / time-to-leave** (WeatherKit needs a provisioned entitlement), **live audio
  waveform** (audio tap), **AirPods 3D models and battery levels**, **BetterDisplay integration**,
  **Mission Control hiding**, **progressive blur**.
- **Licensing and trial** — out of scope by intent. (The original's updater is replaced by the GitHub one below.)
- **Focus** is read from `~/Library/DoNotDisturb/DB/Assertions.json`, which needs Full Disk
  Access; the original streams the unified log through a private framework instead.

## Layout

```
Sources/AlcoveRecreation/
  App/        entry point, status item, manager → notch wiring
  Managers/   volume, brightness, battery, media, calendar, focus/lock/screen/media keys
  Notch/      panel + state machine, shape, collapsed-state views
  Views/      expanded media player and calendar, shared components
  Settings/   settings window, tabs, intro
  Support/    defaults keys and option enums, sounds, haptics
```

Note for the macOS 27 SDK: `@State` is now a macro whose compiler plugin ships only with Xcode,
so views use the small `@LocalState` wrapper (in `Views/Components.swift`) to stay buildable
with `swift build` alone.

## Claude Code status (Developer tab)

Not in the original. When enabled, the notch follows Claude Code sessions from the terminal and
from the Claude desktop app:

- **Status and tokens** come from the session transcripts in `~/.claude/projects/`.
- **Plan usage** (5-hour and 7-day percentages) comes from the copy Claude Code caches in
  `~/.claude.json`, so it is only as fresh as Claude Code's last check.
- **Permission prompts** leave no trace in a transcript until answered. The optional hook
  (Developer → Install Hook) adds one `Notification` hook to `~/.claude/settings.json` so they
  show as "Needs you"; other hooks are left alone and a backup is written beside the file.

Two diagnostics run without starting the app: `AlcoveRecreation --claude-status <transcript>`
prints how a transcript is read, and `--claude-hook-selftest <settings-copy> [install|uninstall]`
exercises the hook installer against a copy.

## Updates (GitHub Releases)

Not in the original. The app checks `https://api.github.com/repos/<owner>/<name>/releases/latest`
about once a day (and from the menu bar item or About tab), compares the tag with its own
version, and can download and install the release in place.

- Set the repository in `Resources/Info.plist` (`UpdateRepository`, `owner/name`), or for testing
  `defaults write local.alcove-recreation updateRepository owner/name`.
- `Scripts/release.sh [--publish]` builds `build/Alcove-Recreation-<version>.zip`; attach it to a
  release tagged `v<version>` (`--publish` does that with the GitHub CLI).
- Before swapping, the app checks the zip against GitHub's SHA-256 for the asset, that the bundle
  has the same identifier and the announced (newer) version, that its signature is valid, and that
  the team identifier matches the running app. Sign releases with the same certificate as the
  installed build; otherwise the update is refused and the Release Page button is the fallback.
- Installing hands off to a detached script that waits for the app to quit, replaces the bundle
  (keeping the old one until the copy succeeds), and reopens it. The folder holding the app must
  be writable by the user.
