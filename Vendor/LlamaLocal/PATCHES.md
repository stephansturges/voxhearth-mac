# VoxHearth llama.cpp patch set

This directory is not a general-purpose llama.cpp distribution. The following
changes are intentional and are part of the pinned runtime contract.

## Static backend closure

- `ggml/src/ggml-backend-reg.cpp` registers CPU, Accelerate/BLAS, and Metal in
  a fixed table. Dynamic backend loading and discovery entry points are inert.
- Unused public backend headers and the dynamic-loader implementation are not
  vendored.
- `src/llama-model.cpp` constructs Qwen3 only. Other architecture factory
  cases are compile-time excluded, and only `src/models/qwen3.cpp` is present.
- Model saving and quantization implementations are not vendored. Session/model
  file-save entry points fail closed, gguf file writers are inert, and the
  shared file helper permits read-binary mode only. In-memory state APIs remain.
- `include/LlamaLocal.h` is a local umbrella header for the minimal C API.

## Sealed Metal runtime

- `ggml/src/ggml-metal/ggml-metal-device.m` opens exactly
  `Bundle.main.resourceURL/Metal/ggml-llama.metallib`, requires a regular file,
  and creates the library only from that URL.
- Runtime Metal source compilation, embedded-source fallback,
  executable-directory lookup, default-library lookup, and environment-selected
  paths are removed. `ggml_metal_library_init_from_source` is an inert ABI stub.
- Tensor/BF16 capabilities are derived from the Metal device family and the
  sealed metallib instead of compiling probe kernels at runtime.

## Fixed production policy

All environment-variable steering was replaced by fixed or explicit API
policy in the patched ggml/llama sources. Debug/capture/trace switches are off;
supported fusion and graph optimizations are on; device selection is the
default Metal device; graph reuse follows explicit request parameters; and no
driver environment is mutated. The checker requires zero `getenv(` and no
`setenv(` in this closure.

## Offline and privacy hardening

- Android `dlopen`/`dlsym` and backtrace-loading code is removed.
- Runtime error/help strings containing remote URLs are replaced with local,
  content-free guidance.
- The vendored closure has no downloader, HTTP, DNS, socket, telemetry,
  updater, server, RPC, or durable user-text persistence component.

## Files patched from upstream

The byte manifest marks the following paths as `patched`:

- `ggml/src/ggml-backend-meta.cpp`
- `ggml/src/ggml-backend-reg.cpp`
- `ggml/src/ggml-backend.cpp`
- `ggml/src/ggml-cpu/ggml-cpu.c`
- `ggml/src/ggml-cpu/ggml-cpu.cpp`
- `ggml/src/ggml-cpu/arch/arm/quants.c` (trailing blank-line cleanup)
- `ggml/src/ggml-cpu/unary-ops.cpp` (trailing blank-line cleanup)
- `ggml/src/ggml-cpu/vec.h`
- `ggml/src/ggml-metal/ggml-metal-context.m`
- `ggml/src/ggml-metal/ggml-metal-device.m`
- `ggml/src/ggml-metal/ggml-metal-ops.cpp`
- `ggml/src/ggml-metal/ggml-metal.cpp`
- `ggml/src/ggml.c`
- `ggml/src/ggml.cpp`
- `ggml/src/gguf.cpp`
- `src/llama-batch.cpp`
- `src/llama-context.cpp`
- `src/llama-graph.cpp`
- `src/llama-graph.h`
- `src/llama-grammar.cpp` (trailing blank-line cleanup)
- `src/llama-kv-cache-dsv4.cpp`
- `src/llama-kv-cache-iswa.cpp`
- `src/llama-kv-cache.cpp`
- `src/llama-model-loader.cpp`
- `src/llama-model.cpp`
- `src/llama-mmap.cpp`
- `src/llama.cpp`

The local-only file is `include/LlamaLocal.h`. All other manifest entries are
byte-identical excerpts of the pinned upstream commit.
