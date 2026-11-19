// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SoundIsle",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SoundIsleCore", targets: ["SoundIsleCore"]),
        .executable(name: "SoundIsle", targets: ["SoundIsle"]),
    ],
    targets: [
        .target(name: "SoundIsleCore"),
        .executableTarget(name: "SoundIsle", dependencies: ["SoundIsleCore"]),
        .testTarget(name: "SoundIsleCoreTests", dependencies: ["SoundIsleCore"]),
        .testTarget(name: "SoundIsleAppTests", dependencies: ["SoundIsle", "SoundIsleCore"]),
    ]
)
