# 0004. Face lock with Vision image feature prints

**Status:** Accepted

## Context

Face lock lets Glazer follow only the enrolled user, so someone else at the desk can't
move the user's focus around. That needs a way to tell faces apart.

Apple's Vision framework finds faces and measures head pose, but has no public face
recognition API. Photos recognises people with a private API that apps can't use. The
usual alternative is a face recognition model bundled with the app, but:

- Most widely used pretrained face models are licensed for research or non-commercial
  use only, or were trained on datasets that have since been withdrawn. That isn't a
  sound basis for an open-source project others will redistribute.
- A model is a large third-party dependency in an app that has the camera
  ([ADR 0003](0003-no-third-party-dependencies.md)).

## Decision

Face lock uses Vision's built-in `VNGenerateImageFeaturePrintRequest` on a tight crop of
each face. The resulting vector is the user's face signature. Signatures are compared by
cosine similarity.

Because a general-purpose image feature print isn't trained for faces, the match
threshold isn't fixed. It is learned from enrolment: just below how alike the user's own
samples are across angles. Enrolment covers left, centre and right head turns, so the
user is recognised facing any display.

The template is stored only in the macOS Keychain, marked not synchronisable, and setting
it up or deleting it requires Touch ID or the login password.

## Consequences

- No third-party code or model, and nothing to license. Everything runs on the Mac with
  frameworks that ship with macOS.
- Face lock reliably tells the user apart from **other people in view**, which is its job.
  It is **not** a security boundary like Face ID or Touch ID: someone who looks very
  similar, or a good photo, may match. The README and privacy doc say so plainly.
- Accessories that change a lot, such as glasses on and off, may need a second enrolment.
- If Apple changes the feature print, the template version changes and Glazer asks the
  user to enrol again instead of silently failing to match.
- A dedicated face model can replace the extractor later behind the same `FaceSignature`
  type, with a new decision record.
