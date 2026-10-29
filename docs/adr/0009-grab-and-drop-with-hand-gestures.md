# 0009. Grab and drop screenshots with hand gestures

**Status:** Accepted.

## Context

Glazer already knows which display the user faces. Users asked to move what's on one
display to another with a gesture: close a hand facing one display, open it facing
another, as some phones do between devices.

The hard part isn't seeing a hand. Apple's Vision framework finds the 21 joints of a hand
(`VNDetectHumanHandPoseRequest`), on this Mac in about the time it takes to find faces.
The hard part is never acting on a hand that wasn't meant as a gesture: a hand holding a
mug, a chin on a fist, someone reaching for the mouse. A screenshot nobody asked for is
the worst failure, so the design leans towards missing a gesture over inventing one.

## Decision

### Reading a hand

- **Three scale-free measures** of each hand: how far the fingertips reach from the wrist
  in palm lengths, how much the fingers bend at their two upper joints, and how far the
  tips are from the middle of the palm. Each fails differently: a fist seen from the side
  still bends, and an open hand tilted away still reaches. The thumb is left out; it
  moves much the same in both shapes.
- **Per-user calibration.** The user shows an open hand and a fist, twice each. Every
  later reading is placed on the line between their own two shapes, each measure weighted
  by how steady it was for them, giving an openness from 0 (their fist) to 1 (their open
  hand). A calibration whose two shapes are less than four typical variations apart is
  refused, with advice (more light, hand closer). After calibrating, the user tries a
  grab and a drop before saving.
- **The biggest hand wins**, and a palm smaller than 4% of the image height is ignored, so
  someone further back can't take screenshots.
- **1280×720 while gestures are on**, instead of 640×480: a hand at arm's length is only a
  few dozen pixels across at VGA.
- Fingertips hidden behind the knuckles in a fist are still used at low confidence: Vision
  places them roughly right, which is all the measures need.

### Recognising the gesture

`GrabDetector` is a small state machine in GlazerCore, tested with drawn hands:

- **A grab** is an open hand (openness ≥ 0.7) followed within 0.8 s by a fist (≤ 0.3)
  that stays closed 0.25 s and moved less than 15% of the image while closing. A fist
  that wasn't just an open hand, or that moved, is ignored, and so is a fist that was
  already closed: that's the mug and the chin.
- **A drop** is the fist opening for 0.2 s. A grab held 15 s, or with the hand out of view
  for 4 s, is cancelled. Readings are smoothed over three frames, so one misread frame
  can't start or end anything, and there's a 1 s pause after each drop.
- **Which display:** the one faced when the gesture began (when the hand was last seen
  open, or started opening), from a short `DisplayHistory`. A raised hand often hides the
  face by the time the gesture is recognised.

### Acting on it

- **Grab:** a ScreenCaptureKit screenshot of that one display, without the pointer or
  Glazer's windows, saved as a PNG where macOS saves screenshots (named like macOS's
  own) and copied to the clipboard. The shutter sound plays if interface sounds are on,
  the display flashes unless Reduce Motion is on, and a thumbnail follows the user to
  whichever display they face.
- **Drop:** if the pointer is on the drop display and Accessibility says the element under
  it takes typing (a text field or area, or web content with an editable ancestor, never
  a password field), Glazer brings that window forward, clicks at the pointer and
  presses ⌘V, with V found in the current keyboard layout. Otherwise it opens the
  screenshot in the default app for PNGs and moves that window, shrunk to fit if needed,
  to the middle of the drop display. It finds the window by the document it reports, or
  the app's focused window, never by title.
- **Off by default**, and only with the camera: gestures need Screen Recording, a
  permission Glazer otherwise never asks for.

## Consequences

- Gestures cost CPU only while on: each frame is larger and is searched for hands as
  well as faces.
- The clipboard holds the screenshot after a grab, as with macOS's own screenshot
  shortcuts. A drop copies it again first, in case something else was copied meanwhile.
- Chromium and Electron apps are asked to build their accessibility tree
  (`AXManualAccessibility`), once each, so their text boxes can be found. They then do a
  little more work while they run, as they do for any assistive app.
- Clicking to paste puts the caret where the pointer is, which is what the user pointed
  at. An app that ignores a first click in a background window gets it brought forward
  first.
- Screen Recording permission, like Accessibility, survives updates only because releases
  are signed with Glazer's own certificate. macOS may ask the user to quit and reopen
  Glazer after granting it, and recent versions of macOS remind users periodically that
  an app can record the screen.
- The thresholds were tuned on drawn hands and the measures' known geometry. Real-world
  tuning comes from `glazer-camera-check --hands` and the Diagnostics tab, which show the
  live openness.
