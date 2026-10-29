# 0006. Switch displays with a double-pressed key

**Status:** Superseded by [0008](0008-switch-with-a-keyboard-shortcut.md)

## Context

Following the user's head needs the camera, enough light, and a calibration. Some people
can't or don't want to meet those: a dark room, a video call that holds the camera, a
shared office, or simply preferring not to have a camera on. They still have the problem
Glazer solves: getting the pointer and keyboard to the other display without dragging.

[ADR 0005](0005-no-switching-while-typing.md) dropped a hold-fn mode, because it
intercepted keystrokes and was the most fragile part of the app. Any key feature has to
avoid that.

## Decision

The user chooses how to switch: where they look, double-pressing a key, or both.

- **The trigger is a double-press of one modifier key**: fn / 🌐 by default, or a
  right-hand ⌥, ⌘, ⌃ or ⇧. A modifier tapped on its own types nothing, and right-hand
  modifiers are rarely used in shortcuts. A double-press is deliberate: two taps, each
  shorter than 0.35 s, less than 0.4 s apart. Holding the key, or pressing any other key
  with it, cancels it, so ⌥-clicking or ⇧-typing never switches.
- **Each double-press moves to the next display in reading order**, top to bottom, then
  left to right, wrapping round. With two displays, it toggles.
- **`DoublePressDetector`** (GlazerCore) is a plain value fed key-down, key-up and
  other-key events with times, unit-tested with invented times.
  **`DoublePressMonitor`** (GlazerSystem) feeds it from read-only global and local event
  monitors for modifier changes and key presses. It reads only whether the chosen key went
  down or up and that another key was pressed, never which. It can't block or change a
  keystroke, and stores nothing.
- **Key only never runs the camera.** Camera access, calibration and face lock aren't
  asked for, and setup skips them. Accessibility is still needed: macOS delivers other
  apps' key events only with it, and moving keyboard focus needs it anyway.
- **Both** runs the camera and the key together. A double-press tells the engine the
  user moved focus themselves, exactly as moving the mouse does, so the camera doesn't
  pull focus straight back until they turn their head to another display. The key keeps
  working while the camera can't, such as in the dark.

## Consequences

- Glazer is useful without a camera, and a camera user gets an instant override.
- macOS can also use fn twice, for Dictation. Glazer can't see that setting, so Setup and
  Settings say so and offer other keys. Glazer doesn't stop macOS from also acting on the
  double-press.
- Event monitors only observe, so a double-press always reaches the frontmost app too.
  A lone modifier tap does nothing in almost every app, which is why only modifiers are
  offered.
