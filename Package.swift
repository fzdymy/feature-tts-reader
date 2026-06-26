// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FeatureTTSReader",
    platforms: [
        .iOS(.v17)
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
            path: "Sources/FeatureTTSReaderApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
