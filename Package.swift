// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kelpie",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KelpieCore", targets: ["KelpieCore"]),
        .library(name: "KelpieClient", targets: ["KelpieClient"]),
    ],
    targets: [
        .target(name: "KelpieCore"),
        .target(name: "KelpieClient", dependencies: ["KelpieCore"]),
        .testTarget(name: "KelpieCoreTests", dependencies: ["KelpieCore"]),
        .testTarget(name: "KelpieClientTests", dependencies: ["KelpieClient"]),
    ]
)
