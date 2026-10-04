// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Orbit", targets: ["OrbitApp"]),
        .executable(name: "orbit-agent", targets: ["OrbitAgent"]),
        .executable(name: "orbitctl", targets: ["OrbitController"]),
        .library(name: "OrbitCore", targets: ["OrbitCore"]),
    ],
    targets: [
        .target(name: "OrbitCore"),
        .executableTarget(name: "OrbitAgent", dependencies: ["OrbitCore"]),
        .executableTarget(name: "OrbitController", dependencies: ["OrbitCore"]),
        .executableTarget(name: "OrbitApp", dependencies: ["OrbitCore"]),
        .testTarget(name: "OrbitCoreTests", dependencies: ["OrbitCore"]),
        .testTarget(name: "OrbitAgentTests", dependencies: ["OrbitAgent", "OrbitCore"]),
    ],
    swiftLanguageModes: [.v5]
)
