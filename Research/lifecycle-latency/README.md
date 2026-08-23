# Lifecycle latency evaluator

This is a supplemental, versioned same-process soak. It does not modify or
supersede the frozen P0–P5 evaluator under `Research/latency`.

The lock covers the package graph, both model manifests, the tracked fixture
dataset, all VoxHearthCore and vendored ASR sources compiled into the evaluator,
the complete evaluator test target, and its verification/capture scripts. The
tree digest includes each relative path and the SHA-256 of its bytes, so added,
removed, renamed, or modified files under a locked directory invalidate it.

After an intentional change to any locked evaluator or compiled source, refresh
the supplemental lock and immediately verify it:

```sh
scripts/soak-eval.sh lock
scripts/soak-eval.sh verify
```

The lock command preserves the reviewed root list, refuses unsafe or missing
roots, and regenerates only this supplemental lifecycle lock. It never changes
the frozen P0-P5 evaluator lock.

Run a short validation:

```sh
scripts/soak-eval.sh quick /private/tmp/voxhearth-soak-quick.json
```

Run the full bounded profile:

```sh
scripts/soak-eval.sh full /private/tmp/voxhearth-soak-full.json
```

Do not dictate with the installed app while either profile runs. The evaluator
performs sustained real-model inference in `swiftpm-testing-helper`; shared Core
ML/CPU contention can temporarily delay the separate VoxHearth process. Test
logs use the `com.stephansturges.voxhearth.tests` subsystem so a PID-scoped
production capture cannot confuse evaluator traffic with an app session.

Both profiles use one long-lived process, controller, and real multilingual
model, exercise preview and final transcription on every cycle, deny network
access, verify transcript stability, and compare the first and last windows.
Resource sampling inside the evaluator is deliberately limited to process CPU,
resident/peak/physical footprint, and thread count. It does not suspend itself
with `heap`, `vmmap`, or `sample`; use the separate installed-process capture for
an object census and stack evidence.
They cannot exercise AppKit/WindowServer or reproduce a 20-hour wall-clock
condition; use `scripts/capture-diagnostics.sh` on the installed process for
that evidence.
