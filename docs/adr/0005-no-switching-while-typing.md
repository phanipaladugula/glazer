# 0005. Keyboard focus follows typing, not just gaze

**Status:** Accepted

## Context

Glazer knows which display the user's head faces, not what they're paying attention to.
Some everyday moments look identical to "I want to type on that display":

- turning towards someone who sits or stands beyond the other display, to talk;
- typing on one display, by touch, while facing the other.

Moving keyboard focus whenever the head turns gets both wrong, and typing into the wrong
window is worse than not switching at all.

## Decision

Moving the pointer and moving keyboard focus are separate decisions, made by
`FocusPolicy`. There are three modes, chosen in Settings:

- **Automatic (default).** The pointer moves as soon as the user faces another display,
  which shows them Glazer is ready. Keyboard focus moves only on a *fresh start* of
  typing: the first keystroke after at least 1.5 s without typing. Keystrokes in an
  ongoing burst never move focus. That key is held for 60 ms while the new window becomes
  key, then delivered there.
- **Hold key.** Nothing moves unless Fn is held.
- **Immediate.** The pointer and focus move together, as before this decision.

Knowing when the user types needs a keyboard event tap. `KeyboardMonitor` reads only that
a key went down, its time, and whether Fn is held. It never reads which key or what was
typed, and stores nothing.

## Consequences

- Talking towards the other display moves at most the pointer, and it comes back when the
  user faces their display again.
- Typing while facing the other display stays in the window it started in.
- One case remains: stop typing, face the other display for a while, then start typing
  without looking back. The first keystroke switches. Hold key mode covers people for whom
  that's common.
- The event tap needs Accessibility access, which Glazer already asks for to raise windows.
  Without it, Glazer falls back to immediate mode and Settings says so.
- The privacy statement must describe the keyboard monitor precisely, and does.
