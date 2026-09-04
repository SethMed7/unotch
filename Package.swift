// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "uNotch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "uNotch", targets: ["uNotch"])
    ],
    targets: [
        .executableTarget(
            name: "uNotch",
            path: "Sources/uNotch"
        ),
        .testTarget(
            name: "uNotchTests",
            dependencies: ["uNotch"]
        )
    ]
)
