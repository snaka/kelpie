// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kelpie",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KelpieCore", targets: ["KelpieCore"]),
    ],
    targets: [
        .target(name: "KelpieCore"),
        .testTarget(name: "KelpieCoreTests", dependencies: ["KelpieCore"]),
    ]
)
