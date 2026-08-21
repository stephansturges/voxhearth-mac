// swift-tools-version: 6.0

import PackageDescription

let llamaLocalSources = [
    "ggml/src/ggml.c",
    "ggml/src/ggml.cpp",
    "ggml/src/ggml-alloc.c",
    "ggml/src/ggml-backend.cpp",
    "ggml/src/ggml-backend-meta.cpp",
    "ggml/src/ggml-backend-reg.cpp",
    "ggml/src/ggml-opt.cpp",
    "ggml/src/ggml-threading.cpp",
    "ggml/src/ggml-quants.c",
    "ggml/src/gguf.cpp",
    "ggml/src/ggml-cpu/ggml-cpu.c",
    "ggml/src/ggml-cpu/ggml-cpu.cpp",
    "ggml/src/ggml-cpu/repack.cpp",
    "ggml/src/ggml-cpu/hbm.cpp",
    "ggml/src/ggml-cpu/quants.c",
    "ggml/src/ggml-cpu/traits.cpp",
    "ggml/src/ggml-cpu/binary-ops.cpp",
    "ggml/src/ggml-cpu/unary-ops.cpp",
    "ggml/src/ggml-cpu/vec.cpp",
    "ggml/src/ggml-cpu/ops.cpp",
    "ggml/src/ggml-cpu/llamafile/sgemm.cpp",
    "ggml/src/ggml-cpu/arch/arm/cpu-feats.cpp",
    "ggml/src/ggml-cpu/arch/arm/quants.c",
    "ggml/src/ggml-cpu/arch/arm/repack.cpp",
    "ggml/src/ggml-blas/ggml-blas.cpp",
    "ggml/src/ggml-metal/ggml-metal.cpp",
    "ggml/src/ggml-metal/ggml-metal-device.m",
    "ggml/src/ggml-metal/ggml-metal-device.cpp",
    "ggml/src/ggml-metal/ggml-metal-common.cpp",
    "ggml/src/ggml-metal/ggml-metal-context.m",
    "ggml/src/ggml-metal/ggml-metal-ops.cpp",
    "src/llama.cpp",
    "src/llama-adapter.cpp",
    "src/llama-arch.cpp",
    "src/llama-batch.cpp",
    "src/llama-chat.cpp",
    "src/llama-context.cpp",
    "src/llama-cparams.cpp",
    "src/llama-grammar.cpp",
    "src/llama-graph.cpp",
    "src/llama-hparams.cpp",
    "src/llama-impl.cpp",
    "src/llama-io.cpp",
    "src/llama-kv-cache.cpp",
    "src/llama-kv-cache-iswa.cpp",
    "src/llama-kv-cache-dsa.cpp",
    "src/llama-kv-cache-msa.cpp",
    "src/llama-kv-cache-dsv4.cpp",
    "src/llama-memory.cpp",
    "src/llama-memory-hybrid.cpp",
    "src/llama-memory-hybrid-iswa.cpp",
    "src/llama-memory-recurrent.cpp",
    "src/llama-mmap.cpp",
    "src/llama-model-loader.cpp",
    "src/llama-model.cpp",
    "src/llama-sampler.cpp",
    "src/llama-vocab.cpp",
    "src/unicode-data.cpp",
    "src/unicode.cpp",
    "src/models/qwen3.cpp",
]

let llamaLocalCDefinitions: [CSetting] = [
    .define("GGML_COMMIT", to: "\"9ee9fc0\""),
    .define("GGML_SCHED_MAX_COPIES", to: "4"),
    .define("GGML_VERSION", to: "\"0.20.2\""),
    .define("GGML_METAL_EMBED_LIBRARY", to: "0"),
    .define("_DARWIN_C_SOURCE"),
    .define("_XOPEN_SOURCE", to: "600"),
]

let llamaLocalCXXDefinitions: [CXXSetting] = [
    .define("ACCELERATE_LAPACK_ILP64"),
    .define("ACCELERATE_NEW_LAPACK"),
    .define("GGML_BLAS_USE_ACCELERATE"),
    .define("GGML_COMMIT", to: "\"9ee9fc0\""),
    .define("GGML_SCHED_MAX_COPIES", to: "4"),
    .define("GGML_USE_ACCELERATE"),
    .define("GGML_USE_BLAS"),
    .define("GGML_USE_CPU"),
    .define("GGML_USE_CPU_REPACK"),
    .define("GGML_USE_LLAMAFILE"),
    .define("GGML_USE_METAL"),
    .define("GGML_VERSION", to: "\"0.20.2\""),
    .define("GGML_METAL_EMBED_LIBRARY", to: "0"),
    .define("LLAMA_COMMIT", to: "\"9ee9fc0\""),
    .define("LLAMA_VERSION", to: "\"0.1.2-dev\""),
    .define("_DARWIN_C_SOURCE"),
    .define("_XOPEN_SOURCE", to: "600"),
]

let package = Package(
    name: "VoxHearth",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoxHearthCore", targets: ["VoxHearthCore"]),
        .library(name: "FluidAudioLocal", targets: ["FluidAudioLocal"]),
        .library(name: "LlamaLocal", targets: ["LlamaLocal"]),
        .executable(name: "VoxHearth", targets: ["VoxHearthApp"]),
    ],
    targets: [
        .target(
            name: "FluidAudioLocal",
            path: "Vendor/FluidAudioLocal/Sources/FluidAudioLocal"
        ),
        .target(
            name: "LlamaLocal",
            path: "Vendor/LlamaLocal",
            sources: llamaLocalSources,
            publicHeadersPath: "include",
            cSettings: llamaLocalCDefinitions + [
                .headerSearchPath("ggml/include"),
                .headerSearchPath("ggml/src"),
                .headerSearchPath("ggml/src/ggml-cpu"),
                .headerSearchPath("ggml/src/ggml-blas"),
                .headerSearchPath("ggml/src/ggml-metal"),
                .headerSearchPath("src"),
                .unsafeFlags(["-fno-objc-arc"]),
            ],
            cxxSettings: llamaLocalCXXDefinitions + [
                .headerSearchPath("ggml/include"),
                .headerSearchPath("ggml/src"),
                .headerSearchPath("ggml/src/ggml-cpu"),
                .headerSearchPath("ggml/src/ggml-blas"),
                .headerSearchPath("ggml/src/ggml-metal"),
                .headerSearchPath("src"),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),
        .target(
            name: "VoxHearthCore",
            dependencies: ["FluidAudioLocal", "LlamaLocal"]
        ),
        .executableTarget(
            name: "VoxHearthApp",
            dependencies: ["VoxHearthCore"]
        ),
        .testTarget(
            name: "VoxHearthCoreTests",
            dependencies: ["VoxHearthCore", "FluidAudioLocal"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "VoxHearthAppTests",
            dependencies: ["VoxHearthApp", "VoxHearthCore"]
        ),
        .testTarget(
            name: "VoxHearthLatencyEval",
            dependencies: ["VoxHearthCore"]
        ),
    ],
    cLanguageStandard: .gnu11,
    cxxLanguageStandard: .cxx17
)
