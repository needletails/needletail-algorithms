// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "needletail-algorithms",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NeedleTailAlgorithms",
            targets: [
                "NeedleTailAsyncSequence",
                "NeedleTailQueue",
                "NTKLoop"
            ]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.3"),
        .package(url: "https://github.com/needletails/needletail-logger.git", from: "3.1.1")
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
                .product(name: "NeedleTailLogger", package: "needletail-logger"),
                .product(name: "Collections", package: "swift-collections")
            ]
        ),
        .target(name: "NeedleTailQueue", dependencies: [.product(name: "Collections", package: "swift-collections")]),
        .target(name: "NTKLoop"),
        .testTarget(
            name: "NeedleTailAsyncSequenceTests",
            dependencies: ["NeedleTailAsyncSequence"]),
    ]
)
