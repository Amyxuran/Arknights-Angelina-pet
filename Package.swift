// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LimeCourier",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LimeCourier", targets: ["LimeCourier"])
    ],
    targets: [
        .executableTarget(
            name: "LimeCourier",
            path: "Sources/LimeCourier"
        ),
        .testTarget(
            name: "LimeCourierTests",
            dependencies: ["LimeCourier"],
            path: "Tests/LimeCourierTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
