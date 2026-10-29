# 0008. Switch displays with a keyboard shortcut

**Status:** Accepted. Supersedes [0006](0006-switch-with-a-double-pressed-key.md).

## Context

Glazer 0.2.0 switched displays on a double-press of one modifier key, fn or a right-hand
⌥, ⌘, ⌃ or ⇧ ([ADR 0006](0006-switch-with-a-double-pressed-key.md)). In use, macOS and
other apps already claim those double-presses: fn twice starts Dictation, ⌃ or ⌘ twice can
start Dictation or Siri, and launchers and accessibility tools bind modifier double-taps
too. An event monitor only observes, so one double-press did two things, and Glazer
couldn't tell when that happened.

## Decision

Switch with an ordinary keyboard shortcut, registered with macOS, that the user can
change.

- **The default is ⌃⌥⌘Space.** macOS doesn't use it, and common window managers don't
  either. ⌃⌥⌘→ reads better, but Rectangle uses it for exactly this.
- **The user can record another** in Setup or Settings: a letter, digit, arrow or Space
  with at least two of ⌃, ⌥ and ⌘. One modifier would take over shortcuts apps use every
  day, such as ⌘K, or typing, such as ⌥E. The on/off shortcut, ⌥⌘G, is refused.
- **A shortcut that's taken is refused, not shared.** Before registering, `HotKey` checks
  macOS's own enabled shortcuts (`CopySymbolicHotKeys`), and registers with
  `kEventHotKeyExclusive`, which fails if another app holds it. Glazer then says which, in
  Settings and, when it switches only by shortcut, in the menu bar panel.
- **macOS delivers the press.** A Carbon hot key needs no event monitor: Glazer doesn't
  watch the keyboard for it at all, and the key press doesn't reach the frontmost app.
  `DoublePressMonitor` and `DoublePressDetector` are removed.
- Settings from 0.2.0 carry over: "switch by double-press" becomes "switch by shortcut",
  with the default shortcut.

## Consequences

- One press always does exactly one thing.
- Glazer reads less of the keyboard than before.
- A three-key chord is less effortless than a double-tap. Users who want something quicker
  can record any two-modifier shortcut that's free on their Mac.
- macOS shortcuts the user turns on later, or apps that register after Glazer, aren't
  rechecked until Glazer registers the shortcut again, such as after a restart.
