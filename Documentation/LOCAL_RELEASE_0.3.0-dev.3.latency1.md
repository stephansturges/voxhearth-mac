# VoxHearth 0.3.0-dev.3.latency1 local latency build

This is a local, ad-hoc-signed, unsigned-by-Developer-ID and unnotarized build
with bundle build number 949. It is not a GitHub release and must not be
presented as an official or Gatekeeper-ready distribution.

## Runtime contents

The app runtime is the current `v0.3.0-dev.3` code. It includes the restored
hold-to-talk responsiveness work: direct Carbon hotkey handling, an idle live
preview that no longer animates continuously, bounded eight-second preview
snapshots, non-overlapping preview/final inference, and microphone stop before
preview cancellation is awaited.

The follow-up latency research tested CPU + GPU, CPU + Neural Engine, and all
compute-unit placement for multilingual preprocessing. Every candidate was
slower than the retained CPU-only baseline and also failed cold/resource
gates, so none is present in this build. The opt-in evaluator and tracked test
fixtures are development-only and are inert during an ordinary app run.

## Artifact identity

- Marketing version: `0.3.0-dev.3.latency1`
- Bundle build: `949`
- Expected DMG: `VoxHearth-v0.3.0-dev.3.latency1-unsigned.dmg`
- Signing: ad-hoc app-bundle seal only; no trusted publisher identity
- Notarization: absent
- Installation: intentionally not performed by this work

The build command is:

```bash
VERSION=0.3.0-dev.3.latency1 BUILD_NUMBER=949 \
  ./scripts/build-release-local.sh
```

Before replacing an installed copy manually, quit the running VoxHearth
process. Verify the delivered SHA-256, open the DMG, drag the app to
Applications, and use the documented per-app **Open Anyway** flow if macOS
blocks this development build. Never disable Gatekeeper globally.

## Acceptance still required

Automated evidence cannot measure the actual audible cue, microphone indicator,
Carbon delivery boundary, focused-app visibility, or clipboard restoration.
The recipient should manually exercise short and rapid press/release, preview
on and off, both speech models, Accessibility insertion, Unicode fallback, and
clipboard compatibility after installing later.
