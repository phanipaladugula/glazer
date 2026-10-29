# Privacy

Glazer uses your camera. This page says exactly what it does with it. Every statement here
can be checked in the source code.

## Summary

- Everything happens on your Mac. Glazer makes **no network requests** of any kind.
- Camera frames are analysed and **discarded immediately**. Nothing is recorded or saved.
- The camera runs **only when needed**, and the camera light always shows when it does.
- Face lock keeps a **face signature, not a photo**, in your Keychain, and only if you set it up.
- With hand gestures on, Glazer takes a **screenshot only when you grab one**, and saves it
  where macOS saves your own.

## The camera

When Glazer is on, set to follow where you look, has two or more displays to choose
between, and has been set up, it reads up to 12 frames a second from the camera. Each frame is analysed on your Mac with
Apple's Vision framework, which reports:

- where each face is in the image, and how confident it is that it's a face;
- which way each face is turned (yaw and pitch);
- with face lock on, a face signature for up to three faces, only when Glazer needs to check who is in view;
- the frame's average brightness;
- with hand gestures on, where the joints of the nearest hand are, reduced straight away
  to three numbers that say how open it is.

The frame is then dropped. Only the numbers above are kept, and only until the next frame.

The camera also runs while you calibrate, while you set up face lock and while you
calibrate your hand for gestures. During face lock setup and hand calibration, a live
preview is shown in the setup window. It is shown on screen only and never recorded.

While hand gestures are on, the camera reads 1280×720 frames instead of 640×480, because
hands are smaller than faces in the image. The frames are handled exactly as above.

The camera is **off** when the screen is locked or asleep, when another user is
switched in, when Glazer is turned off, when only one display is connected, when
setup isn't finished, and whenever Glazer is set to switch by key only. The green camera light is controlled by macOS, not by Glazer,
so it always tells you the truth.

## The keyboard

So that it never switches displays while you're typing, Glazer notices when you press a
key. It uses a read-only macOS event monitor, which needs Accessibility access.

From each key press it reads only **the time**. It never reads which key you pressed or
what you typed, it can't block or change a keystroke, and it stores nothing. The code is
in `Sources/GlazerSystem/Focus/TypingMonitor.swift`.

If you switch displays with a keyboard shortcut, Glazer registers it with macOS, and macOS
tells Glazer when it's pressed. Glazer doesn't watch the keyboard for it at all. The code
is in `Sources/GlazerSystem/HotKey`.

## Hand gestures and your screen

Hand gestures are off unless you turn them on in **Settings › Gestures**. With them on:

- **A grab takes one screenshot** of the display you face, with ScreenCaptureKit. Glazer
  saves it as a PNG in the folder macOS uses for screenshots (the Desktop unless you
  changed it) and copies it to the clipboard, as macOS's own screenshot shortcuts do. It
  never captures the screen at any other time, and never sends a screenshot anywhere.
- **A drop** asks macOS, through Accessibility, what kind of element is under the pointer
  (a text field, say), and nothing else about it. If it takes typing, Glazer clicks there
  and presses ⌘V. Password fields are never pasted into. Chrome, Slack, VS Code and other
  apps built on Chromium describe their content only once an assistive app asks, so
  Glazer asks them, once each.
- **Otherwise the screenshot opens** in your usual app for images, and Glazer moves its
  window to the display you face. It recognises the window by the file it reports, not by
  its title.

Your screenshots are yours: Glazer doesn't keep a list of them or delete them.

## What Glazer stores

| What | Where | Contains |
|---|---|---|
| Settings | User defaults (`io.github.phanipaladugula.glazer`) | On/off, setup done, how you switch and with which shortcut, switch delay, the head angles calibrated at the centre and corners of each display, whether hand gestures are on, and your hand calibration: six numbers for your open hand and fist, and how much they vary |
| Screenshots you grab | Your screenshots folder, and the clipboard | The screen of the display you faced when you grabbed |
| Face lock template | Your login Keychain, item "Glazer face lock" | Face signatures from setup, and the match threshold learned from them |

The face lock template is biometric data, so it gets extra protection:

- It is a list of numbers computed by Vision, never a photo. It can't simply be turned
  back into an image. Research has shown rough reconstructions are sometimes possible,
  which is why it gets the protections below.
- It lives only in your login keychain, which macOS encrypts with your login password and
  never syncs to iCloud. Like the rest of your keychain, it is included in your own
  encrypted Time Machine backups.
- macOS lets only Glazer read it without asking you. Any other app has to ask, and Glazer
  itself asks too after an update unless the update is signed with the same identity.
- In Glazer, setting it up and deleting it need Touch ID or your login password. That
  stops someone at your unlocked Mac from swapping in their own face through Glazer. It
  isn't a lock on the item itself: you, or anyone at your unlocked Mac, can still delete
  it in Keychain Access.
- Glazer reads it only when it starts following you, not at every launch.
- It never leaves your Mac and is never sent anywhere.

## What Glazer never does

- Record, save or upload video or photos, or take a screenshot you didn't grab.
- Connect to the internet. There is no analytics, crash reporting, update check or
  telemetry.
- Read which keys you press or what you type.
- Read window titles. To find the window to focus, Glazer reads only window positions and
  which app owns them. Apart from a screenshot you grab, it never sees what's on your
  screen.
- Identify who you are. Face lock only checks whether the face in view matches the one
  enrolled on this Mac.

## Permissions

| Permission | Why | Without it |
|---|---|---|
| Camera | To see which display you're facing. Not needed to switch by key only | Glazer can only switch by key |
| Accessibility | To bring the window you last used on a display to the front, and to know when you're typing | Glazer pauses, since it could otherwise move the pointer but send your typing to the other display |
| Touch ID or password | To confirm it's you before face lock is set up or deleted in Glazer | Face lock can't be set up |
| Keychain access | macOS asks when an app reads the face lock item. Choose **Always Allow** | Face lock pauses Glazer until allowed |
| Screen Recording | Only for hand gestures, to take the screenshot you grab. Asked for when you turn gestures on | Gestures stay off |

## Removing everything

1. Run the uninstall command, which removes the app, its settings, its permissions and the
   face lock item. Or, in **Settings › Face Lock**, choose **Delete Face…**, or delete the
   "Glazer face lock" item in Keychain Access.
2. Remove settings and permissions:

   ```sh
   defaults delete io.github.phanipaladugula.glazer
   tccutil reset All io.github.phanipaladugula.glazer
   ```

3. Delete `Glazer.app`.

## Checking these claims

Camera access lives in `Sources/GlazerSystem/Camera` and `Sources/GlazerSystem/Vision`.
Keyboard monitoring is in `Sources/GlazerSystem/Focus`, and shortcuts in
`Sources/GlazerSystem/HotKey`.
Keychain storage is in `Sources/GlazerSystem/Security`. Nothing in the package imports
networking APIs. You can check with:

```sh
grep -rnE "URLSession|Network|NWConnection|CFSocket" Sources
```

It finds nothing. The Privacy tab's link to this page hands the address to your browser;
Glazer itself never connects.
