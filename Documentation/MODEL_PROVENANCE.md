# Model provenance and attribution

VoxHearth release builds contain two selectable Core ML conversions of NVIDIA
Parakeet automatic-speech-recognition models. Both run entirely on the Mac.

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
