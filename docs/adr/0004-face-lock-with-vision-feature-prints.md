# 0004. Face lock with Vision image feature prints

**Status:** Accepted, experimental

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

## Evidence

Before release, the approach was measured on public-domain portraits from Wikimedia
Commons: three photos of one person at different angles, and six other people, both
photos and paintings.

| Face crop | Same person | Other people, highest | Separates? |
|---|---|---|---|
| Face box widened by 15% | 0.65–0.79 | 0.70 | No |
| Exact face box | 0.70–0.75 | 0.68 | Yes, narrowly |
| Face box narrowed by 10–20% | 0.58–0.74 | 0.79 | No |

With the exact box, the threshold learned from the same person's other angles (0.68)
accepted all three of their photos and rejected all 18 comparisons with other people.
The margin is small and the sample is small, so face lock ships marked **experimental**.

Two more things the measurements showed:

- Wider crops let hair, clothes, background and even painting style sway the comparison.
  So signatures use the exact face box.
- Samples taken a moment apart at the same angle are near copies. So the threshold is
  learned from similarities *across* angles, and the user is dropped only after three
  failed checks in a row.

## Consequences

- No third-party code or model, and nothing to license. Everything runs on the Mac with
  frameworks that ship with macOS.
- Face lock tells the user apart from most other people in view, but not reliably from
  everyone. It's marked experimental in the app and the docs. It is **not** a security
  boundary like Face ID or Touch ID: someone who looks similar, or a good photo, may
  match.
- A dedicated face recognition model would separate people far better. Adopting one
  needs a model whose licence allows redistribution, and a new decision record.
- Accessories that change a lot, such as glasses on and off, may need a second enrolment.
- If Apple changes the feature print, the template version changes and Glazer asks the
  user to enrol again instead of silently failing to match.
- A dedicated face model can replace the extractor later behind the same `FaceSignature`
  type, with a new decision record.
