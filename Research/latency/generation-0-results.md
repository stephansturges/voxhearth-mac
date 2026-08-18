# UX latency research result

The bounded session stopped after its first candidate generation because none
of the three multilingual preprocessor placements improved the frozen
CPU-only baseline. No candidate product patch was promoted.

## Decision

The baseline weighted warm p95 was **48.089 ms**. A candidate had to improve it
by at least **4.809 ms**, retain byte-identical transcripts, avoid component and
cold-path regressions, and remain within the measured CPU and peak-RSS noise
allowances.

| Candidate | Weighted p95 | Change from baseline | Peak RSS | Decision |
| --- | ---: | ---: | ---: | --- |
| CPU + Neural Engine | 50.438 ms | 2.349 ms slower (4.884%) | 117.70 MiB | Reject |
| All compute units | 51.477 ms | 3.389 ms slower (7.046%) | 137.73 MiB | Reject |
| CPU + GPU | 51.884 ms | 3.795 ms slower (7.892%) | 128.61 MiB | Reject |

All three candidates preserved transcript bytes. All three nevertheless failed
the primary latency threshold, the resource gate, the cold gate, and at least
the cue, audio-stop-entry, and visible-text component gates. The baseline peak
RSS was 106.39 MiB; the candidates increased it rather than revealing a useful
offload path.

The session therefore retained `.cpuOnly` for the multilingual preprocessor.
The configured patience rule stopped the search instead of deriving a second
generation from regressions. The fixed `[1, 240000]` model input and the tiny
already-direct activation dispatch segments had already eliminated input
right-sizing and task-hop restructuring before mutation.

## Interpretation

The user's macmon reading of 62.28 / 128 GB does not indicate system memory
exhaustion, and this experiment did not find evidence that moving preprocessing
off CPU would help. The severe shortcut, cue, microphone-release, and preview
stall reported in the installed build remains consistent with the preview
lifecycle regression fixed on current `main`: idle animation was stopped,
preview snapshots were bounded, the extra main-actor hotkey hop was removed,
and microphone capture now stops before preview cancellation is awaited.

The local latency build packages that current runtime without any rejected
compute-unit experiment. The evaluator uses fake OS boundaries, so final
acceptance still requires real hold-to-talk, cue, microphone-indicator,
preview, model-switch, and text-insertion checks on the DMG.

Machine-readable evidence is in
[`generation-0-results.json`](generation-0-results.json), the immutable
controller export is in [`autoresearch-report.json`](autoresearch-report.json),
and the full baseline distributions are under [`baselines/`](baselines/).
