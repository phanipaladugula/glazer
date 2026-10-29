# Contributing to Glazer

Thanks for helping. This guide covers setting up, the standards the code follows, and
how changes get merged.

## Setup

You need macOS 15 or later and Swift 6.2 or later. Xcode works, but isn't required:

```sh
xcode-select --install   # Command Line Tools, if you don't have Xcode
git clone https://github.com/phanipaladugula/glazer.git
cd glazer
Scripts/test.sh          # run the tests
Scripts/lint.sh          # run the static checks CI runs
Scripts/bundle.sh --open # build dist/Glazer.app and launch it
swift run glazer-camera-check  # check the camera and head tracking live
```

To work in Xcode, open `Package.swift`.

## Where things go

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first. In short:

- **Decisions go in `GlazerCore`**, as plain types with unit tests. If logic needs a
  camera, a screen or AppKit to be tested, it's in the wrong place.
- **macOS APIs go in `GlazerSystem`**, in small adapters with as little logic as possible.
- **UI goes in `GlazerApp`**, and follows [the design spec](docs/design/README.md).
  Visible changes to the UI should update the spec too.

## Checks

CI runs four jobs on every pull request, and all must pass:

| Job | Checks | Run it yourself |
|---|---|---|
| Lint | ShellCheck, actionlint, Markdown links, the README figure matches its source | `Scripts/lint.sh` (install `shellcheck` and `actionlint` with Homebrew for every check) |
| Build and test | Formatting, debug and release builds with warnings as errors, tests, GlazerCore coverage of at least 95% | `Scripts/test.sh --warnings-as-errors --min-coverage 95` |
| Package and smoke test | The universal app, its signature, entitlements and icon, the installer test suite, and launching the app | `Scripts/bundle.sh --universal && Scripts/package.sh && Tests/Install/run.sh` |
| Release (dry run) | The release pipeline, on changes to packaging | Tag a release; see [docs/RELEASING.md](docs/RELEASING.md) |

## Standards

- Format with `Scripts/format.sh` before committing. CI runs `Scripts/format.sh --check`.
- Shell scripts source `Scripts/lib/common.sh` for strict mode, error reporting, logging and
  `--help`, and must pass ShellCheck. `install.sh` is the exception: it stands alone because
  it runs through `curl | bash`, and it must work with macOS's bash 3.2.
- Every change to `GlazerCore` comes with tests, written with Swift Testing.
- Public types and non-obvious functions get a doc comment that says what, not how.
- No third-party dependencies without discussing it in an issue first. A camera app has
  to be easy to audit.
- No force unwraps or `try!` outside tests.

## Commits and pull requests

- One logical change per commit. Write the subject in the imperative, under about 60
  characters ("Add display classifier"), and explain why in the body when it isn't
  obvious.
- Branch from `main`, and open a pull request. CI must pass before merging.
- Large changes start as an issue, so the approach can be agreed before the code is
  written.

## Releases

Maintainers release by pushing a version tag. See [docs/RELEASING.md](docs/RELEASING.md).

## Design decisions

Significant decisions are recorded in [docs/adr](docs/adr). If your change reverses or
adds one, add a record. Copy the format of the existing ones.
