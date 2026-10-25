// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PrivateIndexEngine",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "PrivateIndexEngine",
            targets: ["PrivateIndexEngine"]
        ),
        .executable(
            name: "private-index-cli",
            targets: ["private-index-cli"]
        ),
    ],
    targets: [
        // C target: vendored sqlite-vec amalgamation linked against system libsqlite3
        .target(
            name: "CSQLiteVec",
            path: "Sources/CSQLiteVec",
            publicHeadersPath: "include",
            cSettings: [
                // Compile as a built-in extension (uses sqlite3.h, not sqlite3ext.h)
                .define("SQLITE_CORE"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        // Main Swift library
        .target(
            name: "PrivateIndexEngine",
            dependencies: ["CSQLiteVec"],
            path: "Sources/PrivateIndexEngine",
            resources: [
                .process("Resources/vocab.txt")
            ]
        ),
        // Developer CLI
        .executableTarget(
            name: "private-index-cli",
            dependencies: ["PrivateIndexEngine"],
            path: "Sources/private-index-cli"
        ),
        // Unit tests
        .testTarget(
            name: "PrivateIndexEngineTests",
            dependencies: ["PrivateIndexEngine"],
            path: "Tests/PrivateIndexEngineTests"
        ),
    ]
)
