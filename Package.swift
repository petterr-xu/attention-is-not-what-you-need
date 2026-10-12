// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Attention",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Attention", targets: ["Attention"]),
        .executable(name: "attention-mcp", targets: ["AttentionMCP"])
    ],
    targets: [
        // 共享控制协议与本地传输层：不依赖 AppKit / Combine，app 与 MCP 桥接都用它
        .target(
            name: "AttentionControl",
            path: "Sources/AttentionControl"
        ),
        .executableTarget(
            name: "Attention",
            dependencies: ["AttentionControl"],
            path: "Sources/Attention"
        ),
        // MCP 协议层：纯逻辑、无 I/O，独立成库以便直接单测
        .target(
            name: "AttentionMCPCore",
            dependencies: ["AttentionControl"],
            path: "Sources/AttentionMCPCore"
        ),
        .executableTarget(
            name: "AttentionMCP",
            dependencies: ["AttentionMCPCore"],
            path: "Sources/AttentionMCP"
        ),
        .testTarget(
            name: "AttentionTests",
            dependencies: ["Attention", "AttentionControl"],
            path: "Tests/AttentionTests"
        ),
        .testTarget(
            name: "AttentionControlTests",
            dependencies: ["AttentionControl", "AttentionMCPCore"],
            path: "Tests/AttentionControlTests"
        )
    ]
)
