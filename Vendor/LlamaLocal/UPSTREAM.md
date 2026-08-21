# LlamaLocal upstream provenance

`LlamaLocal` is a source-vendored, deliberately reduced copy of llama.cpp for
VoxHearth's local S1-mini cleanup runtime.

- Upstream repository: <https://github.com/ggml-org/llama.cpp>
- Upstream tag: `b10524`
- Upstream commit: `9ee9fc04c136ef2ae729bfc60d18961b23c13ddf`
- Upstream version macros: llama.cpp `0.1.2-dev`, ggml `0.20.2`
- License: MIT; the byte-identical upstream license is stored at
  `LICENSES/llama.cpp-MIT.txt`.

The imported closure contains only the Qwen3 model implementation and the
CPU, Accelerate/BLAS, and Metal backends required by VoxHearth. It excludes the
upstream applications, common CLI helpers, downloaders, server, RPC,
subprocess support, examples, tests, dynamic backend loader, and unrelated
accelerator backends.

`FILES.json` pins every runtime source/header byte and the explicit SwiftPM
compiled-source list. `PATCHES.md` describes the security and scope patches.
Run `python3 scripts/check-vendored-llama.py` after any change. An upstream
update is a reviewed re-vendoring operation: update the pin, reapply or revise
the documented patches, regenerate the manifest, and repeat all runtime,
security, Metal, model, and package evidence.
