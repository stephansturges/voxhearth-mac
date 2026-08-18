# UX latency autoresearch implementation plan

Status: evaluator setup implemented; latency candidates not started.

This Codex-owned execution plan applies the accepted brief and amended Claude
architecture while resolving setup ambiguities in favor of reproducible,
non-synthetic evidence.

## Frozen setup

1. Track the canonical `say` AIFF files under
   `Research/latency/fixtures/**`; do not generate per candidate.
2. Measure the existing controller seams only. Add no product milestone API or
   shipped environment-variable check.
3. Score warm P0 with the confirmed 10/10/20/60 weighted R-7 p95. Run one
   excluded process warm-up per ten-sample repeat, yielding 27 scored samples
   over three fresh processes.
4. Keep cold launch and multilingual-to-compact switch evidence separate as a
   hard no-regression gate.
5. Use no fake timed duration in any profile. Prove post-dispatch cleanup
   exclusion using segment boundaries rather than the superseded P3 120 ms
   delay. Do not model real audio teardown.
6. Accept model roots only from explicit environment variables, verify exact
   payload file sets and digests against the committed manifests, and provide
   no network fallback.
7. Lock the evaluator, protocol, dataset and capability fingerprint before any
   candidate branch is measured.

## Candidate sequence after generation zero

Generation zero runs P0-P5 as baseline A, then P0 and P5 as baseline B to
freeze score/component/cold/resource noise. The compiled payloads declare
fixed `[1, 240000]` preprocessor input with no shape flexibility, so the C1
dynamic-right-sizing path is recorded as capability-gated/no-op rather than
forcing an invalid model shape.

Generation 1 remains bounded to three independently measurable candidates:

1. The authorized FluidAudio input-right-sizing candidate only if a future
   verified payload fingerprint admits it; otherwise preserve the no-op result
   and use the accepted fallback slot.
2. Multilingual preprocessor compute-unit configuration.
3. Eliminate/restructure the queued activation task, measured directly at cue,
   capture and stop seams. No synthetic teardown credit is permitted.

Generation 2 contains at most three evidence-derived combinations/tunings and
never repeats a rejected mechanism unchanged. Total candidates remain at most
six across two generations.

## Promotion and delivery

A winner must clear the frozen score threshold, all four component gates, cold
gates, byte-identical transcript gates and resource gates. It must pass P0-P5,
normal tests/builds, both offline real-model smoke tests, static resource and
privacy review, and fresh read-only Claude review. If no candidate qualifies,
the unchanged baseline is the honest outcome.

The only delivery artifact authorized is a local unsigned
`0.3.0-dev.3.latency1` build 949 DMG. Do not install it, touch the app in
`/Applications`, push, open a pull request, tag, sign, notarize or publish.
