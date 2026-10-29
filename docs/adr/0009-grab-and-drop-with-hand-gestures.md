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
- **Only the user's hand counts.** A hand is the user's only if it's within three face
  widths beside the face, one and a half face heights above or two and a half below its
  middle, and its palm is 0.2–1.6 times the face's height. Measuring in the user's own face
  units keeps the rules the same near the camera and far from it, and rules out someone
  further back (too small) or beside the user (too far). Of the hands that qualify, the
  nearest to the face wins. The face is the one the engine follows, so with face lock on
  only the enrolled person's hand can count. With no face seen for two seconds, no hand
  counts.
- **Look only around the user, in detail.** Vision scales whatever image it's given to a
  fixed size, so hands are searched for in a crop around the user's face rather than the
  whole frame: a distant hand gets several times more detail, and hands elsewhere in the
  room aren't even looked at. The camera also runs at 1280×720 instead of 640×480 while
  gestures are on.
- Fingertips hidden behind the knuckles in a fist are still used at low confidence: Vision
  places them roughly right, which is all the measures need.

### Recognising the gesture

`GrabDetector` is a small state machine in GlazerCore, tested with drawn hands:

- **A grab** is an open hand (openness ≥ 0.7) followed within 0.8 s by a fist (≤ 0.3)
  that stays closed 0.25 s and moved less than 15% of the image while closing. A fist
  that wasn't just an open hand, or that moved, is ignored, and so is a fist that was
  already closed: that's the mug and the chin.
- **A drop** is the held fist opening past 0.6 for 0.15 s. Once a grab is held, any clear
  opening is the drop, so it doesn't wait for the fingers to spread fully, and its
  readings aren't smoothed, so it follows the hand without lag; the 0.15 s keeps one
  misread frame from dropping. A grab held 15 s, or with the hand out of view for 4 s, is
  cancelled. Grabs use readings smoothed over three frames, so one misread frame can't
  start one, and there's a 1 s pause after each drop.
- **Which display:** the one the hand was held towards when the gesture began (when the
  hand was last seen open, or started opening). During calibration the user holds their
  open hand towards each display in turn, and Glazer records where it is relative to the
  face. A hand is held towards a display when it's within three typical variations of
  that display's position and clearly nearer it than any other. Calibration refuses
  positions closer than four variations apart, and then gestures use the display the user
  faced instead, as they do whenever the hand's position isn't clear. Both come from a
  short history, because a raised hand often hides the face by the time the gesture is
  recognised.

### Acting on it

- **Grab:** a ScreenCaptureKit screenshot of that one display, without the pointer or
  Glazer's windows, saved as a PNG where macOS saves screenshots (named like macOS's
  own) and copied to the clipboard. The shutter sound plays if interface sounds are on,
  the display flashes unless Reduce Motion is on, and a thumbnail follows the user to
  whichever display they face.
- **Drop:** if the pointer is on the drop display and Accessibility says the element under
  it takes typing (a text field or area, or web content with an editable ancestor, never
  a password field), Glazer brings that window forward, clicks at the pointer and
  presses ⌘V, with V found in the current keyboard layout. Otherwise it shows the
  screenshot in a window of Glazer's own, in the middle of the drop display, with
  buttons to show it in Finder or open it in Preview. An earlier version opened it in
  Preview and moved Preview's window, which failed in use: Preview reopens a window where
  it last had one, which can be another display or one no longer connected, and the
  window has to be found through Accessibility before it can be moved. A window of
  Glazer's own goes exactly where it's put.
- **Off by default**, and only with the camera: gestures need Screen Recording, a
  permission Glazer otherwise never asks for.

## Consequences

- Gestures cost CPU only while on: each frame is larger and is searched for hands as
  well as faces.
- The clipboard holds the screenshot after a grab, as with macOS's own screenshot
  shortcuts, as a PNG only: a TIFF copy too would be uncompressed, about 33 MB for a 4K
  display, and apps that prefer TIFF would read all of it on every paste. A drop copies it
  again only if something else was copied meanwhile.
- **Pasting is prepared while the fist is held.** Every 0.4 s Glazer asks the app under
  the pointer to describe its content, so at the drop the text box is found at once, and
  it skips bringing the app forward when it already is. From the hand opening to ⌘V is
  then a few frames and about 50 ms. A large screenshot can still take the receiving app
  a moment to take in.
- Chromium and Electron apps are asked to describe their content to Accessibility, once
  each, so their text boxes can be found: Electron apps through `AXManualAccessibility`,
  Chromium browsers (Chrome, Edge, Brave, Arc and others, by bundle ID) through
  `AXEnhancedUserInterface`. They then do a little more work while they run, as they do
  for any assistive app. The enhanced interface is turned on only in those browsers,
  because in other apps it can slow window animations.
- Clicking to paste puts the caret where the pointer is, which is what the user pointed
  at. An app that ignores a first click in a background window gets it brought forward
  first.
- Screen Recording permission, like Accessibility, survives updates only because releases
  are signed with Glazer's own certificate. macOS may ask the user to quit and reopen
  Glazer after granting it, and recent versions of macOS remind users periodically that
  an app can record the screen.
- The thresholds were tuned on drawn hands and the measures' known geometry. Real-world
  tuning comes from `glazer-camera-check --hands` and the Diagnostics tab, which show the
  live openness, the display the hand is towards and how many other hands were ignored,
  and from the counts in calibration's trial.
- The camera can't see where a hand points, only where it is. Held towards displays that
  sit close together, the hand may be in much the same place for each; calibration says
  so, and the user's head decides.
