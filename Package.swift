// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoxHearth",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoxHearthCore", targets: ["VoxHearthCore"]),
        .library(name: "FluidAudioLocal", targets: ["FluidAudioLocal"]),
        .executable(name: "VoxHearth", targets: ["VoxHearthApp"]),
    ],
    targets: [
        .target(
            name: "FluidAudioLocal",
            path: "Vendor/FluidAudioLocal/Sources/FluidAudioLocal"
        ),
        .target(
            name: "VoxHearthCore",
            dependencies: ["FluidAudioLocal"]
        ),
        .executableTarget(
            name: "VoxHearthApp",
            dependencies: ["VoxHearthCore"]
        ),
        .testTarget(
            name: "VoxHearthCoreTests",
            dependencies: ["VoxHearthCore", "FluidAudioLocal"]
        ),
        .testTarget(
            name: "VoxHearthAppTests",
            dependencies: ["VoxHearthApp", "VoxHearthCore"]
        ),
        .testTarget(
            name: "VoxHearthLatencyEval",
            dependencies: ["VoxHearthCore"]
        ),
    ]
)
