# Menu bar design

Glazer lives in the menu bar. It has no Dock icon and no main window. Everything a person
needs day to day fits in one small panel.

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

## Menu bar icon

| State | Symbol | Notes |
|---|---|---|
| On | `eye` | Template image, so it follows the menu bar's appearance |
| Off | `eye.slash` | Same weight and size, so the menu bar doesn't jump |

The icon is the only thing Glazer shows in the menu bar, with no text beside it.

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
| On | Following your gaze |
| Off | Off. Camera is not in use |

### Display map

This is the panel's one piece of custom drawing, and it carries real information.

- Displays are drawn in their actual arrangement and relative size, taken from the
  system. If the person moves the LG to the left in System Settings, it moves here too.
- The map is 56 pt tall. Each display is a rounded rectangle (radius 3 pt) with a
  hairline `separator` stroke.
- The display with the menu bar has a thin white strip along its top edge, as in
  System Settings.
- The display in focus is filled with the accent colour. The others use `quaternary`.
- Each display's short name sits under it in `.caption2`. Every built-in panel is called
  "Built-in", which fits under the small tile a laptop gets next to a large monitor. The focused display's name is `.primary`
  and the others are `.secondary`.
- When Glazer is off, nothing is highlighted: the arrangement is still shown, but nothing
  is being followed.

Until gaze tracking ships, "in focus" means the display that holds the pointer.

### Rows

Rows look like `NSMenu` items: 22 pt tall, 13 pt system font, with a rounded selection
highlight (radius 5 pt, accent colour, white text) on hover. A keyboard shortcut is shown
trailing in `.secondary`. Rows only appear when they work. Glazer doesn't show
placeholders for features that haven't shipped yet.

## Global shortcut

`⌥⌘G` turns Glazer on and off from anywhere. It is registered with the Carbon hot key API,
which needs no Accessibility permission.

## Copy

- Sentence case everywhere, except the product name.
- Say what is happening, not how it works. Write "Following your gaze", not
  "Head-pose tracking active".
- Never blame the person. Permission prompts explain what Glazer needs and why, in
  one sentence.
