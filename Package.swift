// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Proteus",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "ProteusCore", path: "Sources/ProteusCore"),
        .executableTarget(name: "Proteus", dependencies: ["ProteusCore"], path: "Sources/Proteus"),
        .testTarget(name: "ProteusCoreTests", dependencies: ["ProteusCore"], path: "Tests/ProteusCoreTests"),
    ]
)
