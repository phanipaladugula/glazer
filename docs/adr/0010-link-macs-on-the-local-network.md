# 0010. Link Macs on the local network

**Status:** Accepted.

## Context

Glazer moves the pointer and keyboard between the displays of one Mac, and hand gestures
move a screenshot between them ([ADR 0009](0009-grab-and-drop-with-hand-gestures.md)).
Many people work with two Macs side by side, say a laptop and a desktop. They want the
same things across the Macs: look at the other Mac and type there with the keyboard in
front of them, and grab a screenshot on one Mac and drop it on the other.

That brings in a network for the first time. Glazer has promised never to connect to the
internet, and its users trust it with a camera, so the bar is high: nothing leaves the
local network, nothing happens between Macs the user didn't pair on purpose, and
everything between them is encrypted.

## Decision

Two features stay separate and each can be used alone: **displays** (today's Glazer, one
Mac) and **linked Macs** (this record). Linking is off until the user turns it on.

### Pairing: a code shown on both Macs

- Macs find each other with Bonjour (`_glazer._tcp`), only on the local network. The TXT
  record carries a random device ID and the Mac's name, nothing else.
- To pair, the user picks the other Mac on one of them. **Both Macs then show the same
  six-digit code**, and the user confirms on each that the codes match. This is numeric
  comparison, as in Bluetooth pairing, and it's chosen over typing a code from one Mac
  into the other: a typed six-digit code needs a password-authenticated key exchange
  (PAKE) to be safe against someone recording the exchange and trying all million codes
  offline, CryptoKit has none, and Glazer takes no third-party dependencies
  ([ADR 0003](0003-no-third-party-dependencies.md)).
- The exchange: the Mac that starts commits to a fresh Curve25519 key by sending its hash,
  the other replies with its key, and the first reveals its own. Both derive the shared
  secret and, from it and every message of the exchange, the code. Because the first
  Mac committed before seeing the other's key, a machine in the middle can't choose keys
  that make the two codes match; its only chance is a one-in-a-million guess, live.
- Once both users confirm, each Mac proves it with a MAC over the exchange, and both keep
  a 256-bit key derived from the shared secret, in the Keychain, for that one peer.
  Unpairing on either Mac deletes it there and tells the other.

### The link: TLS with the paired key

- Paired Macs connect over TCP with TLS, keyed by the pairing key (TLS pre-shared key,
  the same Network framework setup Apple's own peer-to-peer sample uses). A Mac that
  doesn't hold the key can't connect, read or inject anything.
- Messages are length-prefixed frames: a small JSON header, then raw bytes such as a
  PNG. Frames over 64 MB are refused.
- Each side sends a heartbeat every second and drops a link that's been silent for five,
  then reconnects as soon as Bonjour sees the peer again.

### Which Mac the user faces

Each Mac already knows how far the user's head is from the region of each of its
calibrated displays (ADR 0007). A Mac counts as **faced** when the user's head is within
a few degrees of one of its display regions, and it tells its linked Macs whether it's
faced, and how squarely, every time that changes and with each heartbeat. Every Mac
runs the same rule, `LinkArbiter`, on the same reports:

- If this Mac is faced, the user is at this Mac.
- Otherwise, the linked Mac reporting the squarest face, if any, recently, wins after a
  short dwell, so a glance doesn't count.
- If no Mac is faced, such as when the user looks at a phone, nothing changes.

Each Mac calibrates only its own displays, with its own camera, which sees the user
straight on when they look at it. No Mac has to be calibrated against another, and a
laptop with one display can be linked.

### Keyboard and mouse

When the user faces a linked Mac and types or moves the mouse on this one, this Mac
**forwards** its keyboard and mouse to that Mac, which replays them. When they face this
Mac again, forwarding stops. The Mac whose keyboard is in use decides, so either Mac's
keyboard drives whichever Mac the user looks at.

- An event tap (which needs the Accessibility permission Glazer already has) takes the
  events and doesn't pass them on locally. The local pointer is held still while
  forwarding; the other Mac moves its own pointer by the same amounts.
- Keys are sent by key code, so the other Mac's keyboard layout applies, as with
  Universal Control.
- Switching is held back while a key or button is down, and until the user pauses
  typing, so a word never splits between Macs (ADR 0005).
- When forwarding stops for any reason, a lost link included, every key and button held
  on the other Mac is released, so nothing sticks.
- Glazer's own on/off shortcut, ⌥⌘G, is never forwarded: it always turns Glazer off on
  this Mac, which also stops forwarding.
- Events Glazer replays are marked, and a Mac never forwards events it replayed itself,
  so two Macs can't bounce input between them.

### Clipboard

When control moves to another Mac, the clipboard goes with it: text, rich text and
images up to 20 MB. When control comes back, the other Mac's clipboard comes back, if it
changed. Files are not sent.

### Screenshots between Macs

A grab works as on one Mac, on the Mac whose camera sees it. That Mac tells its linked
Macs it holds a screenshot. When the hand opens:

- if the user faces a linked Mac, the screenshot goes there, and that Mac pastes it or
  shows it, exactly as a local drop would;
- the linked Mac being faced also watches for the open hand with its own camera, and
  claims the screenshot when it sees it. Whichever happens first wins; the screenshot is
  sent once.

### Permissions

macOS asks once for **Local Network** access. Nothing else is new: Accessibility,
already granted, covers both taking and replaying input.

## Consequences

- Glazer now uses the network, but only the local one: Bonjour, and TLS connections to
  paired Macs. It still never contacts the internet. The privacy statement says so.
- A paired Mac can type and click on this Mac while it's linked and the user faces it.
  That's the feature, and it's why pairing needs the user at both Macs, why the code is
  confirmed on both, and why linking and control can each be turned off.
- TLS with a pre-shared key has no forward secrecy: someone who later steals a pairing key
  from the Keychain could read recorded traffic. Unpairing and pairing again replaces the
  key. A future version could add an ephemeral key exchange inside the link.
- Both Macs need Glazer running with the camera, and calibrated. Without a camera on a
  Mac, it can't report being faced, and it's only ever controlled by the shortcut.
- Replayed input can't type into another Mac's password fields when that Mac turns on
  Secure Event Input, as with Universal Control.
- None of this can be tested end to end on one Mac. Pairing, the link and every message
  are tested over the loopback interface; forwarding and replay need two Macs.
