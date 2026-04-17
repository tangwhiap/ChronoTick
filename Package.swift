// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChronoTick",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ChronoTick", targets: ["ChronoTick"])
    ],
    targets: [
        .executableTarget(
            name: "ChronoTick",
            path: "ChronoTick"
        ),
        .testTarget(
            name: "ChronoTickTests",
            dependencies: ["ChronoTick"],
            path: "ChronoTickTests"
        )
    ]
)
