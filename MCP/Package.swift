// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SpliceKitMCP",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "splicekit-mcp", targets: ["SpliceKitMCP"])],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .executableTarget(
            name: "SpliceKitMCP",
            dependencies: [.product(name: "MCP", package: "swift-sdk")],
            resources: [.copy("Catalog.json")]
        ),
        .testTarget(
            name: "SpliceKitMCPTests",
            dependencies: ["SpliceKitMCP", .product(name: "MCP", package: "swift-sdk")]
        ),
    ]
)
