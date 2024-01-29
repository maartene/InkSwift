// swift-tools-version:5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "InkSwift",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "InkSwift",
            targets: ["InkSwift"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
         .package(url: "https://github.com/jectivex/JXKit.git", .upToNextMajor(from: "3.0.0")),
         .package(url: "https://github.com/neallester/JSONEquality.git", branch: "master"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "InkSwift",
            dependencies: ["JXKit"],
            resources: [
                .process("ink-full.js")]
        ),
        .testTarget(
            name: "InkSwiftTests",
            dependencies: ["InkSwift", "JSONEquality"],
            resources: [
                .process("test.ink"),
                .process("test.ink.json"),
                .process("compare.json"),
                .process("TheIntercept.ink"),
            ]
        )
    ]
)
