// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PrivateIndexIOS",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "PrivateIndexIOS", targets: ["PrivateIndexIOS"])
    ],
    dependencies: [
        .package(path: "../../Packages/PrivateIndexEngine")
    ],
    targets: [
        .target(
            name: "PrivateIndexIOS",
            dependencies: [
                .product(name: "PrivateIndexEngine", package: "PrivateIndexEngine")
            ],
            path: "Sources/PrivateIndexIOS"
        )
    ]
)
