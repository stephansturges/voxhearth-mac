// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoxHearth",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoxHearthCore", targets: ["VoxHearthCore"]),
        .executable(name: "VoxHearth", targets: ["VoxHearthApp"]),
    ],
    targets: [
        .target(name: "VoxHearthCore"),
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
