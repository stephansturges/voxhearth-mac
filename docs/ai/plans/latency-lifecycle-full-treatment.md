# Full long-running latency treatment and diagnostics

Status: implemented and reviewed; local diagnostic artifact pending.

This plan integrates the complete lifecycle treatment and diagnostic surface for
the intermittent hotkey, preview, microphone-release, and text-delivery stalls
reported after roughly a day of VoxHearth uptime. It supersedes the earlier
small-slice approach while retaining its bounded Accessibility insertion work.

## Evidence and diagnosis boundary

The slow installed-app trace shows local preview inference markers completing
in roughly 113–156 ms while publication completes 1.27–4.03 seconds later. A
nominal 600 ms preview cadence also stretched to 10.65 seconds. In the same
trace, audio teardown took 7 ms and Unicode event dispatch took 1 ms.

The existing marker is not an exact Core ML return boundary, and preview
publication is logged only after the synchronous MainActor overlay callback.
The unexplained interval therefore includes scoped destruction, actor
scheduling, SwiftUI/AppKit work, and WindowServer work. This release will make
those boundaries distinguishable rather than attributing the gap to the model.

A later bounded snapshot of the roughly 38-hour process showed no runaway CPU,
thread, or RAM condition, but it did show no user-activity assertion and a
collection of IOSurface and MLMultiArray objects that a fresh-process evaluator
cannot classify as stable pools or uptime growth. Both control-plane throttling
and same-process resource drift therefore remain live hypotheses.

## Accepted implementation

1. Accept start and stop synchronously on MainActor before queueing asynchronous
   preparation or teardown. Route UI, hotkey, and pointer activation through the
   same request methods, retain duplicate-event and short-press guards, and run
   the user-visible continuation at explicit user-initiated task priority.
   Monotonic lifecycle epochs and predecessor joins prevent cancelled or
   background-preparation continuations from clobbering a newer accepted press.
2. Add an injectable lifecycle-activity abstraction. An accepted microphone
   session starts a sleep-permitting user-initiated activity with the
   latency-critical flag, narrows to sleep-permitting user-initiated immediately
   after the microphone stops, and ends on every idle, failure, cancellation,
   retry, discard, or deactivation path. External audio and insertion retry use
   only the sleep-permitting user-initiated scope. VoxHearth never disables App
   Nap globally or holds an assertion while idle.
3. Move preview scheduling into a separate actor that shares the one existing
   capture service and transcription engine. It performs one MainActor hop only
   when publishing. Audio stop, preview cancellation/join, and final inference
   retain their strict no-overlap order.
4. Measure each preview cycle from snapshot request through completed MainActor
   publication. If it exceeds the greater of two seconds or four preview
   intervals, open a per-recording circuit breaker, retain the last visible
   text, stop further preview work for that recording, and leave the engine free
   for the final transcript. A new recording creates a fresh breaker.
5. Update the overlay only when its displayed text actually changes. Query the
   screen, position, and order the panel only on hidden-to-visible presentation
   or a real screen-configuration change. Remove continuous symbol effects from
   both the overlay and busy menu presentation.
6. Expand the closed, privacy-safe marker vocabulary across cue playback,
   activation acceptance, activity-scope changes, snapshot lock/copy, inference
   return and scope release, preview MainActor handoff, overlay text/screen/frame/
   order operations, circuit opening, pooled-buffer experiments, and recovery
   decisions. Unicode insertion is explicitly recorded as event dispatch, not
   target-application acknowledgement.
7. Keep the existing audio accumulator design. The preview copy is bounded and
   uses an unfair lock; preallocating ten minutes would impose a large per-session
   memory cost. Instrument its lock/copy boundary instead.
8. Keep compute-unit placement and vendored FluidAudio unchanged. Do not wrap an
   async prediction in `autoreleasepool`, add speculative output backings, or add
   a second engine/model. Make the Core ML return/release markers honest. Expose
   pooled-array release and an idle-only, one-shot model reload as diagnostic
   opt-ins, because neither is proven to improve latency and clearing the current
   shared pool is not synchronously acknowledged by the vendored manager.
9. Add a versioned, opt-in same-process real-model soak inside the existing test
   target plus a separate supplemental lock. Do not mutate the frozen P0–P5
   evaluator, fixtures, lock, or objective. The soak keeps one process, model,
   controller, and fixture set alive across windows; records raw per-cycle
   latency, window percentiles, CPU, peak RSS, physical footprint, and thread
   count; verifies transcript digests; and fails sustained first-to-last drift
   rather than averaging it away.
10. Add a privacy-safe installed-process capture command. It pins the VoxHearth
    log subsystem and one PID, collects a bounded log window and fixed process,
    vmmap, heap, and short sample outputs where permitted, records unavailable
    tools without failing, and never captures environment variables, clipboard
    content, audio, or unrelated processes.

## Rejected changes

- No global App Nap disable, Mach real-time scheduling, permanent priority
  elevation, persistent microphone/audio engine, background poller, or timer.
- No second resident model, compute-unit experiment, unverified Core ML output
  backing, vendored decoder change, or persistent memory increase.
- No automatic Accessibility fallback after an ambiguous side-effecting write.
- No claim that a minutes-long soak reproduces a 20–24-hour symptom or exercises
  the AppKit/WindowServer overlay; installed-process capture remains the decisive
  tool for that path.

## Verification and artifact

- Deterministic unit tests cover synchronous acceptance, rapid/duplicate events,
  activity balance, priority, breaker/reset, no-overlap, overlay policy, recovery
  gating, marker privacy, evaluator inertness, and script guardrails.
- The frozen evaluator verifies byte-identically, the full local gate and both
  real-model smoke tests pass, and quick plus full same-process soaks run without
  network access.
- A fresh read-only Claude Opus/max review receives the exact diff and evidence;
  each finding is independently classified before the single commit.
- The local artifact is `0.3.0-dev.3.diag2` build 951, ad-hoc signed and packaged
  in an unsigned DMG. It is not installed, pushed, tagged, notarized, or
  published, and no existing artifact is overwritten.

## Source references

- Process activity API: https://developer.apple.com/documentation/foundation/processinfo
- Latency-critical activity: https://developer.apple.com/documentation/foundation/processinfo/activityoptions/latencycritical
- App Nap guidance: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html
- Swift task priority: https://developer.apple.com/documentation/swift/taskpriority
- Core ML optimization: https://developer.apple.com/videos/play/wwdc2022/10027/
- Async Core ML execution: https://developer.apple.com/videos/play/wwdc2023/10049/
- FluidAudio IOSurface issue context: https://github.com/FluidInference/FluidAudio/issues/320
