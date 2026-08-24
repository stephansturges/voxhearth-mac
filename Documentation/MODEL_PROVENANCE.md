# Model provenance and attribution

VoxHearth release builds contain two selectable Core ML conversions of NVIDIA
Parakeet automatic-speech-recognition models and one optional English text
normalizer, S1-mini by Superwhisper. All run entirely on the Mac.

## Material used

| Field | Value |
| --- | --- |
| Distributed model | `FluidInference/parakeet-tdt-0.6b-v3-coreml` |
| Immutable revision | `aed02740059203c4a87495924f685de3722ae9ce` |
| Source | <https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml> |
| Base model | `nvidia/parakeet-tdt-0.6b-v3` |
| Base source | <https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3> |
| Creator/base-model attribution | NVIDIA Corporation |
| Core ML conversion attribution | FluidInference |
| Conversion source identified by the model card | <https://github.com/FluidInference/mobius/tree/main/models/stt/parakeet-tdt-v3-0.6b/coreml> |
| Redistribution license used by VoxHearth | CC BY 4.0 |
| Full license | [`LICENSES/CC-BY-4.0.txt`](../LICENSES/CC-BY-4.0.txt) |

### Compact English model

| Field | Value |
| --- | --- |
| Distributed model | `FluidInference/parakeet-tdt-ctc-110m-coreml` |
| Immutable revision | `9bc92ead6e8f17eca92a869fd578ae76842b82ba` |
| Source | <https://huggingface.co/FluidInference/parakeet-tdt-ctc-110m-coreml> |
| Base model | `nvidia/parakeet-tdt_ctc-110m` |
| Base source | <https://huggingface.co/nvidia/parakeet-tdt_ctc-110m> |
| Creator/base-model attribution | NVIDIA Corporation |
| Core ML conversion attribution | FluidInference |
| Redistribution license used by VoxHearth | CC BY 4.0 |
| Full license | [`LICENSES/CC-BY-4.0.txt`](../LICENSES/CC-BY-4.0.txt) |

The converted model card's machine-readable metadata declares CC BY 4.0 and
names the NVIDIA model as its base. Its prose footer separately says Apache
2.0. The NVIDIA base model also declares CC BY 4.0. VoxHearth therefore takes
the conservative position and satisfies CC BY 4.0 for the distributed model
bytes rather than relying on the less restrictive prose footer.

VoxHearth does not claim ownership of the model. It does not change the pinned
model files; it selects the required upstream payloads, verifies them byte-for-byte,
and places them inside the signed application bundle. Packaging, naming, and
integration code are VoxHearth changes, not changes to model weights.

## Exact payload

Only these top-level payloads are distributed:

- `Preprocessor.mlmodelc`
- `Encoder.mlmodelc`
- `Decoder.mlmodelc`
- `JointDecisionv3.mlmodelc`
- `parakeet_vocab.json`

[`Models/parakeet-tdt-0.6b-v3-coreml.json`](../Models/parakeet-tdt-0.6b-v3-coreml.json)
records all 21 files, their byte counts, and SHA-256 values. The expected
uncompressed payload is 483,105,645 bytes. The build fetcher will not overwrite
an existing invalid payload and the verifier rejects additional files or
directories.

The `*.mlmodelc` directories are already-compiled Core ML artifacts. The
manifest deliberately excludes upstream quantized alternatives, other joint
model variants, examples, model-card media, and downloader metadata.

The compact model contains `Preprocessor.mlmodelc`, `Decoder.mlmodelc`,
`JointDecision.mlmodelc`, and `parakeet_vocab.json`. Its manifest records 16
files totaling 227,466,209 bytes. It is English-only. The multilingual model's
manifest records 21 files totaling 483,105,645 bytes.

## License obligations

CC BY 4.0 permits sharing and adaptation, including commercial use, subject to
attribution, license notice/link, change indication, and no additional legal or
technological restrictions. VoxHearth provides the attribution and license in
the source repository, inside the app's `Contents/Resources/Legal` directory,
in the release SBOM, and in this document.

No endorsement by NVIDIA or FluidInference is implied. Model output can be
incorrect and must not be treated as verified fact or used as the sole basis
for safety-critical decisions.

## S1-mini by Superwhisper cleanup model

| Field | Value |
| --- | --- |
| Product identification | S1-mini by Superwhisper |
| Model-card repository | `superwhisper/s1-mini` |
| Immutable model-card revision | `65f84bcda1d13df582c4a8443c1c5aa53c0c66db` |
| Model-card README SHA-256 | `b22a4ce83218b21af2e71c7e0d28b686239a0028299cdbc87e4238b2568cfd97` |
| Distributed repository | `superwhisper/s1-mini-GGUF` |
| Immutable GGUF revision | `8eab4779866f477ae6e7f237ca45fc2c65153f50` |
| Distributed file | `s1-mini-q4_k_m.gguf` |
| Exact bytes | 484,219,808 |
| Payload SHA-256 | `3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634` |
| Relationship | Fine-tuned from `Qwen/Qwen3-0.6B` |
| Qwen revision reviewed for attribution | `c1899de289a04d12100db370d81485cdf75e47ca` |
| License expression | `Apache-2.0 AND LicenseRef-S1-mini-Naming-Clause` |
| Complete license | [`LICENSES/S1-mini-LICENSE.txt`](../LICENSES/S1-mini-LICENSE.txt) |

The complete S1-mini license is 11,878 bytes with SHA-256
`d956d2d305a0639211c9cbde71501accb0e1474cc9ddf79a47820a522aff6f98`.
At the revisions above, the model-card and GGUF repositories publish
byte-identical license files. The additional term requires the original model
name and creator to remain identified with exact capitalization. The release
SBOM therefore uses the composite expression above and includes the full term
as extracted licensing information.

`Models/s1-mini-gguf.json` is the authoritative payload allowlist. Packaging
accepts exactly one regular GGUF file under `Resources/Models/s1-mini-gguf`,
rejects symlinks and siblings, and stores a byte-identical manifest under
`Resources/Models/Manifests`. S1-mini receives only the final English text; it
never receives microphone samples or live-preview snapshots.

The model is run through the committed, statically linked llama.cpp subset at
revision `9ee9fc04c136ef2ae729bfc60d18961b23c13ddf` (tag `b10524`). The packaged
Metal library is 8,445,925 bytes with SHA-256
`925c4db276d4459780420282e6f20a221d3b9f35f44b26b7ba55d82d5e381b74`.
`Vendor/LlamaLocal/FILES.json`, `Vendor/LlamaLocal/METALLIB.json`, and
`Research/s1-mini/production-metallib.json` record the source closure,
compiler inputs, and two byte-identical production rebuilds.

S1-mini is a generative normalizer, not a fact checker. VoxHearth validates its
output structurally and falls back to the command-stripped raw transcript if
cleanup is unavailable, times out, is cancelled, or yields unsafe output. It
may still make semantically plausible mistakes, so users should review text
before relying on it in consequential contexts.

The current production safety policy allows at most 42 input tokens in one
cleanup pass. Lists and emails above that cap fall back without generation.
Ordinary prose is split only at safe sentence boundaries; if no safe split
exists, the original transcript is inserted unchanged. This conservative cap
is derived from the passing 41-42-token semantic fixtures in the M5 spike; the
150-word fixtures completed quickly but did not pass the semantic ratchet. It
must not be raised without equivalent real-model evidence on the M2/16 GB
performance floor.
