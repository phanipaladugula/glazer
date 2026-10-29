# Changelog

All notable changes to Glazer are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Glazer never switches displays while you're typing. Keep typing while you look at
  notes or talk to someone, and your words stay where they are. Stop typing for a second
  while facing another display, and focus moves there, ready for you. Glazer only notes
  when a key is pressed, never which key.

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
