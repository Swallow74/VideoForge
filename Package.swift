// swift-tools-version: 6.0

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency")
]

let package = Package(
    name: "VideoEdit",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "VideoEditCore", targets: ["VideoEditCore"]),
        .library(name: "MLXWhisper", targets: ["MLXWhisper"]),
        .executable(name: "VideoEdit", targets: ["VideoEdit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.10.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "VideoEditCore",
            dependencies: [],
            path: "Sources/VideoEditCore"
        ),
        .target(
            name: "MLXWhisper",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "Transformers", package: "swift-transformers"),
            ],
            path: "Sources/MLXWhisper",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
    name: "VideoForge",
            dependencies: [
                .target(name: "VideoEditCore"),
                .target(name: "MLXWhisper"),
            ],
            path: "Sources/VideoEdit"
        ),
        .testTarget(
            name: "VideoEditCoreTests",
            dependencies: [
                .target(name: "VideoEditCore"),
            ],
            path: "Tests/VideoEditCoreTests"
        ),
    ]
)