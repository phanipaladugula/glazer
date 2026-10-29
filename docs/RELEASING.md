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

macOS recognises an app by its code signature. If every release is signed with the same
identity, macOS treats updates as the same app: the face lock Keychain item stays readable
without asking, and camera and Accessibility permissions are kept. If not, each release is
a stranger.

Glazer doesn't have an Apple Developer ID, so it uses its own self-signed code signing
certificate. That gives the stable identity, though not Gatekeeper approval, which only a
Developer ID and notarisation give.

### Set it up once

1. Create the identity somewhere private, outside the repository:

   ```sh
   Scripts/signing.sh create ~/Glazer-Signing
   ```

2. Add it to the repository's secrets, so the Release workflow signs with it:

   ```sh
   base64 -i ~/Glazer-Signing/Glazer-Signing.p12 | gh secret set SIGNING_P12
   gh secret set SIGNING_P12_PASSWORD < ~/Glazer-Signing/Glazer-Signing.password
   ```

3. Pin the certificate in `install.sh` (`expected_signer`) to the fingerprint in
   `~/Glazer-Signing/Glazer-Signing.sha1`, so the installer rejects anything not signed
   with it. Do this only **after** the first signed release is published: users run the
   installer from `main`, and a pin merged earlier rejects the latest release until a
   signed one replaces it.

4. Optionally, sign your own builds with it too, so they share the release's identity:

   ```sh
   Scripts/signing.sh install ~/Glazer-Signing
   ```

Keep `~/Glazer-Signing` backed up and private. Anyone with the `.p12` and its password can
sign apps that macOS treats as Glazer. If it's lost, create a new one: users are asked once
more after the next update.

Without the secrets the Release workflow still publishes, signed ad hoc, and warns.

### What users see

- `install.sh` installs without Gatekeeper warnings, because `curl` doesn't quarantine
  downloads.
- A zip downloaded in a browser needs a right-click › **Open** the first time.
- With the signing identity, updates keep permissions and Keychain access. Without it,
  people allow the camera and Accessibility again, and Glazer's Keychain item again,
  after each update.
