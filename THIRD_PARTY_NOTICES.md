# Third-party notices

This file covers material shipped in the VoxHearth binary distribution. It does
not replace the governing license texts under [`LICENSES/`](LICENSES).

## FluidAudio 0.15.5

- Project: FluidAudio
- Source: <https://github.com/FluidInference/FluidAudio>
- Exact revision: `19600a485baa4998812e4654b70d2bab8f2c9949`
- License: Apache License 2.0
- License text: [`LICENSES/FluidAudio-Apache-2.0.txt`](LICENSES/FluidAudio-Apache-2.0.txt)

VoxHearth builds an ASR-only subset adapted from this FluidAudio revision to
load and run the bundled Core ML speech model. The subset is committed under
`Vendor/FluidAudioLocal`, so every release source archive includes it. HTTP,
model download/cache, CLI, speech-synthesis, and unrelated model code are
omitted. `Vendor/FluidAudioLocal/UPSTREAM.md` records source-file provenance and
modification notices; VoxHearth integration and packaging are additional
changes.

FluidAudio includes the following notices in its pinned source tree. The
minimal `FluidAudioLocal` target does not compile or link these clustering
components, but VoxHearth preserves their exact upstream notices as a
conservative provenance record.

### fastcluster

Copyright:

- Through package version 1.1.23: © 2011 Daniel Müllner
- Changes from version 1.1.24 onward: © Google Inc.

License: BSD 2-Clause-style redistribution terms and disclaimer. The exact
upstream notice is reproduced at
[`LICENSES/fastcluster-LICENSE.md`](LICENSES/fastcluster-LICENSE.md).

### VBx / MachTaskSelf wrapper provenance

Copyright 2021–2024 BUT Speech@FIT (original VBx project).

License: Apache License 2.0. The exact upstream notice and license are
reproduced at [`LICENSES/vbx-LICENSE.md`](LICENSES/vbx-LICENSE.md).

## Parakeet-TDT-0.6B-v3 Core ML model

- Converted model: `FluidInference/parakeet-tdt-0.6b-v3-coreml`
- Exact revision: `aed02740059203c4a87495924f685de3722ae9ce`
- Converted-model source: <https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml>
- Base model: `nvidia/parakeet-tdt-0.6b-v3`
- Base-model source: <https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3>
- Base-model attribution: NVIDIA Corporation
- Core ML conversion attribution: FluidInference
- License applied by VoxHearth: Creative Commons Attribution 4.0 International
- License text: [`LICENSES/CC-BY-4.0.txt`](LICENSES/CC-BY-4.0.txt)

VoxHearth redistributes the pinned model files unchanged. It selects and
packages the exact payload documented in
[`Documentation/MODEL_PROVENANCE.md`](Documentation/MODEL_PROVENANCE.md); it
does not claim authorship, alter the weights, or imply endorsement by NVIDIA or
FluidInference.

The converted model card's metadata and its NVIDIA base-model declaration say
CC BY 4.0, while a prose footer in the converted card says Apache 2.0.
VoxHearth follows the more conservative CC BY 4.0 terms.

## Parakeet-TDT-CTC-110M Core ML model

- Converted model: `FluidInference/parakeet-tdt-ctc-110m-coreml`
- Exact revision: `9bc92ead6e8f17eca92a869fd578ae76842b82ba`
- Converted-model source: <https://huggingface.co/FluidInference/parakeet-tdt-ctc-110m-coreml>
- Base model: `nvidia/parakeet-tdt_ctc-110m`
- Base-model source: <https://huggingface.co/nvidia/parakeet-tdt_ctc-110m>
- Base-model attribution: NVIDIA Corporation
- Core ML conversion attribution: FluidInference
- License applied by VoxHearth: Creative Commons Attribution 4.0 International
- License text: [`LICENSES/CC-BY-4.0.txt`](LICENSES/CC-BY-4.0.txt)

VoxHearth redistributes the compact model files unchanged and records every
distributed byte in `Models/parakeet-tdt-ctc-110m-coreml.json`.

## S1-mini by Superwhisper

- Model: S1-mini by Superwhisper
- Model-card source: <https://huggingface.co/superwhisper/s1-mini>
- Exact model-card revision: `65f84bcda1d13df582c4a8443c1c5aa53c0c66db`
- Distributed GGUF source: <https://huggingface.co/superwhisper/s1-mini-GGUF>
- Exact GGUF revision: `8eab4779866f477ae6e7f237ca45fc2c65153f50`
- License expression used in the SBOM: `Apache-2.0 AND LicenseRef-S1-mini-Naming-Clause`
- Complete license text: [`LICENSES/S1-mini-LICENSE.txt`](LICENSES/S1-mini-LICENSE.txt)

VoxHearth redistributes the pinned Q4_K_M GGUF unchanged. The complete license
is 11,878 bytes with SHA-256
`d956d2d305a0639211c9cbde71501accb0e1474cc9ddf79a47820a522aff6f98`.
It contains Apache License 2.0 and an additional term requiring continued use
of the exact original identification “S1-mini” by “Superwhisper”. Accordingly,
VoxHearth presents the model as S1-mini by Superwhisper in the product,
documentation, notices, provenance, and SBOM. The complete additional term is
reproduced in the shipped license and as SPDX extracted licensing information;
it is not represented as plain Apache-2.0.

## Qwen3-0.6B base model

- Base model: `Qwen/Qwen3-0.6B`
- Exact reviewed revision: `c1899de289a04d12100db370d81485cdf75e47ca`
- Source: <https://huggingface.co/Qwen/Qwen3-0.6B>
- Relationship: S1-mini is a fine-tune of Qwen3-0.6B
- License: Apache License 2.0
- License text: [`LICENSES/Qwen3-0.6B-Apache-2.0.txt`](LICENSES/Qwen3-0.6B-Apache-2.0.txt)
- Copyright notice in the pinned license: Copyright 2024 Alibaba Cloud

The Qwen base-model weights are not packaged separately. This notice and
license preserve the provenance of the base model represented in the S1-mini
weights.

## llama.cpp runtime

- Project: llama.cpp
- Source: <https://github.com/ggml-org/llama.cpp>
- Exact revision: `9ee9fc04c136ef2ae729bfc60d18961b23c13ddf`
- Upstream tag: `b10524`
- License: MIT
- License text: [`LICENSES/llama.cpp-MIT.txt`](LICENSES/llama.cpp-MIT.txt)

VoxHearth compiles a manifest-locked local subset of llama.cpp/ggml and one
sealed Metal library. Runtime networking, model downloading, servers, dynamic
backend discovery, and runtime shader compilation are excluded. The included
source and local modifications are recorded in `Vendor/LlamaLocal/UPSTREAM.md`,
`Vendor/LlamaLocal/FILES.json`, and `Vendor/LlamaLocal/METALLIB.json`.

## Apple platform components

VoxHearth uses system frameworks supplied by macOS, including SwiftUI, AppKit,
AVFoundation, CoreAudio, Core ML, ApplicationServices, Carbon, ServiceManagement,
Foundation, and OSLog. They are not copied into this source repository as
third-party packages and remain subject to Apple's applicable platform terms.
