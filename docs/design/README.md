# Design

Glazer lives in the menu bar. It has no Dock icon and no main window. Everything a person
needs day to day fits in one small panel. Three windows appear only when needed: setup on
first launch, face lock setup, and Settings. Calibration takes over every display for a
few seconds.

## Principles

1. **Native first.** Use system controls, system fonts, SF Symbols and system materials.
   Glazer should look like it shipped with macOS. No custom colour palette, no gradients,
   no emoji, no marketing copy.
2. **State at a glance.** Someone glancing at the menu bar can tell whether Glazer is
   watching. The panel shows which display is in focus without them reading anything.
3. **One primary action.** The on/off switch is the only prominent control. Everything
   else is secondary.
4. **Quiet when off.** When Glazer is off, the camera is off. The icon shows that clearly
   and the panel says so in plain words.

## App icon

"Focus hop": a MacBook and a monitor, with focus hopping along a glowing arc from the
MacBook to the monitor. The monitor is lit, and its window holds the focus ring. The
icon shows what Glazer does in one picture: focus follows you to the other display.

- **Source:** `Resources/Icon/AppIcon.svg`, on the macOS icon grid (an 824 pt rounded
  square on a 1024 pt canvas).
- **Colours:** a deep indigo tile lit from above, aluminium devices, and the same cyan to
  blue gradient for the lit screen that the README figure and the accent use.
- **Sizes:** it stays legible down to 16 px. The two devices and the lit screen are the
  parts that survive. The arc and the ring are details for larger sizes.
- **Build:** `Scripts/icon.sh` renders `Resources/Glazer.icns` and `docs/images/icon.png`.
  Both are committed, so building the app doesn't need Chrome.

The menu bar keeps the `eye` symbols below: a menu bar icon must be a small monochrome
template image, and the eye reads instantly at that size.

## Menu bar icon

| State | Symbol | Notes |
|---|---|---|
| On | `eye` | Template image, so it follows the menu bar's appearance |
| Off | `eye.slash` | Same weight and size, so the menu bar doesn't jump |
| Needs attention | `eye.trianglebadge.exclamationmark` | Not set up, camera blocked, not calibrated, or too dark |

The icon is the only thing Glazer shows in the menu bar, with no text beside it. Every
state and its copy is defined in one place, `ConditionPresentation`.

## Panel

Width 300 pt. It uses the standard `MenuBarExtra` window, so it gets the system material,
corner radius and shadow for free.

```
┌──────────────────────────────────────────┐
│  ◉  Glazer                        [ ●━ ] │  header: symbol, name, status, switch
│     Following your gaze                  │
├──────────────────────────────────────────┤
│   ┌──────────┐ ┌──────────────────┐      │  display map: the real arrangement
│   │          │ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│      │  from System Settings, to scale
│   └──────────┘ │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│      │
│    Built-in    └──────────────────┘      │
│                    LG ULTRAFINE          │
├──────────────────────────────────────────┤
│  Turn Off                        ⌥⌘G     │  menu-style rows
│  About Glazer                            │
│  Quit Glazer                      ⌘Q     │
└──────────────────────────────────────────┘
```

### Header

- The app symbol sits in a 26 pt circle filled with the accent colour when on, and
  `quaternary` fill when off.
- Name: `.headline`. Status: `.subheadline`, `.secondary`.
- Switch: a standard `Toggle` with `.switch` style and `.small` control size, trailing.

Status copy:

| State | Copy |
|---|---|
| Following | Following your gaze |
| No face in view | Looking for you |
| Too dark | Too dark to see you |
| Face lock, someone else | Face not recognised |
| One display | Waiting for a second display |
| Off | Off. Camera is not in use |

### Callout

When Glazer can't run because of something the person can fix, a card appears under the
header: one sentence on what's needed and one small prominent button that fixes it
("Set Up…", "Open Settings…", "Calibrate…"). It uses `.quinary` fill with a radius of
8 pt. There is never more than one callout.

### Display map

This is the panel's one piece of custom drawing, and it carries real information.

- Displays are drawn in their actual arrangement and relative size, taken from the
  system. If the person moves the LG to the left in System Settings, it moves here too.
- The map is 76 pt tall. Each display is a rounded rectangle (radius 3 pt) with a
  hairline `separator` stroke.
