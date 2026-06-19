// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SymairaKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TerminalCore", targets: ["TerminalCore"]),
        .library(name: "GhosttyBridge", targets: ["GhosttyBridge"]),
        .library(name: "AgentKit", targets: ["AgentKit"]),
        .library(name: "WorktreeKit", targets: ["WorktreeKit"]),
        .library(name: "ProviderKit", targets: ["ProviderKit"]),
        .library(name: "ContextBank", targets: ["ContextBank"]),
        .library(name: "StackKit", targets: ["StackKit"]),
        .library(name: "UsageKit", targets: ["UsageKit"]),
        .library(name: "SymairaUI", targets: ["SymairaUI"]),
        .library(name: "ControlKit", targets: ["ControlKit"]),
        .library(name: "MCPKit", targets: ["MCPKit"])
    ],
    dependencies: [
        // Engine pin — exact version on purpose, libghostty's API is not stable
        // yet (ADR-001). Upgrades are deliberate, tested steps.
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "1.2.4")
    ],
    targets: [
        // Engine-neutral terminal primitives: OSC parsing, sessions, env hygiene.
        .target(name: "TerminalCore"),

        // The ONLY target allowed to touch the GhosttyKit C API.
        .target(
            name: "GhosttyBridge",
            dependencies: [
                "TerminalCore",
                .product(name: "GhosttyKit", package: "libghostty-spm"),
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                .product(name: "GhosttyTheme", package: "libghostty-spm")
            ]
        ),

        .target(name: "AgentKit", dependencies: ["TerminalCore", "ProviderKit"]),
        .target(name: "WorktreeKit"),
        .target(name: "ProviderKit"),
        .target(name: "ContextBank"),
        .target(name: "StackKit"),
        .target(name: "UsageKit", resources: [.process("Resources")]),

        .target(
            name: "SymairaUI",
            dependencies: ["TerminalCore", "AgentKit", "WorktreeKit", "ProviderKit", "ContextBank", "StackKit", "UsageKit"]
        ),

        // Local headless control surface — observe and drive orchestration without the GUI.
        // Consumed by the symterminal CLI and the MCP server. See ADR-002 and
        // docs/design/agent-control-surface.md.
        .target(name: "ControlKit", dependencies: ["AgentKit"]),

        // MCP server for symterminal — exposes orchestration tools via MCP protocol.
        .target(name: "MCPKit", dependencies: ["ControlKit"]),

        // Command-line interface: `symterminal status [--json]`, `symterminal mcp`
        // Connect to a running Symaira Terminal instance via ControlKit.
        .executableTarget(name: "symterminal", dependencies: ["ControlKit", "MCPKit"]),

        // Manual GUI smoke check for the engine pipeline (not run in CI):
        // `swift run TerminalSmoke`
        .executableTarget(name: "TerminalSmoke", dependencies: ["GhosttyBridge"]),

        // M1 latency/throughput benchmark harness:
        // `swift run LatencyBench`
        .executableTarget(name: "LatencyBench", dependencies: ["GhosttyBridge", "TerminalCore"]),

        .testTarget(name: "TerminalCoreTests", dependencies: ["TerminalCore"]),
        .testTarget(name: "AgentKitTests", dependencies: ["AgentKit"]),
        .testTarget(name: "WorktreeKitTests", dependencies: ["WorktreeKit"]),
        .testTarget(name: "ProviderKitTests", dependencies: ["ProviderKit"]),
        .testTarget(name: "ContextBankTests", dependencies: ["ContextBank"]),
        .testTarget(name: "StackKitTests", dependencies: ["StackKit"]),
        .testTarget(name: "UsageKitTests", dependencies: ["UsageKit"]),
        .testTarget(name: "SymairaUITests", dependencies: ["SymairaUI"]),
        .testTarget(name: "ControlKitTests", dependencies: ["ControlKit"]),
        .testTarget(name: "MCPKitTests", dependencies: ["MCPKit"])
    ]
)
