# 0005. Don't switch displays while the user is typing

**Status:** Accepted

## Context

Glazer knows which display the user's head faces, not what they're paying attention to.
The most harmful mistake it can make is moving focus while the user is typing, which sends
their words into the wrong window. That happens whenever they type on one display while
facing another: looking at notes, at a reference, or at someone they're talking to.

The first version of this decision added three modes: keyboard focus that moved on a
fresh start of typing (holding back and replaying the first keystroke), a hold-Fn mode,
and an immediate mode. In use, that was more machinery and more choice than the problem
needed, and intercepting keystrokes was the most fragile part of the app.

## Decision

Typing is a stronger signal than gaze. While the user types, focus stays where it is,
however their head turns. When they've stopped typing for about a second and face
another display, focus moves there, so it's ready before they type again.

- `TypingGuard` (GlazerCore) holds a switch back while keys are being pressed and releases
  it after a one-second pause. If the user faces the original display again first, the
  switch is dropped. It is a plain value, unit-tested with invented times.
- `TypingMonitor` (GlazerSystem) observes key presses with a read-only global event
  monitor. It reads only the time of each press: not which key, not what was typed. It
  can't block or change a keystroke, and stores nothing.

There is no setting. One behaviour, designed to be right.

## Consequences

- Typing while facing another display never moves focus.
- Glances during typing never move focus.
- After typing stops, facing another display moves focus as before. Turning to talk to
  someone near the other display moves focus there too. That's harmless, since the user
  isn't typing, and it moves back when they face their display again.
- macOS delivers other apps' key events only with Accessibility access, which Glazer
  already asks for to raise windows. Without it, Glazer sees no typing and switches as
  soon as the user faces another display.
- No keystrokes are intercepted, delayed or replayed.
