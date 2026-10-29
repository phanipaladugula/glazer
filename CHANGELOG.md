# Changelog

All notable changes to Glazer are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `swift run glazer-camera-check`, which shows your head's yaw live using Glazer's own
  camera code.
- Glazer never switches displays while you're typing. Keep typing while you look at
  notes or talk to someone, and your words stay where they are. Stop typing for a second
  while facing another display, and focus moves there, ready for you. Glazer only notes
  when a key is pressed, never which key.

### Changed

- The install script is much faster on networks that can't reach every GitHub download
  server: it moves on from an unreachable server within seconds instead of waiting up to
  a minute.
- The install script shows a small robot walking along a progress bar, replacing curl's
  progress output. Logs, CI and small terminals get plain step-by-step output.
- Clearer install errors: a release that doesn't exist is reported as such, not as a
  connection problem. Ctrl-C cancels cleanly without installing anything.
- Face lock is marked experimental. Its signatures now use the exact face box, its match
  threshold is learned across head angles, and it drops the user only after three failed
  checks in a row. Face lock needs setting up again.
- Setup explains that without Accessibility only the pointer moves, and the menu bar
  panel offers to fix it.

- CI runs lint, build and test, and package jobs in parallel: ShellCheck, actionlint,
  link checks, warnings as errors, a 95% coverage gate on the core logic, a 25-case
  installer test suite, and a launch smoke test.
- Developer scripts share a library for strict mode, error reporting and `--help`, and
  `Scripts/lint.sh` runs the same static checks as CI.

### Security

- The install script compares the checksum directly, checks the app is signed as Glazer
  (and, once releases have a signing identity, by Glazer's certificate), requires TLS 1.2,
  and refuses to run as root. Uninstalling also removes the face lock Keychain item.
- Face lock no longer silently turns off when its Keychain item can't be read (such as
  after choosing Deny); Glazer pauses and offers Try Again rather than following anyone.
- Focus never moves while a password is being typed in the frontmost app.
- Owner authentication fails closed unless the Mac has no login password, and the face
  lock item is updated in place.
- Builds can be signed with a stable identity (`Scripts/signing.sh`), so macOS keeps
  Keychain access and permissions across updates. Release builds run with a read-only
  token, publish from a separate job, and use actions pinned to commits.

### Fixed

- Typing could go to the display the user wasn't looking at. Without working
  Accessibility access, Glazer moved the pointer but asked macOS to activate the other
  app, which macOS ignores unless Glazer is the active app: true just after setup, and
  rarely after. Glazer now moves keyboard focus first, checks it moved, and only then
  moves the pointer. Without Accessibility it pauses and says so, and it resumes by
  itself once access is allowed.
- Displays stacked one above the other were told apart mostly by head turn, which shifts
  when the user moves in their chair, so focus could go to the wrong display. Head turn
  and tilt are now weighted by how the displays are actually arranged.

- macOS asked for Keychain access at every launch: the face lock item is now read only
  when it's needed, at most once per launch.
- Toggling Glazer quickly could leave the camera off while showing "Looking for you".
- Moving the pointer to another display by hand was undone a moment later.
- A switch held back while typing could fire after the user had turned back, and the
  display map showed it as focused while it was held.
- Granting Accessibility later now starts typing detection without a relaunch.
- Calibration shows when the camera stops, cancels if a display is connected or removed,
  and waits for the user to turn before recording the next display.
- "Open at login" shows what macOS actually did, and asks for approval when needed.
- "Camera unavailable" has a Try Again button, face lock's states each say what's
  happening, and setup can calibrate again.
- A display that was disconnected after calibration could still be chosen, warping the
  pointer to a corner.
- Closing the face lock window while Touch ID was showing could leave the camera running.
- The camera now recovers after it's disconnected or fails, rather than staying
  "unavailable" until relaunch.
- The camera now turns off while the screen is locked or asleep, or another user is
  switched in.
- Changing the switch delay no longer resets who Glazer is following.
- A switch blocked by a mouse drag is retried cleanly after the drag.
- The pointer on the top row of pixels no longer counts as off every display.
- Escape on "Calibration complete" keeps the calibration, and the camera turns off while
  the result is shown.

## [0.1.1] - 2026-10-29

### Added

- An app icon, shown in Finder, the Dock, Launchpad, About Glazer and the setup window.

## [0.1.0] - 2026-10-29

### Added

- Follows which display your head is facing, using the camera and Apple's Vision
  framework, and moves the pointer and keyboard focus there.
- Follows only the person at the Mac: the nearest face, held by position as others come
  and go.
- Face lock, which follows only the enrolled user. The face signature is kept in the
  Keychain, and setting it up or deleting it needs Touch ID.
- Calibration with full-screen overlays on every display.
- Ignores glances, with a configurable switch delay, and ignores looking away from every
  display.
- Low-light detection: Glazer pauses and says so when it's too dark to see you.
- First-run setup for permissions, calibration and face lock.
- Settings with General, Displays, Face Lock, Privacy and Diagnostics tabs.
- Launch at login.
- Menu bar app with an on/off switch, display map, status and global shortcut ⌥⌘G.
- Build scripts that produce `Glazer.app` with only the Command Line Tools.

### Changed

- Requires macOS 15 Sequoia or later.

[Unreleased]: https://github.com/phanipaladugula/glazer/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/phanipaladugula/glazer/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/phanipaladugula/glazer/releases/tag/v0.1.0
