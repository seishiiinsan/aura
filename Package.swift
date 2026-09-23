// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Aura",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Aura", targets: ["Aura"]),
        .executable(name: "AuraInsights", targets: ["AuraInsights"]),
    ],
    targets: [
        // Shared activity history (SQLite) and statistics, used by both apps.
        .target(
            name: "AuraKit",
            path: "Sources/AuraKit",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // Menu bar app + main window: detects activities and updates Discord.
        .executableTarget(
            name: "Aura",
            dependencies: ["AuraKit"],
            path: "Sources/Aura",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Companion app exploring the activity history.
        .executableTarget(
            name: "AuraInsights",
            dependencies: ["AuraKit"],
            path: "Sources/AuraInsights",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AuraTests",
            dependencies: ["Aura", "AuraKit"],
            path: "Tests/AuraTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
