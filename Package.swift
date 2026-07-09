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
    targets: [
        .executableTarget(
            name: "FeatureTTSReaderApp",
            path: "Sources/FeatureTTSReaderApp",
            resources: [.copy("Models")]
        )
    ]
)
