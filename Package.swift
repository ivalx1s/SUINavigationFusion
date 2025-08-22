// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SUINavigationFusion",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SUINavigationFusion",
            type: .dynamic,
            targets: ["SUINavigationFusion"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SUINavigationFusion",
            path: "Sources"
        )
    ]
)
