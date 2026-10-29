# 0007. Calibrate the centre and corners of each display

**Status:** Accepted

## Context

Calibration used to record one head pose per display, looking at its middle, and the
classifier chose the display whose middle was nearest. That works when the user faces
the middle of a display. It fails near the edge between two displays of different sizes:
looking at the near edge of a wide display is a smaller turn than looking at its middle,
so the middle of a narrow neighbour can be nearer. Focus then goes to the display the
user isn't looking at, which is the most visible mistake Glazer can make.

## Decision

Calibration records five poses per display: its centre, then each corner, clockwise from
the top left. Each one is recorded only when the user looks at a dot and clicks it (or
presses Space), so the user decides when they're on target; recording then takes about a
second while the dot's ring fills, and restarts if the head moves too much.

- **`PoseRegion`** (GlazerCore) is the convex hull of a display's poses, in yaw and
  pitch. Weighting the axes by the display arrangement (`AxisWeights`) keeps the hull
  convex, so distance to it is computed in weighted degrees: 0 on the region, otherwise
  the distance to its nearest edge.
- **`DisplayClassifier`** uses distance to each display's region, not to its middle.
  Where two regions overlap, the nearer centre decides which display is nearest, and the
  existing margin keeps focus where it is, so an ambiguous pose never causes a switch.
- **`Calibration.issue`** also flags a display whose centre lies on another display's
  region, as well as centres that are too close together.
- Calibrations stored by Glazer 0.1 have no spot recorded. They decode as centre-only
  and keep working, with regions that are single points, which is exactly the old
  behaviour. Settings shows "Centre only" and suggests calibrating again.

## Consequences

- Facing anywhere on a display, its edges included, counts as facing it.
- Calibration takes about half a minute instead of ten seconds, and needs ten clicks for
  two displays.
- Glazer still follows the head, not the eyes ([ADR 0001](0001-head-direction-not-eye-tracking.md)).
  The corners teach it how far the user's head turns to reach each edge; glancing at a
  corner with the eyes alone still doesn't move the head, which is why the overlay asks
  the user to turn their head to each dot.
