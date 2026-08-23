# VoxHearth performance and thrash treatment

Status: implemented, verified, rebuilt, and independently approved from clean baseline `beb4cfb`.

## Goal

Audit the completed S1 Mini build for correctness faults, unnecessary work,
task/allocation churn, and long-uptime degradation; implement only findings
supported by the current source or a deterministic regression; then verify and
rebuild a fresh local app bundle. Current product behavior, offline/privacy
guarantees, model validation, cleanup fallbacks, insertion safety, preview
cadence, and accelerator placement remain fixed.

## Accepted findings

1. `DictationController` can orphan a recovery-capacity reservation when an
   accepted start is superseded before `runAcceptedStart`, or when a whole-
   session cancel is superseded while awaiting teardown. Three orphaned slots
   can reject future captures until relaunch. Close only paths where no
   insertion can still need the reserved slot; keep the explicit-cancel marker
   alive for any in-flight completion.
2. `S1MiniQueueState.prepare` misses its no-op path after sticky Metal demotion
   because it compares the resident CPU session to the originally requested
   Metal backend and additionally requires `!metalDemoted`. Compare against the
   effective backend so an already-correct CPU session is reused.
3. A successful cleanup leaves its deadline callback scheduled and later
   cancels an already-finished token. Cancel that callback when the operation
   wins the deadline race while retaining the existing deadline behavior.
4. The audio render callback materializes a transient `[Float]` for every
   buffer. Append mono samples directly from the input pointer and reuse one
   bounded mixdown scratch allocation for multichannel input. Do not preallocate
   the ten-minute recording or change the accumulator/preview storage design.
5. All signpost intervals currently use the default exclusive ID, which makes
   overlapping intervals ambiguous. Generate a unique ID per interval.
6. The lifecycle soak currently invokes a debug test build. Run it in release
   configuration and stamp that configuration into its result before using it
   for performance comparisons.

## Explicitly deferred or rejected

- Keep `check_tensors = true`; skipping repeat GGUF validation weakens an
  existing verification control.
- Keep memory-pressure recovery semantics. Making recovery lazy can cause the
  next cleanup to fall back and is a product tradeoff, not a transparent fix.
- Keep preview cadence/window and the stop -> preview join -> final inference
  ordering.
- Do not cache/reuse `AVAudioConverter` without measured benefit and byte-
  identity evidence. Existing traces put resampling near zero to two
  milliseconds, while reuse can affect state and ASR accuracy.
- Do not move lifecycle activity assertion work, alter Core ML compute units,
  add a resident engine/model, or edit vendored runtimes without evidence.
- `deactivate()` audio teardown is latent evaluator-only behavior in the shipped
  app and is not part of the user-visible stall fix.

## Ordered gates

1. Make signposts trustworthy and make the soak release-configured; re-lock the
   supplemental evaluator and record a pre-product-change baseline if the local
   verified model payloads are available.
2. Add failing reservation and demoted-backend tests, then implement their
   minimal fixes.
3. Add deadline-callback and audio-buffer regression coverage, then remove the
   substantiated churn.
4. Run focused tests, full `swift test`, release build, local checks, and the
   post-change soak. Report neutral measurements honestly.
5. Build a fresh ad-hoc app bundle from the exact verified local payloads.
6. Give Claude a fresh read-only review packet, reproduce or disprove every
   finding, remediate once, and rerun the final deterministic gates.

## Review remediation

The fresh reviewer identified one inferred medium policy drift and six low
issues/gaps. Inspection of the exact starting source disproved the medium
finding: sticky CPU demotion across unloads was already the baseline behavior.
The same comparison also disproved the suggested mixdown arithmetic drift.
Substantiated low findings were fixed: warm state is tracked for reused cleanup
sessions, dead explicit-cancel markers are removed after all keyed work joins,
the deadline regression has scheduling headroom, and soak configuration is now
compile-time-derived with testability recorded separately. Coverage now pins
the abandoned-start reservation release, retained safety state during an
in-flight cleaning cancel, sticky demotion across unload, and warming an
unwarmed resident session. Default signpost interval states were directly
reproduced as identical on the test host, closing the pre-fix evidence gap.
The resumed Opus/max review approved the remediation and found no material
defect. Three low residuals remain documented in the task evidence: dedicated
coverage for a defensive evaluator-only deactivate branch, non-production
warm-up failure diagnostic asymmetry, and a rare post-insertion cancellation
marker retained within already bounded session history.

## Completion boundary

Automated evidence can establish `verified`, not live 24-hour acceptance.
Signing, notarization, DMG publication, commit, push, and tag creation are out
of scope for this treatment.
