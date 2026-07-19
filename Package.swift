// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HomeWave",
    platforms: [.macOS("14.2")],
    targets: [
        .target(name: "HomeWaveCore"),
        .executableTarget(
            name: "HomeWave",
            dependencies: ["HomeWaveCore"],
            exclude: ["Info.plist"]
        ),
        .executableTarget(name: "HomeWaveChecks", dependencies: ["HomeWaveCore"]),
    ]
)
