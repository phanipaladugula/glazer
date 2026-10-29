# 0002. Build as a Swift package, without an Xcode project

**Status:** Accepted

## Context

Mac apps are usually built from an Xcode project. Xcode is a large download, its project
files are hard to review in pull requests, and it shouldn't be needed for a contributor to
fix a bug.

## Decision

Glazer is a Swift package. It builds with `swift build` using only the Command Line
Tools. `Scripts/bundle.sh` packages the executable into `Glazer.app` with
`Resources/Info.plist` and signs it ad hoc.

## Consequences

- Contributors need only `xcode-select --install`. Xcode users can still open
  `Package.swift`.
- The build is fully described by `Package.swift` and one script, both easy to review.
- App icons and other asset catalogs need a step in the bundle script rather than coming
  from Xcode.
- Swift Testing needs extra search paths when only the Command Line Tools are installed.
  `Scripts/test.sh` adds them.
