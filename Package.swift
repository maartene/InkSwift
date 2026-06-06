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
        .library(
            name: "SwiftInkRuntime",
            targets: ["SwiftInkRuntime"]),
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
                .process("ink-full.js")
            ]
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
        ),
        .target(
            name: "SwiftInkRuntime",
            dependencies: [],
            resources: [
                .process("test.ink.json")
            ]
        ),
        .testTarget(
            name: "SwiftInkRuntimeTests",
            dependencies: [
                "SwiftInkRuntime",
                .target(name: "InkSwift", condition: .when(platforms: [.macOS])),
                "JSONEquality"
            ],
            exclude: [
                "slice01-once-only.ink",
                "slice02-conditional.ink",
                "slice03-read-counts.ink",
                "slice04-invisible-defaults.ink",
                "slice-c1-inline-conditionals.ink",
                "slice-c2-block-conditionals.ink",
                "slice-c3-functions.ink",
                "slice-t1-tunnels.ink",
                "slice-t2-nested-tunnels.ink",
                "slice-t3-ref-params.ink",
                "slice-bug-glue-after-choice.ink",
            ],
            resources: [
                .process("test.ink.json"),
                .process("slice01-once-only.ink.json"),
                .process("slice02-conditional.ink.json"),
                .process("slice03-read-counts.ink.json"),
                .process("slice04-invisible-defaults.ink.json"),
                .process("slice-c1-inline-conditionals.ink.json"),
                .process("slice-c2-block-conditionals.ink.json"),
                .process("slice-c3-functions.ink.json"),
                .process("slice-t1-tunnels.ink.json"),
                .process("slice-t2-nested-tunnels.ink.json"),
                .process("slice-t3-ref-params.ink.json"),
                .process("slice-bug-glue-after-choice.ink.json"),
                .process("TheIntercept.ink.json"),
                .process("TheIntercept_oracle_walkthrough.json"),
            ]
        ),
    ]
)
