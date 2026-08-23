#pragma once

// llama.h already exposes the complete C API closure needed by Swift. Keep
// this umbrella C-only: importing ggml-cpp.h makes Clang build the Swift module
// as C and fails on the C++ standard library.
#include "llama.h"
#include "ggml.h"
#include "ggml-alloc.h"
#include "ggml-backend.h"
#include "ggml-blas.h"
#include "ggml-cpu.h"
#include "ggml-metal.h"
#include "ggml-opt.h"
#include "gguf.h"
