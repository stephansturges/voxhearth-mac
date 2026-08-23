# Aggregated latency evidence

These files preserve the complete aggregated JSON emitted by the frozen
evaluator. They contain only tracked synthetic-fixture transcripts and timing,
count, digest, environment, and process-resource metadata. They contain no
user audio, model payload, absolute local path, or credential.

The compact files under `../baselines/` remain the immutable inputs consumed by
`score`. The full baseline files here make every warm component distribution,
R-7 p95, count, transcript digest, cold sample, and process resource value
independently reproducible. The candidate files preserve the rejected P0/P5
runs. The guardrail files preserve the P1-P4 runs performed on the retained
CPU-only baseline after no candidate passed the scalar gate.

The automated candidate scorer ran P0 and P5. P1-P4 were a separate final
guardrail step, not part of the scalar command. No candidate reached that final
step because all three were already slower than baseline. Future research must
replace the inert promotion-check declaration, explicitly wire any desired
P1-P4 automation, revise the overly strict A/B-derived resource floor if the
user approves, and remeasure generation zero rather than reusing this frozen
session.

`manifest.json` locks the collected file set, byte sizes, and SHA-256 digests.
It is evidence provenance, not an evaluator input, and is intentionally outside
`evaluator.lock.json`.
