# Architecture

Glazer is a Swift package with three modules. Each one depends only on the modules below it.

```
GlazerApp      Menu bar UI, windows, overlays and app state (SwiftUI, AppKit)
   │
GlazerSystem   Thin adapters over macOS: camera, Vision, Keychain, focus, displays
   │
GlazerCore     Pure decision logic and value types. No AppKit, no hardware
```

## Principles

- **Decisions are pure.** The hard parts of Glazer are decisions: which face is the user,
  which display they face, and when a glance becomes a switch. These decisions live in
  `GlazerCore` as plain values with no clock, camera or UI, so every one of them is
  unit-tested with invented frames.
- **Adapters are thin.** `GlazerSystem` turns macOS into those values, and turns
  decisions back into actions. Each adapter does one job with little logic, so there is
  little in it to get wrong.
- **Everything stays on the Mac.** Nothing in the package imports networking APIs. Camera
  frames are analysed and dropped, and the face template lives only in the Keychain.
- **No third-party dependencies.** Only Apple frameworks, so the whole app can be audited
  ([ADR 0003](adr/0003-no-third-party-dependencies.md)).

## The pipeline

```
 Camera ──▶ FrameAnalyzer ──▶ Frame ──▶ GazeEngine ─────────────────────────────▶ Output
 (AVFoundation)  (Vision)      faces,     │                                   status, pose,
                               pose,      ├─ UserTracker      who is the user   focused display,
                               brightness ├─ HeadPoseFilter   steady angles     switch?
                                          ├─ DisplayClassifier which display        │
                                          └─ LightMeter        too dark?            ▼
                                                                          FocusController
                                                                          (pointer + window)
```

1. **CameraFeed** runs the camera at VGA and analyses at most 12 frames a second on a
   background queue.
2. **FrameAnalyzer** uses Vision to find faces, each face's yaw and pitch, and the frame's
   brightness. With face lock, it also computes a signature for the nearest three faces,
   but only when the tracker asks for one.
3. **UserTracker** picks the user: the nearest qualifying face, which is then followed by
   position. With face lock, a face must also match the enrolled template, and it is
   checked again every two seconds.
4. **HeadPoseFilter** smooths the angles with a One Euro filter: steady when still,
   responsive on a turn.
5. **DisplayClassifier** finds the nearest calibrated display. It switches only when that
   display is clearly nearer than the current one (by a margin) for long enough (the
   dwell), and it ignores poses far from every display.
6. **TypingGuard** holds a switch back while the user is typing, and lets it through once
   they've paused for a second ([ADR 0005](adr/0005-no-switching-while-typing.md)).
   **TypingMonitor** tells it when keys are pressed, never which keys.
7. **FocusController** focuses the frontmost window on the target display and returns the
   pointer to where it was there.

## Modules

### GlazerCore

| Area | Contents |
|---|---|
| `Vision/` | `HeadPose`, `Frame`, `DetectedFace` |
| `Tracking/` | `UserTracker`, `OneEuroFilter`, `HeadPoseFilter`, `LightMeter` |
| `Calibration/` | `Calibration`, `CalibrationRecorder`, `DisplayClassifier` |
| `Identity/` | `FaceSignature`, `FaceTemplate` (with its learned threshold), `IdentityVerifier`, `FaceEnrollment` |
| `Engine/` | `GazeEngine`, which ties the pipeline together, and `TypingGuard`, which holds switches back while the user types |
| `Display/` | `Display`, `DisplayLayout`, lookup by point |
| `Settings/` | `Preferences`: on/off, setup state, switch delay, calibration |
| `Models/` | `KeyboardShortcut` |

### GlazerSystem

| Area | Contents |
|---|---|
| `Camera/` | `CameraFeed`, `CameraAccess` |
| `Vision/` | `FrameAnalyzer` |
| `Security/` | `FaceVault` (Keychain), `OwnerAuthentication` (Touch ID or password) |
| `Focus/` | `FocusController`, `TypingMonitor`, `AccessibilityAccess` |
| `Display/` | `DisplayMonitor` |
| `HotKey/` | `HotKey`, a global shortcut through Carbon |
| `Login/` | `LaunchAtLogin` |
| `Support/` | `SystemSettings`, which opens Privacy & Security panes; `SessionMonitor`, which reports when the screen locks, sleeps or the user switches out |

### GlazerApp

| Area | Role |
|---|---|
| `AppModel.swift` | App state. Decides when the camera runs, and owns permissions, calibration and face lock |
| `Gaze/` | `GazeController`: runs the camera and the engine, and moves focus |
| `Calibration/` | Full-screen overlays and the calibration session |
| `FaceLock/` | Face lock setup, with a live camera preview |
| `Setup/` | The first-run setup window |
| `Settings/` | General, Displays, Face Lock, Privacy and Diagnostics tabs |
| `Views/` | Menu bar icon, panel, display map, and `ConditionPresentation` (every state's copy and icon) |

The interface follows the [design spec](design/README.md).

## When the camera runs

The camera is on only in three modes, all owned by `GazeController`:

| Mode | When |
|---|---|
| Following | Glazer is on, set up, has camera access, and is calibrated for two or more connected displays |
| Calibrating | During calibration |
| Enrolling | During face lock setup |

Otherwise the camera is off. With only one display connected, Glazer doesn't run the
camera at all.

## Threading

- Camera frames arrive on a serial background queue, and Vision runs there.
- Each `Frame` (a small `Sendable` value, never an image) is sent to the main actor.
- The engine, the app state and the UI all run on the main actor. At 12 frames a second
  the engine's work is negligible.

## Testing

| Target | Covers |
|---|---|
| `GlazerCoreTests` | Every decision: tracking, filtering, light, calibration, classification, the engine end to end, face signatures and enrolment, preferences |
| `GlazerSystemTests` | Frame analysis with real Vision on synthetic camera images |

Run `Scripts/test.sh`. It works with only the Command Line Tools installed.

## Tools

`glazer-camera-check` is a small command-line target that runs the real camera and Vision
code and prints the head angle live: `swift run glazer-camera-check`. Use it to check a
camera or a lighting setup without the app.

## Building without Xcode

The package builds with only the Command Line Tools ([ADR 0002](adr/0002-swift-package-without-xcode.md)).
`Scripts/bundle.sh` wraps the executable in `Glazer.app` with `Resources/Info.plist`, and
signs it with the hardened runtime and `Resources/Glazer.entitlements`, which declares the
camera. It signs with Glazer's signing identity when one is configured, so every build has
the same identity, and ad hoc otherwise ([Releasing › Signing](RELEASING.md#signing)).
