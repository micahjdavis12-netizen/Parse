// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ParseCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "ParseCore", targets: ["ParseCore"])
    ],
    targets: [
        .target(
            name: "ParseCore"
        ),
        .testTarget(
            name: "ParseCoreTests",
            dependencies: ["ParseCore"]
        )
    ]
)
