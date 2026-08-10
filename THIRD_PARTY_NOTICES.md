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

## Apple platform components

VoxHearth uses system frameworks supplied by macOS, including SwiftUI, AppKit,
AVFoundation, CoreAudio, Core ML, ApplicationServices, Carbon, ServiceManagement,
Foundation, and OSLog. They are not copied into this source repository as
third-party packages and remain subject to Apple's applicable platform terms.
