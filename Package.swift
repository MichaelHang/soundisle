// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SoundIsle",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SoundIsleCore", targets: ["SoundIsleCore"]),
        .executable(name: "Kongshan", targets: ["Kongshan"]),
    ],
    targets: [
        .target(name: "SoundIsleCore"),
        .executableTarget(name: "Kongshan", dependencies: ["SoundIsleCore"]),
        .testTarget(name: "SoundIsleCoreTests", dependencies: ["SoundIsleCore"]),
        .testTarget(name: "KongshanAppTests", dependencies: ["Kongshan", "SoundIsleCore"]),
    ]
)