- The display with the menu bar has a thin white strip along its top edge, as in
  System Settings.
- The display in focus is filled with the accent colour. The others use `quaternary`.
- Each display's short name sits inside its tile in medium `.caption2`, as System
  Settings draws it, so a name can never land on a display stacked below. Every built-in
  panel is called "Built-in", which fits the small tile a laptop gets next to a large
  monitor. The focused display's name is white on the accent colour, the others
  `.secondary`.
- When Glazer is off, nothing is highlighted: the arrangement is still shown, but nothing
  is being followed.

Until gaze tracking ships, "in focus" means the display that holds the pointer.

### Rows

Rows look like `NSMenu` items: 22 pt tall, 13 pt system font, with a rounded selection
highlight (radius 5 pt, accent colour, white text) on hover. A keyboard shortcut is shown
trailing in `.secondary`. Rows only appear when they work. Glazer doesn't show
placeholders for features that haven't shipped yet.

Rows, in order: Turn On/Off (⌥⌘G), Calibrate Displays… (only when the camera is used),
Settings… (⌘,), then after a divider, About Glazer and Quit Glazer (⌘Q).

When switching by key only, the header badge and the menu bar show `keyboard` instead of
`eye`, and the status reads "Press fn twice to switch". Nothing suggests the camera is
watching when it isn't.

## Setup window

Shown on first launch, 560 × 520 pt with a hidden title bar. One idea per page:
welcome, how to switch, camera, Accessibility, calibration, face lock, done. Switching by
key only skips the camera, calibration and face lock pages, and the step dots count only
the pages that apply.

- "How do you want to switch?" offers three rows: Where I look, Double-pressing a key, and
  Both. Each row has a symbol, a title and one line of `.secondary` text; the selected
  row has a tinted fill, an accent hairline and a filled check. A key picker appears
  below once a key is involved.

- Each page has a 64 pt rounded-square badge in the accent colour with a white symbol,
  a 24 pt semibold title and one or two sentences in `.secondary`.
- Below that, at most one action: a large button, or a green confirmation once it's done.
- The footer has step dots on the left (the current one stretches into a pill), and Back
  and the primary button on the right.
- Optional steps say "Skip" or "Not Now" rather than disabling Continue. The camera is the
  only step that can't be skipped.

## Calibration

Calibration covers every display with a dark, blurred overlay, so nothing else competes
for attention.

- The display being calibrated shows a dot at its centre, then at each corner, 84 pt in
  from the edges so it clears the menu bar, the notch and the Dock. The user looks at
  the dot and clicks it (or presses Space). A white dot pulses until clicked; then it
  turns accent and a ring fills as poses are recorded.
- The words, "Display 1 of 2 · Dot 1 of 5" and "Look at the dot and click it", hang above
  the exact middle of the display and Cancel hangs below, so they never cover the centre
  dot. For a corner dot, a faint arrow in the middle points to it.
- The other displays dim further and show "Look at Built-in" with an arrow pointing
  toward it.
- Problems appear as a single yellow line under the middle: can't see you, too dark,
  hold still, turn to this display. They never interrupt the flow.
- The result appears on the display with the menu bar: a green check and "Done", or an
  explanation and "Try Again".
- Esc cancels at any point.

## Face lock setup

A 440 × 540 pt window modelled on Face ID setup.

- A 220 pt circle shows a mirrored live preview while scanning, and a `faceid` symbol
  before and after.
- 72 tick marks ring the circle and fill in the accent colour as the scan progresses.
- One instruction line updates as the scan goes: look at the camera, move closer, only
  one person, keep turning.
- Touch ID or the login password is asked for before the camera starts, and again before
  the face is deleted.

## Settings

A standard Settings window with grouped forms and five tabs: General, Displays, Face
Lock, Privacy and Diagnostics. Diagnostics shows live readings (faces in view, head yaw and
pitch, brightness, match score) so people can see what Glazer sees, without any image.

## Global shortcut

`⌥⌘G` turns Glazer on and off from anywhere. It is registered with the Carbon hot key API,
which needs no Accessibility permission.

## Copy

- Sentence case everywhere, except the product name.
- Say what is happening, not how it works. Write "Following your gaze", not
  "Head-pose tracking active".
- Never blame the person. Permission prompts explain what Glazer needs and why, in
  one sentence.
