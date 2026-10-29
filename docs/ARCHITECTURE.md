# Architecture

Glazer is a Swift package with three modules. Each depends only on the ones below it.

```
GlazerApp      Menu bar UI and app lifecycle (SwiftUI)
   │
GlazerSystem   Adapters over macOS APIs: displays, hot keys, later camera and focus
   │
GlazerCore     Pure logic and value types. No AppKit, no hardware, fully unit-tested
```

## Why this split

The hard parts of Glazer are decisions: which face is the user, which display that face
is turned to, and when a glance becomes a switch. Those decisions live in `GlazerCore` as
plain functions over plain values, so they can be tested with recorded or invented data
and never need a camera, a second display or a person sitting in front of the Mac.

`GlazerSystem` turns macOS into those values (`NSScreen` into `Display`, camera frames
into head poses) and turns decisions back into actions (moving the pointer, focusing a
window). Each adapter stays thin, so there is little in it that can be wrong.

`GlazerApp` owns state and draws the UI. Views read from `AppModel` and never call
macOS APIs directly.

## Modules

### GlazerCore

| Area | Contents |
|---|---|
| `Display/` | `Display`, `DisplayLayout` (fits the arrangement into a drawing area), lookup by point |
| `Models/` | `KeyboardShortcut` |
| `Settings/` | `Preferences` over a `KeyValueStore` |

### GlazerSystem

| Area | Contents |
|---|---|
| `Display/` | `DisplayMonitor`: connected displays, and the display under the pointer |
| `HotKey/` | `HotKey`: a system-wide shortcut via Carbon, which needs no Accessibility permission |

### GlazerApp

| File | Role |
|---|---|
| `GlazerApp.swift` | Entry point. A `MenuBarExtra`, and no Dock icon |
| `AppModel.swift` | The on/off state, preferences and the toggle shortcut |
| `Views/` | The panel. See [the design spec](design/menu-bar.md) |

## The pipeline (planned)

These pieces arrive over the next milestones:

```
Camera ─frames─▶ FaceDetector ─faces─▶ UserTracker ─pose─▶ DisplayClassifier ─display─▶ FocusController
(System)         (System, Vision)      (Core)              (Core)                        (System)
```

- **UserTracker** picks the user from all faces in the frame: the largest face, followed
  from frame to frame, and ignored if it's much smaller than the calibrated size.
- **DisplayClassifier** maps head yaw and pitch to the nearest calibrated display, with
  hysteresis and a dwell time so a quick glance doesn't steal focus.
- **FocusController** remembers the last focused window on each display and restores it.

## Building without Xcode

The package builds with only the Command Line Tools. `Scripts/bundle.sh` wraps the
executable in an `.app` bundle with `Resources/Info.plist` and signs it ad hoc.
`Scripts/test.sh` adds the search paths Swift Testing needs when Xcode isn't installed.
