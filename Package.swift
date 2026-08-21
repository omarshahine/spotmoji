// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Spotmoji",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Spotmoji", targets: ["Spotmoji"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "Spotmoji",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SpotmojiTests",
            dependencies: ["Spotmoji"]
        ),
    ]
)
