# Changelog

All notable changes to Glazer are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Keyboard focus follows when you start typing, not just when you look. The pointer moves
  to the display you face right away, but keyboard focus moves on your next keystroke after
  a pause, so talking to someone, or typing while you look elsewhere, never sends your
  typing to the wrong window.
- Settings › General › Keyboard follows: when I start typing (default), while I hold Fn,
  or right away.

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

[Unreleased]: https://github.com/phanipaladugula/glazer/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/phanipaladugula/glazer/releases/tag/v0.1.0
