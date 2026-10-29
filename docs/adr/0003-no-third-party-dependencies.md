# 0003. No third-party dependencies

**Status:** Accepted

## Context

Glazer has access to the camera and, later, the Accessibility API. People will only
trust it if they can check what it does. Every dependency is more code to audit and
another place where behaviour could change without notice.

## Decision

Glazer uses only Apple frameworks: SwiftUI, AppKit, AVFoundation, Vision, and Carbon for
global shortcuts. Adding a dependency needs an issue and a new decision record.

## Consequences

- The whole app can be read and audited in an afternoon.
- No supply chain risk from packages, and no network access needed to build.
- Some conveniences, such as a shortcut recorder, have to be written by hand.
