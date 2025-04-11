// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Linklab",
    platforms: [.iOS("14.3")],
    products: [
        .library(
            name: "Linklab",
            targets: ["Linklab"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Linklab",
            dependencies: []),
        .testTarget(
            name: "LinklabTests",
            dependencies: ["Linklab"]),
    ]
)
