# Releasing

Releases are built and published by GitHub Actions ([release.yml](../.github/workflows/release.yml))
when a version tag is pushed. Nothing is built on a maintainer's Mac.

## Steps

1. **Update the changelog.** In `CHANGELOG.md`, move the entries under `[Unreleased]`
   into a new section, `## [X.Y.Z] - YYYY-MM-DD`, and update the links at the bottom.
   The release notes are taken from this section, and the release fails without it.
2. **Merge it to `main`** through a pull request.
3. **Tag `main` and push the tag:**

   ```sh
   git switch main && git pull
   git tag -a vX.Y.Z -m "Glazer X.Y.Z"
   git push origin vX.Y.Z
   ```

4. **Watch the Release workflow.** It:
   - runs the tests;
   - builds a universal app (Apple silicon and Intel) with `Scripts/bundle.sh --universal`;
   - packages `Glazer.zip` and `Glazer.zip.sha256` with `Scripts/package.sh`;
   - checks the architectures, the code signature and the camera entitlement, installs
     the package with `install.sh` into a scratch folder, and checks the app's version
     matches the tag;
   - publishes the release with notes from `Scripts/release-notes.sh`.
5. **Check the install command** on a Mac:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/phanipaladugula/glazer/main/install.sh | bash
   ```

## Versioning

Glazer follows [Semantic Versioning](https://semver.org/). The app's version comes from the
latest tag, and its build number from the commit count, so neither is edited by hand.

## Signing

Releases are signed ad hoc with the hardened runtime and the camera entitlement. Without an
Apple Developer ID:

- `install.sh` installs without Gatekeeper warnings, because `curl` doesn't quarantine
  downloads.
- A zip downloaded in a browser needs a right-click › **Open** the first time.
- macOS treats each version as a new app, so people allow the camera and Accessibility
  again after an update.

Developer ID signing and notarisation would remove all three. They need a paid Apple
Developer account, and secrets for the certificate and a notarisation key in the
repository settings.
