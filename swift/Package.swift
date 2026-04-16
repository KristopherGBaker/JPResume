// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "JPResume",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "jpresume",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/JPResume"
        ),
        .testTarget(
            name: "JPResumeTests",
            dependencies: ["jpresume"],
            path: "Tests/JPResumeTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
