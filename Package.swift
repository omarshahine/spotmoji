// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Spotmoji",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Spotmoji", targets: ["Spotmoji"]),
    ],
    targets: [
        .executableTarget(
            name: "Spotmoji",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SpotmojiTests",
            dependencies: ["Spotmoji"]
        ),
    ]
)
