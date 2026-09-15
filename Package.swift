// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Linklab",
    platforms: [
        .iOS("14.3"),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "Linklab",
            targets: ["Linklab"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Linklab",
            dependencies: [],
            path: "Sources/Linklab",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "LinklabTests",
            dependencies: ["Linklab"],
            path: "Tests/LinklabTests"
        ),
    ]
)
