// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EPUBTranslatorHeadlessTests",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "EPUBTranslatorApp", targets: ["EPUBTranslatorApp"]),
        .executable(name: "EPUBTranslatorHelper", targets: ["EPUBTranslatorHelper"]),
    ],
    targets: [
        .target(
            name: "EPUBTranslatorApp",
            path: "app/macOS/Sources/EPUBTranslatorApp",
            exclude: [
                "Assets.xcassets",
                "EPUBTranslatorApp.swift",
            ]
        ),
        .executableTarget(
            name: "EPUBTranslatorHelper",
            path: "app/macOS/Sources/EPUBTranslatorHelper"
        ),
        .testTarget(
            name: "EPUBTranslatorTests",
            dependencies: ["EPUBTranslatorApp"],
            path: "app/macOS/Tests/EPUBTranslatorTests"
        ),
    ]
)
