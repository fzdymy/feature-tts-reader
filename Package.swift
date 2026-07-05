// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FeatureTTSReader",
    platforms: [
        .iOS(.v18)
    ],
    dependencies: [
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main"),
    ],
    products: [
        .executable(
            name: "FeatureTTSReader",
            targets: ["FeatureTTSReaderApp"]
        )
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
