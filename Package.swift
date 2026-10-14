// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AlcoveRecreation",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "AlcoveRecreation",
            path: "Sources/AlcoveRecreation",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
