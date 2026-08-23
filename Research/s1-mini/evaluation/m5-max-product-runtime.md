# S1-mini product-runtime evaluation: M5 Max

Date: 2026-08-21

Status: the integrated production Swift/llama runtime passes the bounded M5 Max
semantic, deterministic-repeat, network-denied, hostile-environment, invalid-
asset, privacy-canary, latency, and resource ratchets. This is development-Mac
evidence. It does not claim the still-external M2/16 GB, manual host-app,
VoiceOver, energy/thermal, or 24-hour integrated-app checks.

## Inputs

- Product source commit under evaluation: `df0f41e` plus the evaluator-only G7
  worktree changes.
- Model: 484,219,808-byte `s1-mini-q4_k_m.gguf`, SHA-256
  `3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634`.
- Metal library: 8,445,733 bytes, SHA-256
  `97897d540709e3819756049c07d67ed5653136d28638e17159c4940ccaf42ea8`.
  This remains the pinned-source spike artifact and is evidence only; P8 must
  perform and record a production rebuild before it can be packaged.
- Machine: Apple M5 Max, 18 CPU cores, 40-core GPU, 128 GB RAM, arm64, macOS
  Darwin 25.4.0, Xcode 26.2.
- Fixture corpus SHA-256:
  `e43a0602078ce7b460a78e5c6080064c4700222560760cc05b9c446e9acc28cc`.
- Ratchet SHA-256:
  `6abb2cd825233ea868fd057f3d89f2fc235e255b74190043bae3425313708e92`.
- Command: `scripts/s1-mini-eval.sh run`, with 20 post-corpus deterministic
  repetitions per backend and 100 ms spacing.

## Results

Both CPU+Accelerate and Metal passed all 15 semantic fixtures. The corpus covers
ordinary prose, explicit list and email modes, a later-word near miss, prose
permitted under list mode, a technical list, email without a signoff, spoken-
address safe fallback, hallucinated-address rejection, filler-only input,
spoken correction, number/date/currency normalization, chunked prose,
structured over-budget fallback, and a private log canary.

| Metric | CPU+Accelerate | Metal |
| --- | ---: | ---: |
| Fixtures passed | 15/15 | 15/15 |
| Deterministic repeated output | yes | yes |
| p95 latency | 188.756 ms | 60.830 ms |
| maximum latency | 245.742 ms | 85.972 ms |
| sampled maximum RSS | 1,552,203,776 bytes | 1,285,373,952 bytes |
| sampled maximum threads | 10 | 5 |
| model loads / contexts / warmups | 1 / 1 / 1 | 1 / 1 / 1 |
| generation failures | 0 | 0 |

The CPU semantic result digest was
`b2ec75a2b1510e17033377b5e35894683837181093f16c1d810ccd8beade539d`;
the Metal digest was
`a7fbea7f25e3f1e6a34506229a188b394964ea1444efb2006b31d46464070573`.
Backend byte identity is advisory; every semantic assertion is mandatory.

Fresh CPU and Metal processes passed under `sandbox-exec` with all networking
denied. Poisoning `GGML_METAL_PATH_RESOURCES`, `GGML_METAL_DEVICES`, and
`GGML_METAL_FUSION_DISABLE` left each backend's semantic digest unchanged.
Wrong-size and symlink model assets were rejected. All evaluator and runtime
stderr captures were empty. The unique private-transcript canary appeared in no
JSON, stderr, or aggregate output. The content-free aggregate artifact SHA-256
was `8b8e548999ba7f98174f42bff9bd56280d10acd42465a8bd2196909b2aa977dc`.

The first run exposed that this model writes a spoken address in a form rejected
by the product grounding validator. The accepted behavior is a typed
`invalidOutput` fallback containing the command-stripped spoken source; it is
now a mandatory fixture. A separate fixture confirms the model does not invent
an address when none was spoken.

## Open acceptance evidence

- Repeat the product-runtime ratchet on the M2/16 GB floor.
- Build a fresh production metallib from the pinned vendored source and record
  its byte identity and compatibility evidence.
- Run the manual host-app, terminal, keyboard, and VoiceOver matrix against the
  packaged app.
- Record integrated app energy/thermal, sleep/wake, user-switch, memory-
  pressure, and 24-hour lifecycle evidence. The earlier isolated runtime 24-hour
  pass remains supporting evidence, not a replacement for this check.
