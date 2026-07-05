// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeatureTTSReader",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .executable(
            name: "FeatureTTSReader",
            targets: ["FeatureTTSReaderApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "FeatureTTSReaderApp",
            dependencies: [
                .product(name: "CosyVoiceTTS", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
            ],
            path: "Sources/FeatureTTSReaderApp",
            resources: [.copy("Models")]
        )
    ]
)
