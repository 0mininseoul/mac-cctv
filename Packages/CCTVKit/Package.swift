// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CCTVKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "CCTVKit",
            targets: ["CCTVKit"]
        )
    ],
    targets: [
        .target(name: "CCTVKit"),
        .testTarget(
            name: "CCTVKitTests",
            dependencies: ["CCTVKit"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
