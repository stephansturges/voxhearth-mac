# Latency diagnostic treatment

Status: delivered as the Accessibility phase of the full lifecycle plan in
`docs/ai/plans/latency-lifecycle-full-treatment.md`.

This pass addresses the synchronous Accessibility insertion tail while adding
privacy-safe lifecycle markers for the separate press, preview, audio teardown,
and inference symptoms reported in the installed app.

## Decisions

- Bound the first two Accessibility queries to 350 ms each and the final
  side-effecting write to 600 ms. The SDK documents only that non-zero timeout
  values must be positive; it does not document a 250 ms minimum.
- Preserve the existing Accessibility-first behavior for responsive apps.
- Fall back automatically only when no side-effecting write was attempted or
  the write returned a definite refusal.
- Treat `kAXErrorCannotComplete` from the final write as uncertain. Retain the
  transcript in memory for an explicit retry or discard instead of risking an
  automatic duplicate.
- Keep Unicode-first insertion available only as a local diagnostic preference,
  with no new UI or persisted transcript state.
- Emit only closed-enum lifecycle identifiers and paired signpost intervals.
  Never emit audio, transcripts, paths, destination identities, device names,
  counts, or numeric durations.
- Preserve the current audio-stop-before-preview-join ordering. The integrated
  follow-up moves only preview orchestration off MainActor, adds backpressure,
  and keeps the shared model actor/no-overlap invariant.

## Verification

Focused tests cover the three insertion outcomes, timeout ordering and reset,
diagnostic Unicode-first behavior, retry safety, and event-vocabulary policy.
The integrated lifecycle plan adds the long-uptime treatment, soak/capture
diagnostics, and build 951 verification. The build is not installed, published,
pushed, tagged, or notarized.
