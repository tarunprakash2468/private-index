// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PrivateIndexMac",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../Packages/PrivateIndexEngine")
    ],
    targets: [
        .executableTarget(
            name: "PrivateIndexMac",
            dependencies: [
                .product(name: "PrivateIndexEngine", package: "PrivateIndexEngine")
            ],
            path: "Sources/PrivateIndexMac"
        )
    ]
)
