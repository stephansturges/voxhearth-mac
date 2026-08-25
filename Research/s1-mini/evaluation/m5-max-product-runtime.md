# S1-mini product-runtime evaluation: M5 Max

Date: 2026-08-25

Status: the integrated production Swift/llama runtime passes the bounded M5 Max
semantic, deterministic-repeat, network-denied, hostile-environment, invalid-
asset, privacy-canary, latency, and resource ratchets. This is development-Mac
evidence. It does not claim the still-external M2/16 GB, manual host-app,
VoiceOver, energy/thermal, or 24-hour integrated-app checks.

## Inputs

- Product source under evaluation: the complete number-canonicalization source
  prepared for tag `v0.4.0-dev.9`. The tag identifies the exact containing
  revision once the release is published.
- Model: 484,219,808-byte `s1-mini-q4_k_m.gguf`, SHA-256
  `3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634`.
- Metal library: reviewed production artifact, 8,445,925 bytes, SHA-256
  `925c4db276d4459780420282e6f20a221d3b9f35f44b26b7ba55d82d5e381b74`.
  It was copied from the installed reviewed VoxHearth bundle and passed
  `scripts/verify-metallib.py` before this run. A fresh build with the locally
  installed Metal toolchain produced the older 8,445,733-byte
  `97897d540709e3819756049c07d67ed5653136d28638e17159c4940ccaf42ea8`
  artifact and was rejected rather than silently substituted.
- Machine: Apple M5 Max, 18 CPU cores, 40-core GPU, 128 GB RAM, arm64, macOS
  Darwin 25.4.0, Xcode 26.2.
- Fixture corpus SHA-256:
  `ccf78cbd6d50a457f8e51d127a92988ed63856ac1d68413b341efc206ba0ce0a`.
- Ratchet SHA-256:
  `ca577ffe1f2d438f530dd9404e95ee9ef5e5afd6114c8391bd9024228e3994d1`.
- Command: `scripts/s1-mini-eval.sh run`, with 20 post-corpus deterministic
  repetitions per backend and 100 ms spacing.

## Results

Both CPU+Accelerate and Metal passed all 16 semantic fixtures. The corpus covers
ordinary prose, explicit list and email modes, a later-word near miss, prose
permitted under list mode, a technical list, email without a signoff, spoken-
address safe fallback, hallucinated-address rejection, filler-only input,
spoken correction, number/date/currency normalization, spoken-integer currency
canonicalization, chunked prose,
structured over-budget fallback, and a private log canary.

| Metric | CPU+Accelerate | Metal |
| --- | ---: | ---: |
| Fixtures passed | 16/16 | 16/16 |
| Deterministic repeated output | yes | yes |
| p95 latency | 176.183 ms | 59.949 ms |
| maximum latency | 558.533 ms | 188.419 ms |
| sampled maximum RSS | 1,552,695,296 bytes | 1,286,537,216 bytes |
| sampled maximum threads | 10 | 5 |
| model loads / contexts / warmups | 1 / 1 / 1 | 1 / 1 / 1 |
| generation failures | 0 | 0 |

The CPU semantic result digest was
`326f1607f8f675c23dc3c13a5fdcb5600ea2b685682d4a53313edbdb1499f5ce`;
the Metal digest was
`c7356be6247f036c7de03393f83df9580e1d0c04d317359525d3b5595b1e9ece`.
Backend byte identity is advisory; every semantic assertion is mandatory.

Fresh CPU and Metal processes passed under `sandbox-exec` with all networking
denied. Poisoning `GGML_METAL_PATH_RESOURCES`, `GGML_METAL_DEVICES`, and
`GGML_METAL_FUSION_DISABLE` left each backend's semantic digest unchanged.
Wrong-size and symlink model assets were rejected. All evaluator and runtime
stderr captures were empty. The unique private-transcript canary appeared in no
JSON, stderr, or aggregate output. The content-free aggregate artifact SHA-256
was `948c5604685f279cd4a089c50a179338c8d424782e56ec8511c11742a1d8f4ab`.

The added spoken-number fixture exposed that the pinned model itself rendered
`seven thousand and twelve dollars` as the incorrect `$7,12`. The accepted-
output finalizer repaired that single compatible numeric slot from the spoken
source and produced `The invoice total is 7012$.` on both backends (output
SHA-256 `75b65e2141c87c9cef464f848f9a155bc775430f99578e3413985f7bc1dddafe`).
The isolated finalizer benchmark, including this source-anchored path, measured
0.131 ms p50 and 0.291 ms p99 over 500 warm samples on this host, including a
chunked-prose-sized no-number case.

The first run exposed that this model writes a spoken address in a form rejected
by the product grounding validator. The accepted behavior is a typed
`invalidOutput` fallback containing the command-stripped spoken source; it is
now a mandatory fixture. A separate fixture confirms the model does not invent
an address when none was spoken.

## Open acceptance evidence

- Repeat the product-runtime ratchet on the M2/16 GB floor.
- Reconcile the local Metal toolchain's byte mismatch with the reviewed
  production metallib before replacing that packaged artifact.
- Run the manual host-app, terminal, keyboard, and VoiceOver matrix against the
  packaged app.
- Record integrated app energy/thermal, sleep/wake, user-switch, memory-
  pressure, and 24-hour lifecycle evidence. The earlier isolated runtime 24-hour
  pass remains supporting evidence, not a replacement for this check.
