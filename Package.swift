// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenRecord",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "OpenRecord", targets: ["OpenRecord"]),
        .executable(name: "openrecord-mcp", targets: ["OpenRecordMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        // swift-log 1.17 uses `@nonexhaustive`, which needs a newer compiler than Swift 6.2 (Xcode 26.1).
        .package(url: "https://github.com/apple/swift-log.git", "1.6.0"..<"1.17.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "OpenRecordCore"),
        .target(
            name: "OpenRecordMCPServer",
            dependencies: ["OpenRecordCore", .product(name: "MCP", package: "swift-sdk")]
        ),
        .executableTarget(name: "OpenRecord", dependencies: ["OpenRecordCore", .product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(
            name: "OpenRecordMCP",
            dependencies: ["OpenRecordMCPServer", .product(name: "MCP", package: "swift-sdk")]
        ),
        .target(name: "OpenRecordTestSupport", dependencies: ["OpenRecordCore"], path: "Tests/OpenRecordTestSupport"),
        .testTarget(name: "OpenRecordCoreTests", dependencies: ["OpenRecordCore", "OpenRecordTestSupport"]),
        .testTarget(
            name: "OpenRecordMCPServerTests",
            dependencies: ["OpenRecordMCPServer", "OpenRecordTestSupport", .product(name: "MCP", package: "swift-sdk")]
        ),
    ]
)
