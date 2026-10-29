# 0001. Follow head direction, not eye gaze

**Status:** Accepted

## Context

Glazer needs to know which display the user is looking at. Webcam eye tracking can
estimate a point on the screen, but its error is several centimetres, it drifts as
lighting and posture change, and it needs frequent recalibration. Dedicated eye trackers
fix this, but few people own one.

Glazer doesn't need a point. It needs to pick one of two or three displays, and those
displays sit at clearly different angles from the user's head.

## Decision

Glazer classifies **head direction** (yaw and pitch, from Apple's Vision framework) into
one of the calibrated displays. It doesn't track the eyes.

## Consequences

- Works with the built-in camera, in ordinary light, without special hardware.
- A short calibration (look at each display for a few seconds) is enough, and it stays
  valid until the displays are moved.
- Glancing at another display with the eyes alone, without turning the head, won't
  switch. Most people turn their head when they move between a laptop and a monitor, and
  a short dwell time means glances shouldn't switch anyway.
- Displays stacked very close together, with little head movement between them, will be
  harder to tell apart.
