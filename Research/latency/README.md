# VoxHearth latency evaluator

This directory freezes the evaluator and synthetic dataset used by the bounded
UX-latency research session. It is opt-in: ordinary `swift test` runs compile
the target but return immediately unless `VOXHEARTH_LATENCY_EVAL=1` is set by
`scripts/latency-eval.sh`.

## Objective

Only warm P0 dictations carry the scalar score:

```text
0.10 * p95(press -> cue dispatch)
+ 0.10 * p95(press -> capture-start completion)
+ 0.20 * p95(release -> audio-stop entry)
+ 0.60 * p95(release -> visible-text dispatch)
```

The p95 is R type 7 linear interpolation. Each P0 repeat contains the ten
fixed scored utterances. The first is marked `process-warmup` and excluded,
leaving 27 warm samples across the required three fresh-process repeats. The
JSON retains every raw sample, all four distributions, medians, maxima, p95s,
the weighted score, unscored segments, transcripts and resource counters.

The four boundaries are existing public injection seams, not product
instrumentation:

- cue dispatch: immediately before the controller invokes `onStartCue`;
- capture-start completion: exit from injected `AudioCapturing.start`;
- audio-stop entry: entry into injected `AudioCapturing.stop`;
- visible-text dispatch: entry into `TextInserting.insert` with the complete
  final transcript.

The microphone, tone, global hotkey/pointer input and destination application
are faked. Every transcription uses the real selected `ParakeetEngine`. The
capture and insertion fakes do no synthetic timed work. In particular, there
is no modeled `AVAudioEngine.stop()` cost and no 120 ms clipboard delay. The
unscored `stopEntryToExit`, `insertEntryToExit` and `insertExitToIdle` segments
make the score boundary explicit without inventing cleanup latency.

## Profiles and gates

- P0: default multilingual, English, preview off, Accessibility-style insert;
  this is the only scored profile.
- P1: preview enabled with a two-second hold; guardrail only.
- P2: compact English model; guardrail only.
- P3: clipboard compatibility enabled and clipboard-style insert; zero fake
  delay, guardrail only.
- P4: explicit release-during-preparation cancellation, short, long, chunked
  and French fixtures, Unicode-style insertion and pointer-button parity;
  guardrail only.
- P5: first dictation without preloading and first dictation after switching
  multilingual to compact; cold hard-gate evidence, never part of the score.

P0 screening alone is insufficient for promotion. A proposed winner must run
P0-P5, retain byte-identical transcripts for every identical
fixture/model/language tuple, keep cold results within their generation-zero
noise margin, and pass manual OS acceptance.

Generation zero consists of baseline A and baseline B at the setup commit.
The absolute A/B difference is frozen as the score, component, cold and
resource noise margin. Promotion requires:

```text
baseline score - candidate score
  >= max(score noise, min(10% of baseline score, 100 ms))
```

No component may regress beyond its component noise. Cold launch and switch
may not regress beyond cold noise. CPU time and peak resident memory may not
regress beyond measured noise and also have a hard 5% ceiling; the smaller
allowance applies. Start/stop counts must be balanced, transcriptions must not
overlap, and no extra model instance, idle audio engine, microphone persistence
or polling may be introduced.

## Immutable inputs

The canonical fixtures are tracked under `Research/latency/fixtures/` so every
candidate worktree receives identical bytes. `fixtures.manifest.json` records
the `say` recipe, source text, duration, size and SHA-256 for all ten scored and
four guardrail fixtures. Research runs verify those bytes and never regenerate
them.

`evaluator.lock.json` SHA-256-locks:

- `Package.swift`;
- `Tests/VoxHearthLatencyEval/**`;
- `scripts/latency-eval.sh`;
- this README and the Codex-owned plan;
- the fixture manifest and every tracked fixture;
- `model-capabilities.json`.

Every candidate write scope must exclude all of those paths. The lock itself
is not self-hashed. The runner refuses a lock, fixture or model-manifest
mismatch and refuses a dirty Git worktree (apart from orchestrator-owned
`.graph-worker/` metadata).

Both model roots must be supplied externally through
`VOXHEARTH_LATENCY_MULTILINGUAL_MODEL_ROOT` and
`VOXHEARTH_LATENCY_COMPACT_MODEL_ROOT`. The runner verifies each root against
its committed model manifest before Core ML is invoked. It has no download
fallback and runs Swift under a sandbox profile that denies networking.

The locked payload fingerprint records a fixed preprocessor input
`audio_signal: [1, 240000]` with `hasShapeFlexibility = false` for both models;
the compiled MIL entry point agrees. Dynamic input right-sizing must therefore
capability-gate to a no-op for these payloads. Any future payload drift is a
hard verification failure, not permission to alter the evaluator.

## Commands

```bash
scripts/latency-eval.sh fixtures
scripts/latency-eval.sh verify

export VOXHEARTH_LATENCY_MULTILINGUAL_MODEL_ROOT=/verified/local/multilingual
export VOXHEARTH_LATENCY_COMPACT_MODEL_ROOT=/verified/local/compact
scripts/latency-eval.sh run /absolute/result.json P0 3
scripts/latency-eval.sh compare baseline-a.json candidate.json baseline-b.json
scripts/latency-eval.sh score baseline-p0-a.json baseline-p0-b.json \
  baseline-p5-a.json baseline-p5-b.json
```

`score` performs three fresh P0 and P5 processes, applies every automated
promotion gate, writes diagnostics to stderr, and emits exactly one JSON metric
object on stdout for the bounded autoresearch controller.

Results are written atomically and existing result files are never
overwritten.

## Bounds and blind spots

The search is limited to two generations, six total candidates, three repeats
and two active-work hours. Generation 2 may only derive from measured
generation-1 evidence; rejected mechanisms are preserved and are not rerun
unchanged.

Absolute numbers include evaluator overhead and are only suitable for
same-machine relative comparisons. Automation cannot measure the actual
Carbon delivery boundary, audible cue, `AVAudioEngine` start/stop duration,
microphone indicator, Accessibility/CGEvent visibility, focus, or clipboard
restoration. Final acceptance on the unsigned DMG must exercise those real OS
boundaries, rapid/short press-release behavior, preview on/off, model switching
and all insertion routes. No user audio is retained.
