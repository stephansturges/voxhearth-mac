# VoxHearth 0.3.0-dev.3.diag2 local lifecycle build

This is a local diagnostic build with marketing version
`0.3.0-dev.3.diag2` and bundle build 951. The app bundle has only an ad-hoc
integrity signature. The DMG is unsigned by Developer ID and unnotarized. It is
not an official, public, or Gatekeeper-ready release.

## Included treatment

- synchronous hotkey/UI start and stop acceptance;
- lifecycle epochs that prevent a cancelled slow start or stop from clobbering
  a newer accepted hotkey session;
- session-scoped, sleep-permitting ProcessInfo activity protection with the
  latency-critical flag limited to cue, preparation, recording, and microphone
  teardown;
- explicit user-initiated start, stop, final-transcription, and insertion work;
- one off-MainActor preview session sharing the existing model and capture
  actors, with stop-before-join-before-final ordering retained;
- a per-recording end-to-end preview circuit breaker;
- a show-once, position-once overlay with no continuous symbol effects;
- bounded Accessibility calls with ambiguity-safe recovery;
- detailed fixed-name markers across hotkey, cue, capture, model return, object
  release, actor handoff, overlay, insertion dispatch, and lifecycle activity;
- a versioned same-process real-model soak and a privacy-safe installed-process
  capture script, with test-helper and production logs isolated by subsystem and
  every production capture pinned to the exact app PID.

No second model, persistent microphone/audio engine, global App Nap disable,
background poller, Mach real-time scheduling, compute-unit change, or vendored
FluidAudio mutation is included. Pooled-array release and idle model reload are
diagnostic opt-ins and default off.

## Artifact identity

- Marketing version: `0.3.0-dev.3.diag2`
- Bundle build: `951`
- App: `.build/distribution/VoxHearth-0.3.0-dev.3.diag2.app`
- DMG: `.build/distribution/VoxHearth-v0.3.0-dev.3.diag2-unsigned.dmg`
- Signing: ad-hoc app-bundle seal only
- Developer ID signature: absent
- Notarization/stapling: absent
- Installation and publication: intentionally not performed

The non-colliding local build commands are:

```sh
./scripts/fetch-models.sh
./scripts/build-app-bundle.sh \
  --version 0.3.0-dev.3.diag2 \
  --build 951 \
  --output .build/distribution/VoxHearth-0.3.0-dev.3.diag2.app
./scripts/create-dmg.sh \
  .build/distribution/VoxHearth-0.3.0-dev.3.diag2.app \
  .build/distribution/VoxHearth-v0.3.0-dev.3.diag2-unsigned.dmg
```

These paths preserve the existing `diag1` app/DMG. The scripts refuse to
overwrite an existing destination.

## Manual acceptance still required

Automated evidence cannot reproduce a 20–24-hour menu-agent lifetime or run the
test-target soak through AppKit and WindowServer. After choosing to install the
build later, exercise rapid and short press/release, preview on/off, both models,
Accessibility/Unicode/clipboard paths, screen changes, sleep/wake, and a full
working day. Capture a slow process immediately with the documented
`scripts/capture-diagnostics.sh` command. Never disable Gatekeeper globally.
