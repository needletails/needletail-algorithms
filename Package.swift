// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "needletail-algorithms",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NeedleTailAlgorithms",
            targets: [
                "NeedleTailAsyncSequence",
                "NeedleTailQueue",
                "NTExtensions"
            ]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", .upToNextMajor(from: "1.2.0")),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "1.2.0")),
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "2.65.0")),
        .package(url: "https://github.com/orlandos-nl/BSON.git", from: "8.1.0"),
        .package(url: "git@github.com:needle-tail/needletail-logger.git", .upToNextMajor(from: "1.0.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NeedleTailAsyncSequence",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "NeedleTailLogger", package: "needletail-logger")
            ]
        ),
        .target(name: "NeedleTailQueue"),
        .target(
            name: "NTExtensions",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "BSON", package: "BSON"),
                .product(name: "NeedleTailLogger", package: "needletail-logger")
            ]
        ),
        .testTarget(
            name: "NeedleTailAsyncSequenceTests",
            dependencies: ["NeedleTailAsyncSequence"]),
    ]
)
