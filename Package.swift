// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoxHearth",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoxHearthCore", targets: ["VoxHearthCore"]),
        .executable(name: "VoxHearth", targets: ["VoxHearthApp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            revision: "19600a485baa4998812e4654b70d2bab8f2c9949"
        ),
    ],
    targets: [
        .target(
            name: "VoxHearthCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .executableTarget(
            name: "VoxHearthApp",
            dependencies: ["VoxHearthCore"]
        ),
        .testTarget(
            name: "VoxHearthCoreTests",
            dependencies: ["VoxHearthCore"]
        ),
    ]
)
